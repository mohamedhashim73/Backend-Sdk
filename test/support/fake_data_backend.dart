import 'package:backend_sdk/src/contracts/data_backend.dart';
import 'package:backend_sdk/src/contracts/data_query_spec.dart';
import 'package:backend_sdk/src/core/backend_resource.dart';
import 'package:backend_sdk/src/errors/backend_error_mapper.dart';
import 'package:backend_sdk/src/errors/backend_error_type.dart';
import 'package:backend_sdk/src/filters/filter_condition.dart';
import 'package:backend_sdk/src/filters/filter_operator.dart';
import 'package:backend_sdk/src/filters/sort_condition.dart';
import 'package:backend_sdk/src/pagination/cursor_page_result.dart';
import 'package:backend_sdk/src/pagination/page_result.dart';
import 'package:backend_sdk/src/result/backend_result.dart';
import 'fakes.dart' show ArmedFailure, fail, success;

/// An in-memory [DataBackend] used by the unit tests.
///
/// It applies the same inclusive range arithmetic, soft-delete hiding, filter and
/// ordering rules the real provider applies, but performs no I/O. That lets the
/// repository and pagination logic be tested exhaustively without a network, a
/// Flutter binding, or a running Supabase project.
///
/// Every spec it receives is recorded, so a test can assert the exact range,
/// filters and ordering the repository produced.
class FakeDataBackend implements DataBackend {
  /// Rows keyed by resource, in insertion order.
  final Map<BackendResource, List<BackendRecord>> store =
      <BackendResource, List<BackendRecord>>{};

  /// Every spec passed to [readPage], in call order.
  final List<DataQuerySpec> pageSpecs = <DataQuerySpec>[];

  /// Every spec passed to [readCursorPage], in call order.
  final List<DataQuerySpec> cursorSpecs = <DataQuerySpec>[];

  /// Every spec passed to [countRecords], in call order.
  final List<DataQuerySpec> countSpecs = <DataQuerySpec>[];

  /// How many times [readPage] was invoked.
  int readPageCalls = 0;

  /// How many times [insertRecord] was invoked.
  int insertCalls = 0;

  /// The soft-delete column this fake honours, when set.
  String? softDeleteColumn;

  /// A failure to throw instead of servicing the next call.
  Object? nextFailure;

  /// Artificial latency applied to every call, used to exercise timeouts.
  Duration latency = Duration.zero;

  /// Seeds a row for [resource].
  void seed(BackendResource resource, BackendRecord record) {
    store.putIfAbsent(resource, () => <BackendRecord>[]).add(record);
  }

  /// Seeds several rows for [resource].
  void seedAll(BackendResource resource, Iterable<BackendRecord> records) {
    store.putIfAbsent(resource, () => <BackendRecord>[]).addAll(records);
  }

  /// Removes every row for [resource].
  void clear(BackendResource resource) {
    store[resource] = <BackendRecord>[];
  }

  @override
  Future<BackendResult<PageResult<BackendRecord>>> readPage({
    required BackendResource resource,
    required DataQuerySpec spec,
  }) async {
    readPageCalls++;
    pageSpecs.add(spec);
    await _delay();
    _throwIfArmed();

    final rows = _apply(resource, spec);
    final total = spec.includeTotalCount ? rows.length : null;
    final start = spec.from;
    final end = spec.to + 1;
    final window = start >= rows.length
        ? const <BackendRecord>[]
        : rows.sublist(start, end > rows.length ? rows.length : end);

    return success(
      PageResult<BackendRecord>.fromItems(
        items: window,
        page: (spec.from ~/ spec.limit) + 1,
        pageSize: spec.limit,
        totalCount: total,
      ),
    );
  }

  @override
  Future<BackendResult<CursorPageResult<BackendRecord>>> readCursorPage({
    required BackendResource resource,
    required String? cursor,
    required DataQuerySpec spec,
  }) async {
    cursorSpecs.add(spec);
    await _delay();
    _throwIfArmed();

    final rows = _apply(resource, spec);
    // The cursor is the numeric offset encoded as a string, which keeps the
    // fake honest about the "fetch one extra row" contract.
    final start = int.tryParse(cursor ?? '') ?? 0;
    final limit = spec.limit;
    final stop = start + limit + 1;
    final window = start >= rows.length
        ? const <BackendRecord>[]
        : rows.sublist(start, stop > rows.length ? rows.length : stop);
    final hasMore = window.length > limit;
    final items = hasMore ? window.sublist(0, limit) : window;

    return success(
      CursorPageResult<BackendRecord>(
        items: items,
        nextCursor: hasMore ? '${start + limit}' : null,
        hasMore: hasMore,
      ),
    );
  }

  @override
  Future<BackendResult<BackendRecord>> readById({
    required BackendResource resource,
    required String id,
  }) async {
    await _delay();
    _throwIfArmed();
    for (final row in store[resource] ?? const <BackendRecord>[]) {
      if (row['id'] == id) {
        if (_isSoftDeleted(row)) break;
        return success(row);
      }
    }
    return fail(
      BackendErrorClassifier.build(
        type: BackendErrorType.notFound,
        message: 'No $resource record with id "$id".',
      ),
    );
  }

