import '../contracts/data_backend.dart';
import '../errors/backend_failure.dart';
import '../pagination/cursor_page_result.dart';
import '../pagination/cursor_request.dart';
import '../pagination/page_request.dart';
import '../pagination/page_result.dart';
import '../result/backend_result.dart';
import '../retry/cancellation_token.dart';
import '../retry/request_executor.dart';
import 'backend_logger.dart';
import 'backend_repository.dart';
import 'resource_codec.dart';

/// Decodes one JSON record into an application model.
typedef BackendJsonDecoder<T extends Object> = T Function(
  Map<String, dynamic> json,
);

/// Encodes an application request as JSON-compatible values.
typedef BackendPayloadEncoder<T extends Object> = Map<String, Object?> Function(
  T request,
);

/// Defines an application resource once without writing a codec class.
///
/// The descriptor uses a logical resource key. Its provider target belongs in
/// the SDK routing at initialization, not in a data source or model.
class BackendResourceDefinition<TModel extends Object, TCreate extends Object,
    TUpdate extends Object> {
  /// Provider-neutral resource metadata.
  final BackendResourceDescriptor descriptor;

  /// Converts one backend record to a model.
  final BackendJsonDecoder<TModel> fromJson;

  /// Converts a create request to backend values.
  final BackendPayloadEncoder<TCreate> toCreateJson;

  /// Converts an update request to backend values.
  final BackendPayloadEncoder<TUpdate> toUpdateJson;

  /// Optional domain validation for creates.
  final BackendFailure? Function(TCreate request)? validateCreate;

  /// Optional domain validation for updates.
  final BackendFailure? Function(TUpdate request)? validateUpdate;

  /// Creates a typed resource definition.
  const BackendResourceDefinition({
    required this.descriptor,
    required this.fromJson,
    required this.toCreateJson,
    required this.toUpdateJson,
    this.validateCreate,
    this.validateUpdate,
  });

  ResourceCodec<TModel, TCreate, TUpdate> toCodec() =>
      _DefinitionResourceCodec<TModel, TCreate, TUpdate>(this);
}

/// Typed CRUD client created from one [BackendResourceDefinition].
///
/// Application data sources receive this client through DI and call only typed
/// methods. They never need a provider, a table/collection name, raw record,
/// codec class or retry executor.
class BackendResourceClient<TModel extends Object, TCreate extends Object,
    TUpdate extends Object> {
  final BackendRepository<TModel, TCreate, TUpdate> _repository;

  /// Creates a resource client from its definition and SDK infrastructure.
  BackendResourceClient({
    required DataBackend backend,
    required BackendResourceDefinition<TModel, TCreate, TUpdate> definition,
    required RequestExecutor executor,
    BackendLogger logger = const NoopBackendLogger(),
  }) : _repository = BackendRepository<TModel, TCreate, TUpdate>(
          backend: backend,
          codec: definition.toCodec(),
          executor: executor,
          logger: logger,
        );

  /// The typed repository for migration-only advanced access.
  BackendRepository<TModel, TCreate, TUpdate> get repository => _repository;

  /// Reads a record by id.
  Future<BackendResult<TModel>> getById(
    String id, {
    CancellationToken? cancellationToken,
  }) =>
      _repository.getById(id, cancellationToken: cancellationToken);

  /// Reads an offset-paginated page.
  Future<BackendResult<PageResult<TModel>>> getPage({
    required PageRequest request,
    CancellationToken? cancellationToken,
  }) =>
      _repository.getPage(
        request: request,
        cancellationToken: cancellationToken,
      );

  /// Reads a cursor-paginated page.
  Future<BackendResult<CursorPageResult<TModel>>> getCursorPage({
    required CursorRequest request,
    CancellationToken? cancellationToken,
  }) =>
      _repository.getCursorPage(
        request: request,
        cancellationToken: cancellationToken,
      );

  /// Counts records matching a query.
  Future<BackendResult<int>> count({
    PageRequest request = const PageRequest(page: 1, pageSize: 1),
    CancellationToken? cancellationToken,
  }) =>
      _repository.count(
        request: request,
        cancellationToken: cancellationToken,
      );

  /// Creates a record.
  Future<BackendResult<TModel>> create(
    TCreate request, {
    CancellationToken? cancellationToken,
  }) =>
      _repository.create(request, cancellationToken: cancellationToken);

  /// Updates a record.
  Future<BackendResult<TModel>> update(
    String id,
    TUpdate request, {
    CancellationToken? cancellationToken,
  }) =>
      _repository.update(id, request, cancellationToken: cancellationToken);

  /// Deletes a record, or soft-deletes it when the definition supports it.
  Future<BackendResult<void>> delete(
    String id, {
    CancellationToken? cancellationToken,
  }) =>
      _repository.delete(id, cancellationToken: cancellationToken);
}

class _DefinitionResourceCodec<TModel extends Object, TCreate extends Object,
    TUpdate extends Object> implements ResourceCodec<TModel, TCreate, TUpdate> {
  final BackendResourceDefinition<TModel, TCreate, TUpdate> _definition;

  const _DefinitionResourceCodec(this._definition);

  @override
  BackendResourceDescriptor get descriptor => _definition.descriptor;

  @override
  BackendResult<TModel> decode(BackendRecord record) {
    try {
      return BackendSuccess<TModel>(_definition.fromJson(record));
    } on Object catch (error) {
      return failureOf<TModel>(
        CodecFailures.decode(descriptor.key, error.toString()),
      );
    }
  }

  @override
  BackendResult<Map<String, Object?>> encodeCreate(TCreate request) {
    try {
      return BackendSuccess<Map<String, Object?>>(
        _definition.toCreateJson(request),
      );
    } on Object catch (error) {
      return failureOf<Map<String, Object?>>(
        CodecFailures.field(error.toString()),
      );
    }
  }

  @override
  BackendResult<Map<String, Object?>> encodeUpdate(TUpdate request) {
    try {
      return BackendSuccess<Map<String, Object?>>(
        _definition.toUpdateJson(request),
      );
    } on Object catch (error) {
      return failureOf<Map<String, Object?>>(
        CodecFailures.field(error.toString()),
      );
    }
  }

  @override
  BackendFailure? validateCreate(TCreate request) =>
      _definition.validateCreate?.call(request);

  @override
  BackendFailure? validateUpdate(TUpdate request) =>
      _definition.validateUpdate?.call(request);
}
