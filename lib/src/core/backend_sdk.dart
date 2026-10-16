import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import '../auth/auth_repository.dart';
import '../auth/backend_token_provider.dart';
import '../contracts/data_backend.dart';
import '../errors/backend_error_mapper.dart';
import '../errors/backend_error_type.dart';
import '../errors/backend_failure.dart';
import '../modules/products/products_repository.dart';
import '../modules/users/users_repository.dart';
import '../operations/backend_operation_client.dart';
import '../providers/supabase/supabase_provider.dart';
import '../realtime/realtime_repository.dart';
import '../retry/request_executor.dart';
import '../retry/retry_policy.dart';
import '../storage/storage_repository.dart';
import 'backend_configuration.dart';
import 'backend_logger.dart';
import 'backend_provider.dart';
import 'backend_resource_definition.dart';
import 'dependency_container.dart';

/// The entry point of the backend SDK.
///
/// `BackendSdk` is a thin, typed facade over whichever provider is configured.
/// It owns the initialization lifecycle and hands out repositories; it contains
/// no data-access logic of its own.
///
/// ## Lifecycle
///
/// Initialization happens **exactly once** per process:
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await BackendSdk.initialize(
///     provider: BackendProvider.supabase,
///     configuration: BackendConfiguration.supabase(
///       url: AppEnvironment.supabaseUrl,
///       apiKey: AppEnvironment.supabaseAnonKey,
///     ),
///   );
///   runApp(const MyApp());
/// }
/// ```
///
/// * [initialize] validates the configuration before touching the network.
/// * Calling [initialize] again while an instance is active is a **no-op that
///   throws**: the active provider is never silently replaced, because two
///   different configurations silently swapping underneath live screens is a
///   class of bug that is very hard to diagnose.
/// * Accessing a repository before initialization throws a
///   `BackendErrorType.configuration` failure rather than a null dereference.
///
/// ## Secrets
///
/// Configuration carries the provider's **public** key. Never put a
/// service-role or secret key in a Flutter application: the binary is readable
/// by its users, and every table must be protected by row level security
/// instead.
class BackendSdk {
  BackendSdk._();

  static final BackendSdk _instance = BackendSdk._();

  /// The process-wide SDK instance.
  ///
  /// Reading this getter also registers the built-in providers, so
  /// `BackendSdk.instance` works whether or not [initialize] was called first.
  /// [initialize] performs the same registration itself, so **an application
  /// never has to touch `instance` before initializing**:
  ///
  /// ```dart
  /// // Correct: no `BackendSdk.instance` read required.
  /// await BackendSdk.initialize(
  ///   provider: BackendProvider.supabase,
  ///   configuration: BackendConfiguration.supabase(url: ..., apiKey: ...),
  /// );
  /// ```
  static BackendSdk get instance {
    registerBuiltInProviders();
    return _instance;
  }

  /// Registers the providers that ship with this package.
  ///
  /// Called automatically by both [initialize] and [instance], so an application
  /// never has to call it. It is public for one reason: a test that needs to
  /// assert the registry contents without performing a full initialization.
  ///
  /// Idempotent, and it never replaces a factory registered through
  /// [BackendServiceFactory.register].
  static void registerBuiltInProviders() => _registerBuiltInProviders();

  static BackendServices? _services;
  static BackendConfiguration? _configuration;
  static BackendLogger? _logger;
  static Future<void>? _initialization;

  /// The configuration the active provider was built with, or `null` before
  /// initialization.
  static BackendConfiguration? get configuration => _configuration;

  /// Whether [initialize] has completed and services are available.
  bool get isInitialized => _services != null;

  /// Whether [initialize] has completed and services are available.
  ///
  /// [initialize] is a `static` method, so its result cannot be read through an
  /// instance. This `static` accessor is the equivalent of [isInitialized] for
  /// code in static context, and it deliberately does **not** read
  /// [instance]: checking the lifecycle must never be a side-effecting act.
  static bool get isInitializedGlobally => _services != null;

  /// Initializes the SDK.
  ///
  /// [provider] selects the backend. Only [BackendProvider.supabase] ships with
  /// this package; the others return a clear
  /// [BackendErrorType.unsupportedProvider] failure unless a factory has been
  /// registered through `BackendServiceFactory.register`.
  ///
  /// [logger] overrides the log sink. Logging is off unless
  /// [BackendConfiguration.enableLogging] is `true`, and even then every value
  /// is redacted before it reaches the sink.
  ///
  /// Throws a [BackendFailure] with type
  /// [BackendErrorType.configuration] when the configuration is invalid, and a
  /// failure of [BackendErrorType.unsupportedProvider] when no factory is
  /// registered for [provider]. It also throws when the SDK is already
  /// initialized.
  static Future<void> initialize({
    required BackendProvider provider,
    required BackendConfiguration configuration,
    BackendLogger? logger,
  }) {
    if (_initialization != null) {
      return Future<void>.error(
        BackendErrorClassifier.build(
          type: BackendErrorType.configuration,
          message: 'BackendSdk.initialize() has already been called. The '
              'active provider is not replaced; dispose the SDK first if you '
              'really need to switch backends.',
        ),
        StackTrace.current,
      );
    }

    // The in-flight future is published *synchronously*, before `_initialize`
    // runs. Otherwise two concurrent calls could both pass the guard above,
    // and a failed attempt would leave a stale future that blocks a legitimate
    // retry.
    final completer = Completer<void>();
    _initialization = completer.future;

    // Built-in providers are registered here, *before* the factory is resolved.
    // Doing this only in the `instance` getter meant that an application which
    // called `initialize()` first - the correct bootstrap order - got
    // `unsupportedProvider` for the Supabase provider shipped in this package.
    registerBuiltInProviders();

    _initialize(
      provider: provider,
      configuration: configuration,
      logger: logger,
    ).then(
      completer.complete,
      onError: (Object error, StackTrace stackTrace) {
        // Clearing the marker is what allows a corrected configuration to be
        // retried after a failed attempt.
        _initialization = null;
        completer.completeError(error, stackTrace);
      },
    );

    return completer.future;
  }

  static Future<void> _initialize({
    required BackendProvider provider,
    required BackendConfiguration configuration,
    BackendLogger? logger,
  }) async {
    final validation = validateConfiguration(provider, configuration);
    if (validation != null) {
      throw validation;
    }

    final effectiveLogger = _resolveLogger(configuration, logger);
    final factory = BackendServiceFactory.of(provider);
    if (factory == null) {
      final failure = UnsupportedProviderFailure(provider).error;
      effectiveLogger.warn(
        'The selected backend provider is not implemented.',
        context: {'provider': provider.name},
      );
      throw failure;
    }

    try {
      final services = await factory(configuration, effectiveLogger);
      _services = services;
      _configuration = configuration;
      _logger = effectiveLogger;
      effectiveLogger.info(
        'Backend SDK initialized.',
        context: {'provider': provider.name},
      );
    } on BackendFailure {
      rethrow;
    } on Object catch (error, stackTrace) {
      final failure = BackendErrorClassifier.fromException(
        error,
        stackTrace,
        fallbackType: BackendErrorType.configuration,
      );
      effectiveLogger.error(
        'Initializing the backend SDK failed.',
        cause: error,
        stackTrace: stackTrace,
        context: {'provider': provider.name},
      );
      throw failure;
    }
  }

  /// Validates [configuration] for [provider].
  ///
  /// Returns `null` when the configuration is usable, otherwise a
  /// [BackendErrorType.configuration] failure describing the first problem
  /// found. Exposed so an application can validate a configuration at start-up
  /// and surface its own diagnostics.
  static BackendFailure? validateConfiguration(
    BackendProvider provider,
    BackendConfiguration configuration,
  ) {
    if (configuration.provider != provider) {
      return _configurationFailure(
        'The provider argument (${provider.name}) does not match the '
        'configuration provider (${configuration.provider.name}).',
      );
    }
    final url = configuration.url;
    if (url == null || url.trim().isEmpty) {
      return _configurationFailure(
        'A backend URL is required. Pass it at build time, for example with '
        'String.fromEnvironment, and never hardcode it.',
      );
    }
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return _configurationFailure(
        'The backend URL must be an absolute http(s) URL.',
      );
    }
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      return _configurationFailure('The backend URL must use http or https.');
    }
    if (uri.hasQuery || uri.hasFragment) {
      return _configurationFailure(
        'The backend URL must not contain a query string or fragment.',
      );
    }

    final apiKey = configuration.apiKey;
    if (apiKey == null || apiKey.trim().isEmpty) {
      return _configurationFailure(
        'A backend API key is required. Use the provider anon/publishable key, '
        'never a service-role or secret key.',
      );
    }
    if (_looksLikeServiceRoleKey(apiKey)) {
      return _configurationFailure(
        'The supplied API key looks like a Supabase service-role (secret) key. '
        'A service-role key must never ship inside a Flutter application; use '
        'the anon/publishable key and enforce access with row level security.',
      );
    }

    if (configuration.requestTimeout <= Duration.zero) {
      return _configurationFailure('The request timeout must be positive.');
    }
    if (configuration.maxRetries < 0) {
      return _configurationFailure('maxRetries must not be negative.');
    }
    if (configuration.maxRetries > 10) {
      return _configurationFailure(
        'maxRetries must not exceed 10; a larger value amplifies load without '
        'improving reliability.',
      );
    }
    if (configuration.retryBackoffMultiplier < 1) {
      return _configurationFailure(
        'The retry backoff multiplier must be at least 1.',
      );
    }
    final routingError = configuration.routing.validate();
    if (routingError != null) return _configurationFailure(routingError);
    return null;
  }

  /// Detects a Supabase service-role key.
  ///
  /// A service-role key is a JWT whose payload is `{"role":"service_role"}`.
  /// This is a defence-in-depth check: it catches the most common mistake
  /// (pasting the wrong key from the dashboard) before it is shipped, while
  /// still allowing a publishable key, which is not a JWT.
  static bool _looksLikeServiceRoleKey(String apiKey) {
    final parts = apiKey.split('.');
    if (parts.length != 3) return false;
    final payload = parts.elementAtOrNull(1);
    if (payload == null || payload.isEmpty) return false;

    // The payload is base64url-encoded JSON, so the role has to be decoded
    // rather than pattern-matched.
    try {
      final normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      return decoded.contains('service_role');
    } on FormatException {
      // Not decodable: fall back to a textual check, which still catches the
      // common case of a truncated or pasted key.
      return payload.contains('service_role');
    }
  }

  /// Releases the active provider and resets the SDK so it can be initialized
  /// again.
  ///
  /// Intended for tests and for a deliberate backend switch. Safe to call when
  /// the SDK was never initialized.
  static Future<void> dispose() async {
    final services = _services;
    _services = null;
    _configuration = null;
    _logger = null;
    _initialization = null;
    await services?.dispose();
  }

  /// Clears the singleton state without disposing the provider.
  ///
  /// Intended for tests only. Prefer [dispose].
  static void resetForTesting() {
    _services = null;
    _configuration = null;
    _logger = null;
    _initialization = null;
  }

  /// Authentication.
  DataBackend get data => _require('data').data;

  /// Authentication.
  AuthRepository get auth => _require('auth').auth;

  /// File storage.
  StorageRepository get storage => _require('storage').storage;

  /// Realtime change subscriptions.
  RealtimeRepository get realtime => _require('realtime').realtime;

  /// The products module.
  ProductsRepository get products => _require('products').products;

  /// The users module.
  UsersRepository get users => _require('users').users;

  /// Creates a typed CRUD client from one app-owned resource definition.
  ///
  /// The client inherits the SDK timeout, retry, session and provider setup;
  /// application data sources do not construct codecs or executors.
  BackendResourceClient<TModel, TCreate, TUpdate> resource<
      TModel extends Object, TCreate extends Object, TUpdate extends Object>(
    BackendResourceDefinition<TModel, TCreate, TUpdate> definition,
  ) {
    final configuration = _configuration;
    _require('resource');
    if (configuration == null) {
      throw _configurationFailure(
          'BackendSdk.resource requires initialization.');
    }
    return BackendResourceClient<TModel, TCreate, TUpdate>(
      backend: data,
      definition: definition,
      executor: _createExecutor(configuration),
      logger: _logger ?? const NoopBackendLogger(),
    );
  }

  /// Creates a typed client for aggregate, RPC or provider-function work.
  BackendOperationClient operations() {
    final configuration = _configuration;
    _require('operations');
    if (configuration == null) {
      throw _configurationFailure(
          'BackendSdk.operations requires initialization.');
    }
    return BackendOperationClient(
      backend: data,
      routing: configuration.routing,
      tokens: AuthRepositoryTokenProvider(auth),
      executor: _createExecutor(configuration),
    );
  }

  BackendServices _require(String member) {
    final services = _services;
    if (services == null) {
      throw _configurationFailure(
        'BackendSdk.$member was accessed before initialization. Await '
        'BackendSdk.initialize() during start-up.',
      );
    }
    return services;
  }

  static BackendFailure _configurationFailure(String message) {
    return BackendErrorClassifier.build(
      type: BackendErrorType.configuration,
      message: message,
    );
  }

  static BackendLogger _resolveLogger(
    BackendConfiguration configuration,
    BackendLogger? logger,
  ) {
    if (logger != null) return logger;
    if (!configuration.enableLogging) return const NoopBackendLogger();
    return const CallbackBackendLogger(
      sink: _writeToDeveloperLog,
      // Debug entries are noisy in production; info, warning and error are not.
      isDebug: false,
    );
  }

  static RequestExecutor _createExecutor(BackendConfiguration configuration) {
    return RequestExecutor(
      retryPolicy: RetryPolicy(
        maxRetries: configuration.maxRetries,
        baseDelay: configuration.retryDelay,
        backoffMultiplier: configuration.retryBackoffMultiplier,
        maxDelay: configuration.maxRetryDelay,
      ),
      requestTimeout: configuration.requestTimeout,
      logger: _logger ?? const NoopBackendLogger(),
    );
  }
}