  @override
  Future<BackendResult<BackendRecord>> insertRecord({
    required BackendResource resource,
    required Map<String, Object?> values,
  }) async {
    insertCalls++;
    await _delay();
    _throwIfArmed();
    final record = <String, Object?>{'id': 'generated-$insertCalls', ...values};
    store.putIfAbsent(resource, () => <BackendRecord>[]).add(record);
    return success(record);
  }

  @override
  Future<BackendResult<BackendRecord>> updateRecord({
    required BackendResource resource,
    required String id,
    required Map<String, Object?> values,
  }) async {
    await _delay();
    _throwIfArmed();
    final rows = store[resource] ?? <BackendRecord>[];
    for (var i = 0; i < rows.length; i++) {
      if (rows[i]['id'] == id) {
        final updated = <String, Object?>{...rows[i], ...values};
        rows[i] = updated;
        return success(updated);
      }
    }
    return fail(
      BackendErrorClassifier.build(
        type: BackendErrorType.notFound,
        message: 'No $resource record with id "$id".',
      ),
    );
  }

  @override
  Future<BackendResult<void>> deleteRecord({
    required BackendResource resource,
    required String id,
    String? softDeleteColumn,
    Object? softDeleteValue,
  }) async {
    await _delay();
    _throwIfArmed();
    final rows = store[resource] ?? <BackendRecord>[];
    final index = rows.indexWhere((row) => row['id'] == id);
    if (index < 0) {
      return fail(
        BackendErrorClassifier.build(
          type: BackendErrorType.notFound,
          message: 'No $resource record with id "$id".',
        ),
      );
    }
    if (softDeleteColumn != null) {
      rows[index] = <String, Object?>{
        ...rows[index],
        softDeleteColumn: softDeleteValue,
      };
    } else {
      rows.removeAt(index);
    }
    return success(null);
  }

  @override
  Future<BackendResult<int>> countRecords({
    required BackendResource resource,
    required DataQuerySpec spec,
  }) async {
    countSpecs.add(spec);
    await _delay();
    _throwIfArmed();
    return success(_apply(resource, spec).length);
  }

  /// Applies the filters, search and ordering of [spec] to the stored rows.
  List<BackendRecord> _apply(BackendResource resource, DataQuerySpec spec) {
    final rows = (store[resource] ?? const <BackendRecord>[])
        .where((row) => !_isSoftDeleted(row))
        .where(_matches(spec.filters))
        .toList();

    final needle = spec.search?.trim().toLowerCase() ?? '';
    if (needle.isNotEmpty) {
      rows.removeWhere(
        (row) =>
            !row.values.any((value) => '$value'.toLowerCase().contains(needle)),
      );
    }

    rows.sort(_comparatorFor(spec.sorting));
    return rows;
  }

  bool _isSoftDeleted(BackendRecord row) {
    final column = softDeleteColumn;
    return column != null && row[column] != null;
  }

  bool Function(BackendRecord) _matches(List<FilterCondition> filters) {
    return (row) {
      for (final filter in filters) {
        final actual = row[filter.field];
        final expected = filter.value;
        if (!_matchesOne(actual, expected, filter.operator)) return false;
      }
      return true;
    };
  }

  static bool _matchesOne(Object? actual, Object? expected, FilterOperator op) {
    switch (op) {
      case FilterOperator.equals:
        return actual == null ? expected == null : '$actual' == '$expected';
      case FilterOperator.notEquals:
        return actual == null ? expected != null : '$actual' != '$expected';
      case FilterOperator.contains:
        return '$actual'.toLowerCase().contains('$expected'.toLowerCase());
      case FilterOperator.startsWith:
        return '$actual'.toLowerCase().startsWith('$expected'.toLowerCase());
      case FilterOperator.greaterThan:
        return _num(actual) > _num(expected);
      case FilterOperator.greaterThanOrEqual:
        return _num(actual) >= _num(expected);
      case FilterOperator.lessThan:
        return _num(actual) < _num(expected);
      case FilterOperator.lessThanOrEqual:
        return _num(actual) <= _num(expected);
      case FilterOperator.isNull:
        return actual == null;
      case FilterOperator.isNotNull:
        return actual != null;
      case FilterOperator.inList:
        return expected is List && expected.contains(actual);
      case FilterOperator.textSearch:
        return '$actual'.toLowerCase().contains('$expected'.toLowerCase());
    }
  }

  static double _num(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? double.nan;
  }

  Comparator<BackendRecord> _comparatorFor(List<SortCondition> sorting) {
    return (a, b) {
      for (final sort in sorting) {
        final comparison = _compareValues(a[sort.field], b[sort.field]);
        if (comparison != 0) {
          return sort.ascending ? comparison : -comparison;
        }
      }
      return 0;
    };
  }

  static int _compareValues(Object? a, Object? b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    if (a is num && b is num) return a.compareTo(b);
    return '$a'.compareTo('$b');
  }

  Future<void> _delay() => latency == Duration.zero
      ? Future<void>.value()
      : Future<void>.delayed(latency);

  /// Raises the armed failure verbatim so the SDK's real transport classifier
  /// sees the original type, exactly as it would in production.
  ///
  /// A value that is not throwable is wrapped, so a test can arm an arbitrary
  /// object without tripping the `only_throw_errors` lint.
  void _throwIfArmed() {
    final failure = nextFailure;
    if (failure == null) return;
    nextFailure = null;
    if (failure is Exception) {
      throw failure;
    }
    if (failure is Error) {
      throw failure;
    }
    throw ArmedFailure(failure);
  }
}
