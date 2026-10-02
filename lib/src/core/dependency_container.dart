import 'dart:async';

import '../auth/auth_repository.dart';
import '../errors/backend_error_mapper.dart';
import '../errors/backend_error_type.dart';
import '../errors/backend_failure.dart';
import '../modules/products/products_repository.dart';
import '../modules/users/users_repository.dart';
import '../realtime/realtime_repository.dart';
import '../storage/storage_repository.dart';
import 'backend_configuration.dart';
import 'backend_logger.dart';
import 'backend_provider.dart';

/// The set of repositories a configured provider exposes.
///
/// This is the shape the SDK facade serves. It contains only provider-agnostic
/// types, which is why a REST or Firebase provider can be added later without
/// changing the facade or any application code.
abstract interface class BackendServices {
  /// Authentication.
  AuthRepository get auth;

  /// File storage.
  StorageRepository get storage;

  /// Realtime change subscriptions.
  RealtimeRepository get realtime;

  /// The products module.
  ProductsRepository get products;

  /// The users module.
  UsersRepository get users;

  /// Releases every service and the provider's own resources.
  Future<void> dispose();
}

/// Builds the services for a configured [BackendProvider].
///
/// This is the composition root's only extension point. An application never
/// constructs a provider directly: it calls `BackendSdk.initialize` and the SDK
/// resolves a factory from this registry.
///
/// A factory is registered once per provider, which is what makes
/// "double initialization must not silently replace the active provider"
/// enforceable rather than a convention.
abstract final class BackendServiceFactory {
  static final Map<BackendProvider, BackendServiceFactoryEntry> _factories =
      <BackendProvider, BackendServiceFactoryEntry>{};

  /// Registers the factory for [provider].
  ///
  /// Registering a provider twice replaces the entry, which only affects
  /// subsequent initializations. An already-initialized SDK keeps the provider
  /// it resolved.
  static void register(
    BackendProvider provider,
    BackendServiceFactoryEntry entry,
  ) {
    _factories[provider] = entry;
  }

  /// The factory registered for [provider], or `null`.
  static BackendServiceFactoryEntry? of(BackendProvider provider) =>
      _factories[provider];

  /// Every registered provider.
  static Set<BackendProvider> get registeredProviders =>
      _factories.keys.toSet();

  /// Removes every registration. Intended for tests.
  static void reset() => _factories.clear();
}

/// The factory that builds services for one provider.
typedef BackendServiceFactoryEntry = FutureOr<BackendServices> Function(
  BackendConfiguration configuration,
  BackendLogger logger,
);

/// A [BackendServices] implementation backed by a provider-specific container.
class ProviderBackendServices implements BackendServices {
  final AuthRepository _auth;
  final StorageRepository _storage;
  final RealtimeRepository _realtime;
  final ProductsRepository _products;
  final UsersRepository _users;
  final Future<void> Function() _onDispose;

  bool _disposed = false;

  /// Wires the repositories of one provider instance.
  ProviderBackendServices({
    required AuthRepository auth,
    required StorageRepository storage,
    required RealtimeRepository realtime,
    required ProductsRepository products,
    required UsersRepository users,
    required Future<void> Function() onDispose,
  })  : _auth = auth,
        _storage = storage,
        _realtime = realtime,
        _products = products,
        _users = users,
        _onDispose = onDispose;

  @override
  AuthRepository get auth {
    _ensureUsable();
    return _auth;
  }

  @override
  StorageRepository get storage {
    _ensureUsable();
    return _storage;
  }

  @override
  RealtimeRepository get realtime {
    _ensureUsable();
    return _realtime;
  }

  @override
  ProductsRepository get products {
    _ensureUsable();
    return _products;
  }

  @override
  UsersRepository get users {
    _ensureUsable();
    return _users;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _onDispose();
  }

  /// Whether [dispose] has run.
  bool get isDisposed => _disposed;

  void _ensureUsable() {
    if (_disposed) {
      throw BackendErrorClassifier.build(
        type: BackendErrorType.configuration,
        message: 'This BackendSdk instance has been disposed. Call '
            'BackendSdk.initialize() again before using it.',
      );
    }
  }
}

/// A failure describing why a provider could not be used.
class UnsupportedProviderFailure {
  /// Creates the failure for [provider].
  factory UnsupportedProviderFailure(BackendProvider provider) {
    return UnsupportedProviderFailure._(
      BackendErrorClassifier.build(
        type: BackendErrorType.unsupportedProvider,
        message: 'The ${provider.name} backend provider is declared but not '
            'implemented in backend_sdk $_sdkVersion. '
            'Register a factory for it with '
            'BackendServiceFactory.register() to enable it.',
      ),
    );
  }

  const UnsupportedProviderFailure._(this.error);

  /// The failure to hand back to callers.
  final BackendFailure error;
}

/// The version string reported in provider failures.
///
/// Kept in sync with `pubspec.yaml` manually; a mismatch here is cosmetic and
/// never affects behaviour.
const String _sdkVersion = '0.1.0';
