import 'dart:convert';

import 'package:supabase/supabase.dart'
    show
        CountOption,
        PostgrestFilterBuilder,
        PostgrestList,
        PostgrestTransformBuilder,
        SupabaseClient,
        TextSearchType;

import '../../contracts/data_backend.dart';
import '../../contracts/data_query_spec.dart';
import '../../core/backend_resource.dart';
import '../../core/backend_routing.dart';
import '../../core/resource_codec.dart';
import '../../errors/backend_error_mapper.dart';
import '../../errors/backend_error_type.dart';
import '../../errors/backend_failure.dart';
import '../../filters/filter_condition.dart';
import '../../filters/filter_operator.dart';
import '../../filters/sort_condition.dart';
import '../../pagination/cursor_page_result.dart';
import '../../pagination/page_result.dart';
import '../../result/backend_result.dart';
import 'supabase_error_mapper.dart';
import 'supabase_mappers.dart';

/// Adapts PostgREST to the `DataBackend` contract.
///
/// This class is the only place where a `BackendResource` becomes a table name
/// and a typed filter becomes PostgREST query syntax. Everything above it -
/// repositories, the SDK facade, the application - works in SDK types.
///
/// Retry is intentionally **not** delegated to the PostgREST client. The
/// `RequestExecutor` above already implements bounded exponential backoff with
/// jitter, and a second retry layer would multiply the attempts and defeat the
/// SDK-wide retry budget.
class SupabaseDataBackend
    implements
        DataBackend,
        BackendFunctionBackend,
        DescriptorDataBackend,
        DescriptorCountBackend {
  final SupabaseClient _client;
  final SupabaseErrorMapper _errorMapper;

  /// Maps a resource to the columns a free-text search term is matched against.
  final Map<BackendResource, List<String>> _searchableColumns;

  /// Central provider-target routing configured by the application.
  final BackendRouting _routing;

  /// Creates the adapter over [client].
  ///
  /// [_searchableColumns] is normally supplied by the dependency container from
  /// the registered module codecs, so a module's searchable columns are
  /// declared once and used by both reads and realtime.
  SupabaseDataBackend({
    required SupabaseClient client,
    SupabaseErrorMapper errorMapper = const SupabaseErrorMapper(),
    Map<BackendResource, List<String>> searchableColumns = const {},
    BackendRouting routing = const BackendRouting(),
  })  : _client = client,
        _errorMapper = errorMapper,
        _routing = routing,
        _searchableColumns = Map<BackendResource, List<String>>.unmodifiable(
          searchableColumns,
        );

  @override
  Future<BackendResult<T>> callRpc<T>({
    required String functionName,
    Map<String, Object?> parameters = const {},
    required T Function(Object? value) decoder,
  }) {
    final validation = validateRpcFunctionName(functionName);
    if (validation != null) return Future.value(failureOf<T>(validation));

    return _guard<T>('callRpc', () async {
      final value =
          await _client.rpc<dynamic>(functionName, params: parameters);
      try {
        return decoder(value);
      } catch (error, stackTrace) {
        throw _errorMapper.map(
          error,
          stackTrace,
          fallbackType: BackendErrorType.validation,
          context: {'operation': 'data.callRpc', 'function': functionName},
        );
      }
    });
  }

  @override
  Future<BackendResult<T>> executeFunction<T>({
    required String target,
    Map<String, Object?> parameters = const {},
    required T Function(Object? value) decoder,
  }) =>
      callRpc(
        functionName: target,
        parameters: parameters,
        decoder: decoder,
      );

  @override
  Future<BackendResult<PageResult<BackendRecord>>> getPage({
    required BackendResourceDescriptor resource,
    required DataQuerySpec spec,
  }) {
    return _guard('getPage', () async {
      resource.validate();
      final filtered = _applySearchDescriptor(
        _applyFilters(_selectDescriptor(resource), spec),
        spec,
        resource,
      );
      final ranged = _applySorting(filtered, spec).range(spec.from, spec.to);
      if (spec.includeTotalCount) {
        final response = await ranged.count(CountOption.exact);
        return PageResult<BackendRecord>.fromItems(
          items: _records(response.data),
          page: (spec.from ~/ (spec.to - spec.from + 1)) + 1,
          pageSize: spec.to - spec.from + 1,
          totalCount: response.count,
        );
      }
      return PageResult<BackendRecord>.fromItems(
        items: _records(await ranged),
        page: (spec.from ~/ (spec.to - spec.from + 1)) + 1,
        pageSize: spec.to - spec.from + 1,
      );
    });
  }

  @override
  Future<BackendResult<CursorPageResult<BackendRecord>>> getCursorPage({
    required BackendResourceDescriptor resource,
    required String? cursor,
    required DataQuerySpec spec,
  }) {
    return _guard('getCursorPage', () async {
      resource.validate();
      final keyset = cursor == null ? null : _decodeCursor(cursor);
      if (cursor != null && keyset == null) {
        throw BackendErrorClassifier.build(
          type: BackendErrorType.validation,
          message: 'The pagination cursor is malformed.',
        );
      }
      final base = _applyFilters(_selectDescriptor(resource), spec);
      final filtered = _applySearchDescriptor(
        keyset == null ? base : _applyKeyset(base, spec, keyset),
        spec,
        resource,
      );
      final records = _records(
        await _applySorting(filtered, spec).range(spec.from, spec.to + 1),
      );
      final hasMore = records.length > spec.limit;
      final items = hasMore ? records.sublist(0, spec.limit) : records;
      return CursorPageResult<BackendRecord>(
        items: List<BackendRecord>.unmodifiable(items),
        nextCursor: hasMore && items.isNotEmpty
            ? _encodeCursor(items.last, spec.sorting)
            : null,
        hasMore: hasMore,
      );
    });
  }

  @override
  Future<BackendResult<BackendRecord>> getById({
    required BackendResourceDescriptor resource,
    required String id,
  }) =>
      _guard(
          'getById',
          () async => _client
              .from(_table(resource))
              .select('*')
              .eq(resource.primaryKeyField, id)
              .limit(1)
              .single());

  @override
  Future<BackendResult<BackendRecord>> create({
    required BackendResourceDescriptor resource,
    required Map<String, Object?> values,
  }) =>
      _guard(
          'create',
          () async => _client
              .from(_table(resource))
              .insert(values)
              .select('*')
              .single());

  @override
  Future<BackendResult<BackendRecord>> update({
    required BackendResourceDescriptor resource,
    required String id,
    required Map<String, Object?> values,
  }) =>
      _guard(
          'update',
          () async => _client
              .from(_table(resource))
              .update(values)
              .eq(resource.primaryKeyField, id)
              .select('*')
              .single());

  @override
  Future<BackendResult<void>> delete({
    required BackendResourceDescriptor resource,
    required String id,
    String? softDeleteColumn,
    Object? softDeleteValue,
  }) =>
      _guard<void>('delete', () async {
        final table = _client.from(_table(resource));
        if (softDeleteColumn != null) {
          final record = await table
              .update(<String, Object?>{
                softDeleteColumn:
                    softDeleteValue ?? DateTime.now().toUtc().toIso8601String(),
              })
              .eq(resource.primaryKeyField, id)
              .select('*')
              .single();
          return _void(record);
        }
        return _void(await table
            .delete()
            .eq(resource.primaryKeyField, id)
            .select(resource.primaryKeyField)
            .single());
      });

  @override
  Future<BackendResult<int>> count({
    required BackendResourceDescriptor resource,
    required DataQuerySpec spec,
  }) =>
      _guard<int>('count', () async {
        resource.validate();
        final filtered = _applySearchDescriptor(
          _applyFilters(_selectDescriptor(resource), spec),
          spec,
          resource,
        );
        final response = await filtered.range(0, 0).count(CountOption.exact);
        return response.count;
      });

  @override
  Future<BackendResult<PageResult<BackendRecord>>> readPage({
    required BackendResource resource,
    required DataQuerySpec spec,
  }) {
    return _guard('readPage', () async {
      final filtered = _applySearch(
        _applyFilters(_select(resource), spec),
        spec,
        resource,
      );
      // `range(from, to)` is inclusive on both ends, which is exactly what
      // PageRequest.inclusiveStart/inclusiveEnd produce.
      final ranged = _applySorting(filtered, spec).range(spec.from, spec.to);

      if (spec.includeTotalCount) {
        final response = await ranged.count(CountOption.exact);
        return PageResult<BackendRecord>.fromItems(
          items: _records(response.data),
          page: (spec.from ~/ (spec.to - spec.from + 1)) + 1,
          pageSize: spec.to - spec.from + 1,
          totalCount: response.count,
        );
      }

      final records = await ranged;
      return PageResult<BackendRecord>.fromItems(
        items: _records(records),
        page: (spec.from ~/ (spec.to - spec.from + 1)) + 1,
        pageSize: spec.to - spec.from + 1,
      );
    });
  }

  @override
  Future<BackendResult<CursorPageResult<BackendRecord>>> readCursorPage({
    required BackendResource resource,
    required String? cursor,
    required DataQuerySpec spec,
  }) {
    return _guard('readCursorPage', () async {
      // PostgREST has no keyset pagination, so the cursor is a base64 encoding
      // of the sort values of the last row of the previous page. The
      // application treats it as opaque; nothing outside this class decodes it.
      final keyset = cursor == null ? null : _decodeCursor(cursor);
      if (cursor != null && keyset == null) {
        throw BackendErrorClassifier.build(
          type: BackendErrorType.validation,
          message: 'The pagination cursor is malformed. Start from the first '
              'page instead.',
        );
      }

      final filtered = _applySearch(
        keyset == null
            ? _applyFilters(_select(resource), spec)
            : _applyKeyset(
                _applyFilters(_select(resource), spec), spec, keyset),
        spec,
        resource,
      );

      // Fetch one extra row to determine whether more records exist without a
      // second count query.
      final ranged =
          _applySorting(filtered, spec).range(spec.from, spec.to + 1);
      final records = _records(await ranged);
      final hasMore = records.length > spec.limit;
      final items = hasMore ? records.sublist(0, spec.limit) : records;

      return CursorPageResult<BackendRecord>(
        items: List<BackendRecord>.unmodifiable(items),
        nextCursor: hasMore && items.isNotEmpty
            ? _encodeCursor(items.last, spec.sorting)
            : null,
        hasMore: hasMore,
      );
    });
  }

  @override
  Future<BackendResult<BackendRecord>> readById({
    required BackendResource resource,
    required String id,
  }) {
    return _guard('readById', () async {
      final record = await _client
          .from(SupabaseResourceRegistry.tableOf(resource))
          .select('*')
          .eq('id', id)
          .limit(1)
          .single();
      return record;
    });
  }

  @override
  Future<BackendResult<BackendRecord>> insertRecord({
    required BackendResource resource,
    required Map<String, Object?> values,
  }) {
    return _guard('insertRecord', () async {
      final record = await _client
          .from(SupabaseResourceRegistry.tableOf(resource))
          .insert(values)
          .select('*')
          .single();
      return record;
    });
  }

  @override
  Future<BackendResult<BackendRecord>> updateRecord({
    required BackendResource resource,
    required String id,
    required Map<String, Object?> values,
  }) {
    return _guard('updateRecord', () async {
      // `single()` makes a zero-row update fail with PGRST116, which the error
      // mapper turns into a typed `notFound` instead of a silent success.
      final record = await _client
          .from(SupabaseResourceRegistry.tableOf(resource))
          .update(values)
          .eq('id', id)
          .select('*')
          .single();
      return record;
    });
  }

  @override
  Future<BackendResult<void>> deleteRecord({
    required BackendResource resource,
    required String id,
    String? softDeleteColumn,
    Object? softDeleteValue,
  }) {
    return _guard<void>('deleteRecord', () async {
      final table = _client.from(SupabaseResourceRegistry.tableOf(resource));

      if (softDeleteColumn != null) {
        final record = await table
            .update(<String, Object?>{
              softDeleteColumn:
                  softDeleteValue ?? DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', id)
            .select('*')
            .single();
        return _void(record);
      }

      final deleted = await table.delete().eq('id', id).select('id').single();
      return _void(deleted);
    });
  }

  @override
  Future<BackendResult<int>> countRecords({
    required BackendResource resource,
    required DataQuerySpec spec,
  }) {
    return _guard<int>('countRecords', () async {
      final filtered =
          _applySearch(_applyFilters(_select(resource), spec), spec, resource);

      // The count honours the filters and search, and `range(0, 0)` keeps the
      // transfer to a single row while PostgREST reports the exact total in the
      // `content-range` header.
      final response = await filtered.range(0, 0).count(CountOption.exact);
      return response.count;
    });
  }

  PostgrestFilterBuilder<PostgrestList> _applyFilters(
    PostgrestFilterBuilder<PostgrestList> query,
    DataQuerySpec spec,
  ) {
    var result = query;
    for (final filter in spec.filters) {
      final fieldError = FilterFieldValidator.validateFieldName(filter.field);
      if (fieldError != null) {
        throw BackendErrorClassifier.build(
          type: BackendErrorType.validation,
          message: fieldError,
        );
      }
      final value = FilterFieldValidator.normalizeValue(filter.value);
      result = switch (filter.operator) {
        FilterOperator.equals => value == null
            ? result.isFilter(filter.field, null)
            : result.eq(filter.field, value),
        FilterOperator.notEquals => value == null
            ? result.not(filter.field, 'is', 'null')
            : result.neq(filter.field, value),
        FilterOperator.greaterThan =>
          result.gt(filter.field, _requireValue(value)),
        FilterOperator.greaterThanOrEqual =>
          result.gte(filter.field, _requireValue(value)),
        FilterOperator.lessThan =>
          result.lt(filter.field, _requireValue(value)),
        FilterOperator.lessThanOrEqual =>
          result.lte(filter.field, _requireValue(value)),
        FilterOperator.contains => result.ilike(
            filter.field,
            '*${_escapeLike(_requireValue(value) as String)}*',
          ),
        FilterOperator.startsWith => result.ilike(
            filter.field,
            '${_escapeLike(_requireValue(value) as String)}%',
          ),
        FilterOperator.isNull => result.isFilter(filter.field, null),
        FilterOperator.isNotNull => result.not(filter.field, 'is', 'null'),
        FilterOperator.inList => result.inFilter(
            filter.field,
            (_requireValue(value) as List<Object?>).toList(growable: false),
          ),
        FilterOperator.textSearch => result.textSearch(
            filter.field,
            _requireValue(value) as String,
            // `websearch` never throws a syntax error on user input, which is
            // exactly what a free-text term needs.
            type: TextSearchType.websearch,
          ),
      };
    }
    return result;
  }

  PostgrestFilterBuilder<PostgrestList> _applySearch(
    PostgrestFilterBuilder<PostgrestList> query,
    DataQuerySpec spec,
    BackendResource resource,
  ) {
    final term = spec.search?.trim() ?? '';
    if (term.isEmpty) return query;

    final columns = _searchableColumns[resource] ?? const <String>[];
    if (columns.isEmpty) return query;

    // A multi-column search has to be expressed with PostgREST's `or` filter,
    // which takes a raw filter string. The term is therefore sanitized down to
    // an explicitly allow-listed character set before being interpolated, so it
    // cannot introduce filter syntax.
    final needle = _sanitizeSearchTerm(term);
    if (needle.isEmpty) return query;

    final clause = columns.map((column) => '$column.ilike.*$needle*').join(',');
    return query.or(clause);
  }

  PostgrestFilterBuilder<PostgrestList> _select(BackendResource resource) {
    return _client.from(SupabaseResourceRegistry.tableOf(resource)).select('*');
  }

  PostgrestFilterBuilder<PostgrestList> _selectDescriptor(
    BackendResourceDescriptor resource,
  ) {
    return _client.from(_table(resource)).select('*');
  }

  String _table(BackendResourceDescriptor resource) {
    resource.validate();
    final target = _routing.resourceTarget(resource.key) ?? resource.tableName;
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(target)) {
      throw BackendErrorClassifier.build(
        type: BackendErrorType.configuration,
        message: 'The configured resource target for "${resource.key}" is '
            'not a safe Supabase identifier.',
      );
    }
    return target;
  }

  PostgrestFilterBuilder<PostgrestList> _applySearchDescriptor(
    PostgrestFilterBuilder<PostgrestList> query,
    DataQuerySpec spec,
    BackendResourceDescriptor resource,
  ) {
    final term = spec.search?.trim() ?? '';
    if (term.isEmpty || resource.searchableFields.isEmpty) return query;
    final needle = _sanitizeSearchTerm(term);
    if (needle.isEmpty) return query;
    final clause = resource.searchableFields
        .map((column) => '$column.ilike.*$needle*')
        .join(',');
    return query.or(clause);
  }

  PostgrestTransformBuilder<PostgrestList> _applySorting(
    PostgrestFilterBuilder<PostgrestList> query,
    DataQuerySpec spec,
  ) {
    PostgrestTransformBuilder<PostgrestList> result = query;
    for (final sort in spec.sorting) {
      final error = FilterFieldValidator.validateFieldName(sort.field);
      if (error != null) {
        throw BackendErrorClassifier.build(
          type: BackendErrorType.validation,
          message: error,
        );
      }
      result = result.order(sort.field, ascending: sort.ascending);
    }
    return result;
  }

  PostgrestFilterBuilder<PostgrestList> _applyKeyset(
    PostgrestFilterBuilder<PostgrestList> query,
    DataQuerySpec spec,
    Map<String, Object?> keyset,
  ) {
    if (keyset.isEmpty) return query;

    // The keyset predicate is a lexicographic "strictly after the last row of
    // the previous page" comparison over the sort columns. Building it from
    // validated field names and typed values keeps it free of interpolation
    // risk.
    final sorts = spec.sorting;
    if (sorts.isEmpty) return query;

    final columns = sorts.map((sort) => sort.field).toList(growable: false);
    final values = <Object?>[
      for (final column in columns) keyset[column],
    ];

    final orParts = <String>[];
    for (var i = 0; i < columns.length; i++) {
      final prefix = <String>[
        for (var j = 0; j < i; j++)
          '${columns[j]}.${sorts[j].ascending ? 'eq' : 'eq'}.${_literal(values[j])}',
      ];
      final operator = sorts[i].ascending ? 'gt' : 'lt';
      orParts.add(
        'and(${prefix.join(',')},${columns[i]}.$operator.${_literal(values[i])})',
      );
    }

    return query.or(orParts.join(','));
  }

  String _encodeCursor(BackendRecord last, List<SortCondition> sorting) {
    final payload = <String, Object?>{
      for (final sort in sorting) sort.field: last[sort.field],
    };
    return _base64UrlEncodeUtf8(jsonEncode(payload));
  }

  Map<String, Object?>? _decodeCursor(String cursor) {
    try {
      final decoded = _base64UrlDecodeUtf8(cursor);
      final map = jsonDecode(decoded);
      if (map is! Map) return null;
      return map.map((key, value) => MapEntry('$key', value));
    } on Object {
      return null;
    }
  }

  /// Returns [value], or throws a validation failure when it is null.
  ///
  /// Ordering comparisons and pattern matches are undefined for `null`, so a
  /// null value for those operators is a client bug that is reported rather
  /// than silently turned into a filter that matches nothing.
  static Object _requireValue(Object? value) {
    if (value == null) {
      throw BackendErrorClassifier.build(
        type: BackendErrorType.validation,
        message: 'This filter operator requires a non-null value.',
      );
    }
    return value;
  }

  /// Escapes the LIKE/ILIKE wildcards so a user's `%` is matched literally.
  static String _escapeLike(String value) {
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
  }

  /// Reduces a free-text term to a character set that cannot be PostgREST
  /// syntax.
  ///
  /// Allowed: letters, digits, spaces, `-`, `_`, `.`, `@`, `/`, `+`, `#`, `&`.
  /// Everything else - including `,`, `(`, `)`, `*`, `"`, `\`, `:` and `%` -
  /// is dropped, and runs of whitespace are collapsed.
  static String _sanitizeSearchTerm(String term) {
    final allowed = RegExp(r'[^A-Za-z0-9\s\-_.@/+#&]');
    final collapsed =
        term.replaceAll(allowed, ' ').replaceAll(RegExp(r'\s+'), ' ');
    return collapsed.trim();
  }

  /// Renders a value as a PostgREST filter literal.
  static String _literal(Object? value) {
    if (value == null) return 'null';
    if (value is num || value is bool) return '$value';
    if (value is DateTime) return value.toUtc().toIso8601String();
    final text = '$value';
    if (text.contains(',') || text.contains(')') || text.contains('(')) {
      return '"${text.replaceAll('"', r'\"')}"';
    }
    return text;
  }

  static List<BackendRecord> _records(PostgrestList list) {
    return List<BackendRecord>.unmodifiable(list);
  }

  static void _void(BackendRecord record) {
    // The record itself is not needed; referencing it keeps the `single()`
    // round trip honest about whether a row was actually affected.
    if (record.isEmpty) {
      throw BackendErrorClassifier.build(
        type: BackendErrorType.notFound,
        message: 'The backend did not report an affected row.',
      );
    }
  }

  Future<BackendResult<T>> _guard<T>(
    String operation,
    Future<T> Function() action,
  ) async {
    try {
      return BackendSuccess<T>(await action());
    } on BackendFailure catch (failure) {
      return BackendFailureResult<T>(error: failure);
    } catch (error, stackTrace) {
      return BackendFailureResult<T>(
        error: _errorMapper.map(
          error,
          stackTrace,
          fallbackType: BackendErrorType.database,
          context: {'operation': 'data.$operation'},
        ),
      );
    }
  }
}

/// Encodes a keyset position into an opaque, URL-safe cursor string.
///
/// The value is deliberately unreadable to callers: it is a provider-internal
/// encoding and is not part of this package's public contract.
String _base64UrlEncodeUtf8(String value) {
  return base64Url.encode(utf8.encode(value));
}

/// Decodes a cursor produced by [_base64UrlEncodeUtf8].
String _base64UrlDecodeUtf8(String value) {
  return utf8.decode(base64Url.decode(value));
}
