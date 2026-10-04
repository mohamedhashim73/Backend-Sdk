import '../core/backend_resource.dart';
import '../core/resource_codec.dart';
import '../errors/backend_error_mapper.dart';
import '../errors/backend_error_type.dart';
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

/// Descriptor-based operations available to all data backends.
///
/// Kept as extensions for source compatibility with providers implementing the
/// original enum-based contract. Providers that support application modules may
/// override these members with concrete methods; such methods take precedence
/// over the extensions.
extension DescriptorDataBackendExtension on DataBackend {
  Future<BackendResult<PageResult<BackendRecord>>> getPage({
    required BackendResourceDescriptor resource,
    required DataQuerySpec spec,
  }) {
    if (this is DescriptorDataBackend) {
      return (this as DescriptorDataBackend).getPage(
        resource: resource,
        spec: spec,
      );
    }
    final legacy = resource.resource;
    if (legacy == null) return _unsupported<PageResult<BackendRecord>>(resource);
    return readPage(resource: legacy, spec: spec);
  }

  Future<BackendResult<CursorPageResult<BackendRecord>>> getCursorPage({
    required BackendResourceDescriptor resource,
    required String? cursor,
    required DataQuerySpec spec,
  }) {
    if (this is DescriptorDataBackend) {
      return (this as DescriptorDataBackend).getCursorPage(
        resource: resource,
        cursor: cursor,
        spec: spec,
      );
    }
    final legacy = resource.resource;
    if (legacy == null) {
      return _unsupported<CursorPageResult<BackendRecord>>(resource);
    }
    return readCursorPage(resource: legacy, cursor: cursor, spec: spec);
  }

  Future<BackendResult<BackendRecord>> getById({
    required BackendResourceDescriptor resource,
    required String id,
  }) {
    if (this is DescriptorDataBackend) {
      return (this as DescriptorDataBackend).getById(resource: resource, id: id);
    }
    final legacy = resource.resource;
    if (legacy == null) return _unsupported<BackendRecord>(resource);
    return readById(resource: legacy, id: id);
  }

  Future<BackendResult<BackendRecord>> create({
    required BackendResourceDescriptor resource,
    required Map<String, Object?> values,
  }) {
    if (this is DescriptorDataBackend) {
      return (this as DescriptorDataBackend).create(
        resource: resource,
        values: values,
      );
    }
    final legacy = resource.resource;
    if (legacy == null) return _unsupported<BackendRecord>(resource);
    return insertRecord(resource: legacy, values: values);
  }

  Future<BackendResult<BackendRecord>> update({
    required BackendResourceDescriptor resource,
    required String id,
    required Map<String, Object?> values,
  }) {
    if (this is DescriptorDataBackend) {
      return (this as DescriptorDataBackend).update(
        resource: resource,
        id: id,
        values: values,
      );
    }
    final legacy = resource.resource;
    if (legacy == null) return _unsupported<BackendRecord>(resource);
    return updateRecord(resource: legacy, id: id, values: values);
  }

  Future<BackendResult<void>> delete({
    required BackendResourceDescriptor resource,
    required String id,
    String? softDeleteColumn,
    Object? softDeleteValue,
  }) {
    if (this is DescriptorDataBackend) {
      return (this as DescriptorDataBackend).delete(
        resource: resource,
        id: id,
        softDeleteColumn: softDeleteColumn,
        softDeleteValue: softDeleteValue,
      );
    }
    final legacy = resource.resource;
    if (legacy == null) return _unsupported<void>(resource);
    return deleteRecord(
      resource: legacy,
      id: id,
      softDeleteColumn: softDeleteColumn,
      softDeleteValue: softDeleteValue,
    );
  }

  Future<BackendResult<int>> count({
    required BackendResourceDescriptor resource,
    required DataQuerySpec spec,
  }) {
    if (this is DescriptorCountBackend) {
      return (this as DescriptorCountBackend).count(
        resource: resource,
        spec: spec,
      );
    }
    final legacy = resource.resource;
    if (legacy == null) return _unsupported<int>(resource);
    return countRecords(resource: legacy, spec: spec);
  }

  Future<BackendResult<T>> _unsupported<T>(BackendResourceDescriptor resource) {
    return Future.value(
      failureOf<T>(
        BackendErrorClassifier.build(
          type: BackendErrorType.unsupportedProvider,
          message: 'The configured data backend does not support '
              'application-defined resource "${resource.key}".',
        ),
      ),
    );
  }
}

/// Optional provider extension implemented by providers that support custom
/// application-defined descriptors.
abstract interface class DescriptorDataBackend {
  Future<BackendResult<PageResult<BackendRecord>>> getPage({
    required BackendResourceDescriptor resource,
    required DataQuerySpec spec,
  });

  Future<BackendResult<CursorPageResult<BackendRecord>>> getCursorPage({
    required BackendResourceDescriptor resource,
    required String? cursor,
    required DataQuerySpec spec,
  });

  Future<BackendResult<BackendRecord>> getById({
    required BackendResourceDescriptor resource,
    required String id,
  });

  Future<BackendResult<BackendRecord>> create({
    required BackendResourceDescriptor resource,
    required Map<String, Object?> values,
  });

  Future<BackendResult<BackendRecord>> update({
    required BackendResourceDescriptor resource,
    required String id,
    required Map<String, Object?> values,
  });

  Future<BackendResult<void>> delete({
    required BackendResourceDescriptor resource,
    required String id,
    String? softDeleteColumn,
    Object? softDeleteValue,
  });
}

/// Optional descriptor count operation.
abstract interface class DescriptorCountBackend {
  Future<BackendResult<int>> count({
    required BackendResourceDescriptor resource,
    required DataQuerySpec spec,
  });
}
