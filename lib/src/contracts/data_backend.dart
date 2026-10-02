import '../core/backend_resource.dart';
import '../pagination/cursor_page_result.dart';
import '../pagination/page_result.dart';
import '../result/backend_result.dart';
import 'data_query_spec.dart';

/// A single record as returned by a provider, in the backend's own JSON shape.
///
/// Raw maps are an **internal** representation: they are produced by providers
/// and consumed by module repositories, which immediately convert them into
/// typed models. `BackendRecord` is intentionally not exported from the public
/// barrel, so application code can never handle one.
typedef BackendRecord = Map<String, dynamic>;

/// The provider-facing data contract.
///
/// This interface is the seam that lets a REST, Firebase or GraphQL provider be
/// added later without touching any repository or UI code. A provider only has
/// to translate a [DataQuerySpec] into its own query language and return
/// records in [BackendRecord] form; pagination arithmetic, sorting stability,
/// retry and error mapping are all handled above this line.
abstract interface class DataBackend {
  /// Reads one page of [resource].
  ///
  /// The [DataQuerySpec.from] and [DataQuerySpec.to] bounds are inclusive on
  /// both ends. The returned [PageResult.totalCount] must be `null` unless
  /// [DataQuerySpec.includeTotalCount] is `true`.
  Future<BackendResult<PageResult<BackendRecord>>> readPage({
    required BackendResource resource,
    required DataQuerySpec spec,
  });

  /// Reads the next page of [resource] positioned after [cursor].
  ///
  /// Implementations return `hasMore: false` and a `null` next cursor once the
  /// result set is exhausted.
  Future<BackendResult<CursorPageResult<BackendRecord>>> readCursorPage({
    required BackendResource resource,
    required String? cursor,
    required DataQuerySpec spec,
  });

  /// Reads a single [resource] by primary key.
  ///
  /// Returns a `notFound` failure when no row matches.
  Future<BackendResult<BackendRecord>> readById({
    required BackendResource resource,
    required String id,
  });

  /// Inserts [values] into [resource] and returns the stored record.
  Future<BackendResult<BackendRecord>> insertRecord({
    required BackendResource resource,
    required Map<String, Object?> values,
  });

  /// Updates the record identified by [id] in [resource].
  ///
  /// Returns a `notFound` failure when no row matches.
  Future<BackendResult<BackendRecord>> updateRecord({
    required BackendResource resource,
    required String id,
    required Map<String, Object?> values,
  });

  /// Deletes the record identified by [id] from [resource].
  ///
  /// When [softDeleteColumn] is supplied, the record is retained and the column
  /// is set to [softDeleteValue] (a timestamp by default) instead of being
  /// removed. This is what keeps "deleted" rows consistent with the row level
  /// security policies shipped in `supabase/migrations`.
  Future<BackendResult<void>> deleteRecord({
    required BackendResource resource,
    required String id,
    String? softDeleteColumn,
    Object? softDeleteValue,
  });

  /// Counts the records of [resource] matching [spec]'s filters and search.
  Future<BackendResult<int>> countRecords({
    required BackendResource resource,
    required DataQuerySpec spec,
  });
}
