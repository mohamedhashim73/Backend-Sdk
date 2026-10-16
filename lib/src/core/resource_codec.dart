import '../contracts/data_backend.dart';
import '../core/backend_resource.dart';
import '../errors/backend_error_mapper.dart';
import '../errors/backend_error_type.dart';
import '../errors/backend_failure.dart';
import '../filters/sort_condition.dart';
import '../result/backend_result.dart';

/// How a module repository translates between its models and backend records.
///
/// A codec is the *only* place in a module that knows the shape of a backend
/// row. Repositories, the SDK facade and the application never see a
/// [BackendRecord].
///
/// Implementations are supplied by each module (`ProductCodec`,
/// `UserCodec`, ...) and are pure functions with no I/O, which is what makes
/// them trivially testable.
abstract interface class ResourceCodec<TModel extends Object,
    TCreate extends Object, TUpdate extends Object> {
  /// The resource this codec describes.
  BackendResourceDescriptor get descriptor;

  /// Converts a backend record into the module's model.
  ///
  /// Returns a validation failure instead of throwing when the record cannot be
  /// mapped, so one malformed row never crashes a page load.
  BackendResult<TModel> decode(BackendRecord record);

  /// Converts a create request into the column values to insert.
  BackendResult<Map<String, Object?>> encodeCreate(TCreate request);

  /// Converts an update request into the column values to write.
  ///
  /// Returns a failure when the request contains no changes, which avoids a
  /// pointless round trip.
  BackendResult<Map<String, Object?>> encodeUpdate(TUpdate request);

  /// Validates a create request beyond what the request type already enforces.
  BackendFailure? validateCreate(TCreate request);

  /// Validates an update request.
  BackendFailure? validateUpdate(TUpdate request);
}

/// The provider-independent description of a resource a codec handles.
class BackendResourceDescriptor {
  /// The legacy built-in resource, when this descriptor represents Products or
  /// Users. Application-defined descriptors leave this `null`.
  final BackendResource? resource;

  /// A stable application-level key for this resource.
  final String key;

  /// Legacy provider target for this resource.
  ///
  /// New definitions should use SDK routing during SDK
  /// initialization. This remains for migration compatibility only.
  @Deprecated('Configure BackendRouting.resourceTargets instead.')
  final String tableName;

  /// The primary key column name.
  ///
  /// Used to build deterministic tie-breaker sorting and to build the `id`
  /// equality predicate.
  final String primaryKeyField;

  /// The columns a free-text search term is matched against.
  final Iterable<String> searchableFields;

  /// The columns the resource is ordered by when a request supplies no sorting.
  final List<SortCondition> defaultSorting;

  /// The column used for soft deletion, or `null` when the resource has no
  /// soft-delete support.
  final String? softDeleteField;

  /// The created timestamp column, when the module exposes it.
  final String? createdAtField;

  /// The updated timestamp column, when the module exposes it.
  final String? updatedAtField;

  /// Creates a resource descriptor.
  const BackendResourceDescriptor({
    this.resource,
    String? key,
    String? tableName,
    this.primaryKeyField = 'id',
    this.searchableFields = const <String>{},
    this.defaultSorting = const [],
    this.softDeleteField,
    this.createdAtField,
    this.updatedAtField,
  })  : key = key ??
            (resource == BackendResource.products
                ? 'products'
                : resource == BackendResource.users
                    ? 'users'
                    : ''),
        tableName = tableName ??
            key ??
            (resource == BackendResource.products
                ? 'products'
                : resource == BackendResource.users
                    ? 'users'
                    : '');

  /// Whether this descriptor contains only safe identifier names.
  bool get isValid {
    return _isIdentifier(key) &&
        _isIdentifier(tableName) &&
        _isIdentifier(primaryKeyField) &&
        searchableFields.every(_isIdentifier) &&
        defaultSorting.every((sort) => _isIdentifier(sort.field)) &&
        (softDeleteField == null || _isIdentifier(softDeleteField!)) &&
        (createdAtField == null || _isIdentifier(createdAtField!)) &&
        (updatedAtField == null || _isIdentifier(updatedAtField!));
  }

  /// Throws an [ArgumentError] when the descriptor is unsafe or incomplete.
  void validate() {
    if (!isValid) {
      throw ArgumentError.value(
        this,
        'descriptor',
        'Resource keys, table names and field names must be non-empty safe '
            'identifiers containing only letters, digits and underscores.',
      );
    }
  }

  static bool _isIdentifier(String value) =>
      RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value);

  /// Whether this resource supports soft deletion.
  bool get supportsSoftDelete => softDeleteField != null;

  /// The ordering to apply for a request, made deterministic.
  ///
  /// When the caller's sorts do not already end with the primary key, an
  /// ascending primary-key sort is appended. Without it, two rows with equal
  /// sort values can swap between pages and be returned twice.
  List<SortCondition> stableSorting(List<SortCondition> requested) {
    // An empty request means "use the module's default order"; it never means
    // "no ordering at all", because an unordered query is not pageable.
    final base = requested.isEmpty ? defaultSorting : requested;
    if (base.isEmpty) {
      return List<SortCondition>.unmodifiable(
        <SortCondition>[SortCondition.ascending(primaryKeyField)],
      );
    }
    final result = <SortCondition>[...base];
    final hasPrimaryKey = result.any((sort) => sort.field == primaryKeyField);
    if (!hasPrimaryKey) {
      result.add(SortCondition.ascending(primaryKeyField));
    }
    return List<SortCondition>.unmodifiable(result);
  }
}

/// A validation failure factory shared by codecs.
abstract final class CodecFailures {
  const CodecFailures._();

  /// Returns a `notFound` failure for a missing record of [resource].
  static BackendFailure notFound(String resource) {
    return BackendErrorClassifier.build(
      type: BackendErrorType.notFound,
      message: 'No $resource record was returned by the backend.',
    );
  }

  /// Returns a validation failure describing an undecodable record.
  static BackendFailure decode(String resource, String reason) {
    return BackendErrorClassifier.build(
      type: BackendErrorType.validation,
      message: 'A $resource record could not be decoded: $reason',
    );
  }

  /// Returns a validation failure for a malformed field value.
  static BackendFailure field(String message) {
    return BackendErrorClassifier.build(
      type: BackendErrorType.validation,
      message: message,
    );
  }
}
