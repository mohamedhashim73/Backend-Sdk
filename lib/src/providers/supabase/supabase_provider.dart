import 'package:supabase/supabase.dart' show SupabaseClient;

import '../../auth/auth_repository.dart';
import '../../contracts/auth_backend.dart';
import '../../contracts/data_backend.dart';
import '../../contracts/realtime_backend.dart';
import '../../contracts/storage_backend.dart';
import '../../core/backend_configuration.dart';
import '../../core/backend_logger.dart';
import '../../core/backend_resource.dart';
import '../../core/dependency_container.dart';
import '../../modules/products/product_mapper.dart';
import '../../modules/products/products_repository.dart';
import '../../modules/users/users_repository.dart';
import '../../realtime/realtime_repository.dart';
import '../../retry/request_executor.dart';
import '../../retry/retry_policy.dart';
import '../../storage/storage_repository.dart';
import 'supabase_auth_backend.dart';
import 'supabase_client_factory.dart';
import 'supabase_data_backend.dart';
import 'supabase_error_mapper.dart';
import 'supabase_realtime_backend.dart';
import 'supabase_storage_backend.dart';

/// Assembles the concrete Supabase implementation of every backend contract.
///
/// This class is the only object in the package that knows both the provider
/// contracts and the Supabase adapters. Everything above it - the SDK facade,
/// the repositories, the application - depends on the contracts only.
///
/// All vendor state (`SupabaseClient`, `RealtimeChannel`, `StorageFileApi`)
/// is created here and disposed here.
class SupabaseProvider implements BackendServices {
  final SupabaseClient _client;
  final BackendConfiguration _configuration;
  final BackendLogger _logger;

  late final SupabaseErrorMapper _errorMapper = const SupabaseErrorMapper();

  late final RequestExecutor executor = RequestExecutor(
    retryPolicy: RetryPolicy(
      maxRetries: _configuration.maxRetries,
      baseDelay: _configuration.retryDelay,
      backoffMultiplier: _configuration.retryBackoffMultiplier,
      maxDelay: _configuration.maxRetryDelay,
    ),
    requestTimeout: _configuration.requestTimeout,
    logger: _logger,
  );

  late final DataBackend dataBackend = SupabaseDataBackend(
    client: _client,
    errorMapper: _errorMapper,
    searchableColumns: _searchableColumns,
  );

  late final AuthBackend authBackend = SupabaseAuthBackend(
    client: _client,
    errorMapper: _errorMapper,
  );

  late final StorageBackend storageBackend = SupabaseStorageBackend(
    client: _client,
    errorMapper: _errorMapper,
  );

  late final RealtimeBackend realtimeBackend = SupabaseRealtimeBackend(
    client: _client,
    errorMapper: _errorMapper,
  );

  @override
  DataBackend get data => dataBackend;

  @override
  late final AuthRepository auth = AuthRepository(
    backend: authBackend,
    executor: executor,
    logger: _logger,
  );

  @override
  late final StorageRepository storage = StorageRepository(
    backend: storageBackend,
    executor: executor,
    logger: _logger,
  );

  @override
  late final RealtimeRepository realtime = RealtimeRepository(
    backend: realtimeBackend,
    logger: _logger,
  );

  @override
  late final ProductsRepository products = ProductsRepository(
    backend: dataBackend,
    executor: executor,
    logger: _logger,
    realtime: realtime,
  );

  @override
  late final UsersRepository users = UsersRepository(
    backend: dataBackend,
    executor: executor,
    logger: _logger,
    realtime: realtime,
  );

  bool _disposed = false;

  /// Creates a provider over an already-built [client].
  ///
  /// [client] is injected rather than created here so tests can drive the whole
  /// provider without a network or a Flutter binding.
  SupabaseProvider({
    required SupabaseClient client,
    required BackendConfiguration configuration,
    BackendLogger logger = const NoopBackendLogger(),
  })  : _client = client,
        _configuration = configuration,
        _logger = logger;

  /// A process-wide override for the Supabase client factory.
  ///
  /// Set by tests so the **real** built-in provider can be initialized without
  /// Flutter platform channels or a network. `null`, the default, means the
  /// `supabase_flutter`-backed client is used, which is what an application
  /// wants.
  ///
  /// This exists because the registration lifecycle has to be verifiable
  /// end-to-end: a test must be able to call
  /// `BackendSdk.initialize(provider: BackendProvider.supabase, ...)` and have it
  /// succeed, rather than merely assert that a factory object exists in a map.
  static SupabaseClientFactory? clientFactoryOverride;

  /// Creates a provider, building the Supabase client with [factory].
  ///
  /// Precedence: the [factory] argument, then [clientFactoryOverride], then the
  /// `supabase_flutter`-backed client.
  static Future<SupabaseProvider> create({
    required BackendConfiguration configuration,
    SupabaseClientFactory? factory,
    BackendLogger logger = const NoopBackendLogger(),
  }) async {
    final clientFactory =
        factory ?? clientFactoryOverride ?? createSupabaseClientWithFlutter;
    final client = await clientFactory(
      SupabaseClientOptions(
        url: configuration.url ?? '',
        apiKey: configuration.apiKey ?? '',
        debug: configuration.enableLogging,
      ),
    );
    return SupabaseProvider(
      client: client,
      configuration: configuration,
      logger: logger,
    );
  }

  /// The searchable columns per resource, taken from the module descriptors so
  /// the schema is declared once.
  static Map<BackendResource, List<String>> get _searchableColumns {
    return <BackendResource, List<String>>{
      BackendResource.products:
          ProductColumnsDefinition.descriptor.searchableFields.toList(),
      BackendResource.users:
          UserColumnsDefinition.descriptor.searchableFields.toList(),
    };
  }

  @override

  /// Releases every provider resource, including the Supabase client.
  ///
  /// Idempotent, so it is safe to call from both `BackendSdk.dispose()` and a
  /// test's teardown.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await realtime.dispose();
    await auth.dispose();
    await storage.dispose();
    try {
      await _client.dispose();
    } on Object catch (error, stackTrace) {
      _logger.error(
        'Disposing the Supabase client failed.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Whether [dispose] has run.
  bool get isDisposed => _disposed;
}