/// The default log sink, writing through `dart:developer`.
///
/// Entries appear in `flutter logs` and in the DevTools console. Values in the
/// entry have already been redacted by `CallbackBackendLogger`, so no secret
/// can reach this function.
void _writeToDeveloperLog(LogEntry entry) {
  developer.log(
    entry.toString(),
    name: 'backend_sdk',
    level: switch (entry.level) {
      LogLevel.debug => 500,
      LogLevel.info => 800,
      LogLevel.warning => 900,
      LogLevel.error => 1000,
    },
    error: entry.cause,
    stackTrace: entry.stackTrace,
  );
}

/// Registers the providers that ship with this package.
///
/// Idempotent: calling it repeatedly registers nothing new, and it **never
/// replaces** a factory an application registered through
/// [BackendServiceFactory.register]. Only providers that are missing are filled
/// in.
///
/// Both SDK entry points call this - [BackendSdk.initialize] and
/// [BackendSdk.instance] - so the built-in Supabase provider is always available
/// regardless of the order an application uses.
void registerBuiltInProviders() => _registerBuiltInProviders();

/// The single implementation behind every registration entry point.
///
/// Kept private under a distinct name because a static member of `BackendSdk`
/// shadows a same-named top-level function inside the class body, which would
/// otherwise make the delegating static call itself.
void _registerBuiltInProviders() {
  _registerIfAbsent(
    BackendProvider.supabase,
    (configuration, logger) => SupabaseProvider.create(
      configuration: configuration,
      logger: logger,
    ),
  );
}

void _registerIfAbsent(
  BackendProvider provider,
  BackendServiceFactoryEntry entry,
) {
  if (BackendServiceFactory.isRegistered(provider)) return;
  BackendServiceFactory.register(provider, entry);
}

/// Registers the providers that ship with this package.
///
/// Retained under its original name for backward compatibility. It is now
/// idempotent and non-clobbering, where it previously overwrote any existing
/// entry, and it is no longer required before
/// [BackendSdk.initialize].
@Deprecated(
  'Use BackendSdk.registerBuiltInProviders(). Registration is now performed '
  'automatically by BackendSdk.initialize and BackendSdk.instance.',
)
void registerDefaultProviders() => registerBuiltInProviders();
