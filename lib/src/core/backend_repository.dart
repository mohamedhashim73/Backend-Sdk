import '../contracts/data_backend.dart';
import '../contracts/data_query_spec.dart';
import '../contracts/pagination_backend.dart';
import '../core/backend_logger.dart';
import '../core/backend_resource.dart';
import '../core/resource_codec.dart';
import '../errors/backend_error_mapper.dart';
import '../errors/backend_error_type.dart';
import '../errors/backend_failure.dart';
import '../filters/filter_condition.dart';
import '../filters/filter_operator.dart';
import '../filters/sort_condition.dart';
import '../pagination/cursor_page_result.dart';
import '../pagination/cursor_request.dart';
import '../pagination/page_request.dart';
import '../pagination/page_result.dart';
import '../pagination/pagination_limits.dart';
import '../result/backend_result.dart';
import '../retry/cancellation_token.dart';
import '../retry/request_executor.dart';

/// The shared CRUD, pagination, search, sort and soft-delete engine behind every
/// module repository.
///
/// A module supplies a [ResourceCodec] and gets all of the behaviour for free.
/// Keeping this logic in one place is what guarantees that pagination arithmetic,
/// ordering stability and duplicate-load protection are identical for products,
/// users and every module added later.
///
/// This class is generic and provider-agnostic. It never sees a table name, a
/// provider exception, or a raw record outside the codec boundary.
class BackendRepository<TModel extends Object, TCreate extends Object,
    TUpdate extends Object> {
  /// The provider-facing data backend.
  final DataBackend backend;

  /// The model/record translation for this module.
  final ResourceCodec<TModel, TCreate, TUpdate> codec;

  /// The timeout, retry and cancellation pipeline.
  final RequestExecutor executor;

  /// The logger for diagnostics.
  final BackendLogger logger;

  /// The clock used for soft-delete timestamps. Defaults to [DateTime.now].
  ///
  /// Injected so tests can assert an exact soft-delete value.
  final DateTime Function() clock;

  final Set<String> _inFlightPages = <String>{};

  /// Creates a repository for one module.
  BackendRepository({
    required this.backend,
    required this.codec,
    required this.executor,
    this.logger = const NoopBackendLogger(),
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now {
    descriptor.validate();
  }

  /// Returns the current UTC time, used as the soft-delete marker.
  DateTime now() => clock().toUtc();

  /// The resource this repository operates on.
  BackendResourceDescriptor get descriptor => codec.descriptor;

  /// The legacy built-in resource, when one exists.
  BackendResource get resource =>
      descriptor.resource ??
      (throw StateError(
        'Application-defined repositories use descriptor, not the legacy '
        'BackendResource enum.',
      ));

  String get resourceKey => descriptor.key;

  /// Reads a single record by primary key.
  ///
  /// Returns a `notFound` failure when the record does not exist, is
  /// soft-deleted, or is not visible to the current user under row level
  /// security.
  Future<BackendResult<TModel>> getById(
    String id, {
    CancellationToken? cancellationToken,
  }) async {
    if (id.trim().isEmpty) {
      return failureOf(_validation('An id is required.'));
    }

    final result = await executor.run<BackendRecord>(
      operation: '$resourceKey.getById',
      fallbackErrorType: BackendErrorType.database,
      cancellationToken: cancellationToken,
      action: () async => unwrap(
        await backend.getById(resource: descriptor, id: id.trim()),
      ),
    );

    return _decodeFirst(result);
  }

  /// Reads one offset-paginated page.
  ///
  /// Applies the module's searchable columns to [PageRequest.search], makes the
  /// ordering deterministic, converts the page to an inclusive backend range, and
  /// decodes every row. Concurrent identical requests are collapsed so a
  /// double-tap or a rebuilt widget cannot fire two network calls.
  Future<BackendResult<PageResult<TModel>>> getPage({
    required PageRequest request,
    CancellationToken? cancellationToken,
  }) async {
    final invalid = _validatePageRequest(request);
    if (invalid != null) {
      return failureOf(invalid);
    }

    final key = '$resourceKey#${request.cacheKey}';
    if (!_inFlightPages.add(key)) {
      logger.debug(
        'Skipping a duplicate in-flight page load.',
        context: {'resource': resourceKey, 'page': request.page},
      );
      return failureOf(
        BackendErrorClassifier.build(
          type: BackendErrorType.conflict,
          message: 'Page ${request.page} of $resourceKey is already being '
              'loaded. Await the in-flight request before requesting it again.',
        ),
      );
    }

    try {
      final spec = _buildSpec(request);
      final result = await executor.run<PageResult<BackendRecord>>(
        operation: '$resourceKey.getPage',
        fallbackErrorType: BackendErrorType.database,
        cancellationToken: cancellationToken,
        action: () async =>
            unwrap(await backend.getPage(resource: descriptor, spec: spec)),
      );

      return result.map((page) {
        final decoded = <TModel>[];
        for (final record in page.items) {
          final model = codec.decode(record);
          final failure = model.failure;
          if (failure != null) {
            logger.warn(
              'Skipping an undecodable record.',
              context: {'resource': resourceKey, 'reason': failure.message},
            );
            continue;
          }
          final value = model.data;
          if (value != null) decoded.add(value);
        }
        return PageResult<TModel>(
          items: List<TModel>.unmodifiable(decoded),
          page: page.page,
          pageSize: page.pageSize,
          hasMore: page.hasMore,
          totalCount: page.totalCount,
        );
      });
    } finally {
      _inFlightPages.remove(key);
    }
  }

  /// Reads one cursor-paginated page.
  ///
  /// Prefer this over [getPage] for large or frequently changing datasets,
  /// because the backend seeks to the cursor instead of skipping every preceding
  /// row.
  Future<BackendResult<CursorPageResult<TModel>>> getCursorPage({
    required CursorRequest request,
    CancellationToken? cancellationToken,
  }) async {
    final invalid = _validateCursorRequest(request);
    if (invalid != null) {
      return failureOf(invalid);
    }

    final spec = DataQuerySpec(
      from: 0,
      to: request.limit - 1,
      search: request.search,
      filters: List<FilterCondition>.unmodifiable(request.filters),
      sorting: codec.descriptor.stableSorting(request.sorting),
      includeTotalCount: request.includeTotalCount,
    );

    final result = await executor.run<CursorPageResult<BackendRecord>>(
      operation: '$resourceKey.getCursorPage',
      fallbackErrorType: BackendErrorType.database,
      cancellationToken: cancellationToken,
      action: () async => unwrap(
        await backend.getCursorPage(
          resource: descriptor,
          cursor: request.cursor,
          spec: spec,
        ),
      ),
    );

    return result.map((page) {
      final decoded = <TModel>[];
      for (final record in page.items) {
        final model = codec.decode(record);
        if (model.failure == null && model.data != null) {
          decoded.add(model.data!);
        }
      }
      return CursorPageResult<TModel>(
        items: List<TModel>.unmodifiable(decoded),
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
        totalCount: page.totalCount,
      );
    });
  }

  /// Counts the records matching [request]'s filters and search.
  ///
  /// This is a separate, explicit call because an exact count is a full extra
  /// pass over the data; it is never performed implicitly.
  Future<BackendResult<int>> count({
    PageRequest request = const PageRequest(page: 1, pageSize: 1),
    CancellationToken? cancellationToken,
  }) async {
    final invalid = _validatePageRequest(request);
    if (invalid != null) {
      return failureOf(invalid);
    }

    final spec = DataQuerySpec(
      from: 0,
      to: 0,
      search: request.search,
      filters: List<FilterCondition>.unmodifiable(request.filters),
      sorting: const [],
    );

    return executor.run<int>(
      operation: '$resourceKey.count',
      fallbackErrorType: BackendErrorType.database,
      cancellationToken: cancellationToken,
      action: () async =>
          unwrap(await backend.count(resource: descriptor, spec: spec)),
    );
  }

  /// Creates a record from [request].
  ///
  /// The codec validates and encodes the request, so no raw column map crosses
  /// the public API.
  Future<BackendResult<TModel>> create(
    TCreate request, {
    CancellationToken? cancellationToken,
  }) async {
    final invalid = codec.validateCreate(request);
    if (invalid != null) {
      return failureOf(invalid);
    }

    final encoded = codec.encodeCreate(request);
    final values = encoded.data;
    if (values == null) {
      return BackendFailureResult<TModel>(
        error:
            encoded.failure ?? CodecFailures.field('The request is invalid.'),
      );
    }

    final result = await executor.run<BackendRecord>(
      operation: '$resourceKey.create',
      fallbackErrorType: BackendErrorType.database,
      cancellationToken: cancellationToken,
      action: () async => unwrap(
        await backend.create(resource: descriptor, values: values),
      ),
    );

    return _decodeFirst(result);
  }

  /// Updates the record identified by [id] with [request].
  Future<BackendResult<TModel>> update(
    String id,
    TUpdate request, {
    CancellationToken? cancellationToken,
  }) async {
    if (id.trim().isEmpty) {
      return failureOf(_validation('An id is required.'));
    }
    final invalid = codec.validateUpdate(request);
    if (invalid != null) {
      return failureOf(invalid);
    }

    final encoded = codec.encodeUpdate(request);
    final values = encoded.data;
    if (values == null) {
      return BackendFailureResult<TModel>(
        error:
            encoded.failure ?? CodecFailures.field('The request is invalid.'),
      );
    }
    if (values.isEmpty) {
      return failureOf(
        _validation('The update request does not change any field.'),
      );
    }

    final result = await executor.run<BackendRecord>(
      operation: '$resourceKey.update',
      fallbackErrorType: BackendErrorType.database,
      cancellationToken: cancellationToken,
      action: () async => unwrap(
        await backend.update(
          resource: descriptor,
          id: id.trim(),
          values: values,
        ),
      ),
    );

    return _decodeFirst(result);
  }

  /// Permanently removes the record identified by [id].
  ///
  /// For records that support soft deletion prefer [softDelete]: permanent
  /// deletion destroys the audit trail that the shipped RLS policies and any
  /// referential integrity rely on.
  Future<BackendResult<void>> delete(
    String id, {
    CancellationToken? cancellationToken,
  }) async {
    if (id.trim().isEmpty) {
      return failureOf(_validation('An id is required.'));
    }

    return executor.run<void>(
      operation: '$resourceKey.delete',
      fallbackErrorType: BackendErrorType.database,
      cancellationToken: cancellationToken,
      action: () async => unwrap(
        await backend.delete(resource: descriptor, id: id.trim()),
      ),
    );
  }

  /// Permanently removes all records matching non-empty equality filters.
  ///
  /// This is intended for composite/link resources where the descriptor's
  /// primary key identifies one side of a one-to-many relationship. It is
  /// deliberately restricted to exact equality filters so replacing links
  /// cannot accidentally delete an entire resource or a range of records.
  Future<BackendResult<void>> deleteWhere({
    required List<FilterCondition> filters,
    CancellationToken? cancellationToken,
  }) async {
    if (filters.isEmpty) {
      return failureOf(
        _validation('At least one exact filter is required for deleteWhere.'),
      );
    }
    final invalid = _validateFilters(filters);
    if (invalid != null) return failureOf(invalid);
    if (filters.any((filter) => filter.operator != FilterOperator.equals)) {
      return failureOf(
        _validation('deleteWhere only supports equality filters.'),
      );
    }

    final spec = DataQuerySpec(
      from: 0,
      to: 0,
      filters: List<FilterCondition>.unmodifiable(filters),
    );
    return executor.run<void>(
      operation: '$resourceKey.deleteWhere',
      fallbackErrorType: BackendErrorType.database,
      cancellationToken: cancellationToken,
      action: () async => unwrap(
        await backend.deleteWhere(resource: descriptor, spec: spec),
      ),
    );
  }

  /// Marks the record identified by [id] as deleted without removing it.
  ///
  /// Returns a `validation` failure for a module whose descriptor declares no
  /// soft-delete column, so callers get a clear signal instead of a silent
  /// hard delete.
  Future<BackendResult<TModel>> softDelete(
    String id, {
    CancellationToken? cancellationToken,
  }) async {
    final softDeleteField = codec.descriptor.softDeleteField;
    if (softDeleteField == null) {
      return failureOf(
        _validation(
          '$resourceKey does not support soft deletion. Call delete() if '
          'you intend to remove the record permanently.',
        ),
      );
    }
    if (id.trim().isEmpty) {
      return failureOf(_validation('An id is required.'));
    }

    final result = await executor.run<BackendRecord>(
      operation: '$resourceKey.softDelete',
      fallbackErrorType: BackendErrorType.database,
      cancellationToken: cancellationToken,
      action: () async => unwrap(
        await backend.update(
          resource: descriptor,
          id: id.trim(),
          values: <String, Object?>{softDeleteField: now()},
        ),
      ),
    );

    return _decodeFirst(result);
  }

  /// Whether a page identified by [request] is currently being loaded.
  bool isPageInFlight(PageRequest request) =>
      _inFlightPages.contains('$resourceKey#${request.cacheKey}');

  DataQuerySpec _buildSpec(PageRequest request) {
    // A soft-delete column, when present, is always hidden from reads so a
    // "deleted" row never reappears in a list. This mirrors the `deleted_at is
    // null` predicate in the shipped RLS policies, so client-side filtering and
    // database-side authorization agree.
    final filters = <FilterCondition>[...request.filters];
    final softDeleteField = codec.descriptor.softDeleteField;
    if (softDeleteField != null) {
      filters.add(FilterCondition.isNull(softDeleteField));
    }
    return DataQuerySpec(
      from: request.inclusiveStart,
      to: request.inclusiveEnd,
      search: request.search,
      filters: List<FilterCondition>.unmodifiable(filters),
      sorting: codec.descriptor.stableSorting(request.sorting),
      includeTotalCount: request.includeTotalCount,
    );
  }

  BackendFailure? _validatePageRequest(PageRequest request) {
    final error = request.validate();
    if (error != null) return _validation(error);
    if (request.page > PaginationLimits.maxPage) {
      return _validation(
        'page must not exceed ${PaginationLimits.maxPage}. Use cursor '
        'pagination (getCursorPage) for deep result sets.',
      );
    }
    final filterError = _validateFilters(request.filters);
    if (filterError != null) return filterError;
    return _validateSorting(request.sorting);
  }

  BackendFailure? _validateCursorRequest(CursorRequest request) {
    final error = request.validate();
    if (error != null) return _validation(error);
    final filterError = _validateFilters(request.filters);
    if (filterError != null) return filterError;
    return _validateSorting(request.sorting);
  }

  BackendFailure? _validateFilters(List<FilterCondition> filters) {
    for (final filter in filters) {
      final error = filter.validate();
      if (error != null) return _validation(error);
    }
    return null;
  }

  BackendFailure? _validateSorting(List<SortCondition> sorting) {
    for (final sort in sorting) {
      final error = sort.validate();
      if (error != null) return _validation(error);
    }
    return null;
  }

  BackendResult<TModel> _decodeFirst(BackendResult<BackendRecord> result) {
    if (result is BackendFailureResult<BackendRecord>) {
      return BackendFailureResult<TModel>(error: result.error);
    }
    final record = (result as BackendSuccess<BackendRecord>).value;
    if (record.isEmpty) {
      return failureOf(
        BackendErrorClassifier.build(
          type: BackendErrorType.notFound,
          message: 'No $resourceKey record was found for the requested id.',
        ),
      );
    }
    return codec.decode(record);
  }

  BackendFailure _validation(String message) {
    return BackendErrorClassifier.build(
      type: BackendErrorType.validation,
      message: message,
    );
  }

  /// The inclusive range a [PageRequest] maps to, exposed for tests and
  /// documentation.
  static ({int from, int to}) rangeFor(PageRequest request) {
    return PaginationBackend.pageRange(
      page: request.page,
      pageSize: request.pageSize,
    );
  }
}
