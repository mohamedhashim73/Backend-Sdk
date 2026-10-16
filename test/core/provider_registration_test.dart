import 'package:backend_sdk/backend_sdk.dart';
import 'package:backend_sdk/src/providers/supabase/supabase_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart' show SupabaseClient;

import '../support/fake_data_backend.dart';
import '../support/fakes.dart';

/// Regression coverage for the provider-registration lifecycle.
///
/// The defect these tests pin down: `registerDefaultProviders()` used to run only
/// from the `BackendSdk.instance` getter, while `initialize()` resolved the
/// factory directly. An application that called `initialize()` first - which is
/// exactly what every correct bootstrap does - therefore received
/// `BackendErrorType.unsupportedProvider` for the Supabase provider that ships
/// with the package.
void main() {
  const validUrl = 'https://project.supabase.co';
  const validKey = 'sb_publishable_abc123';

  BackendConfiguration supabaseConfig() =>
      BackendConfiguration.supabase(url: validUrl, apiKey: validKey);

  tearDown(() async {
    await BackendSdk.dispose();
    BackendServiceFactory.reset();
    SupabaseProvider.clientFactoryOverride = null;
  });

  group('Regression: initialize without touching BackendSdk.instance', () {
    test('the registry starts empty, so nothing can mask the defect', () {
      BackendServiceFactory.reset();

      expect(BackendServiceFactory.registeredProviders, isEmpty);
    });

    test('the built-in Supabase factory is resolvable after registration', () {
      BackendServiceFactory.reset();
      expect(BackendServiceFactory.of(BackendProvider.supabase), isNull);

      BackendSdk.registerBuiltInProviders();

      expect(
        BackendServiceFactory.of(BackendProvider.supabase),
        isNotNull,
        reason: 'the provider shipped with this package must resolve',
      );
    });

    test('initialize registers the built-in provider before resolving',
        () async {
      BackendServiceFactory.reset();
      SupabaseProvider.clientFactoryOverride =
          (options) async => SupabaseClient(options.url, options.apiKey);

      // No `BackendSdk.instance` read anywhere. This is the exact bootstrap an
      // application performs.
      final BackendFailure failure =
          await _initializeAndCaptureFailure(supabaseConfig());

      expect(
        BackendServiceFactory.registeredProviders,
        contains(BackendProvider.supabase),
        reason: 'initialize must register built-ins as a side effect',
      );
      expect(
        failure.type,
        isNot(BackendErrorType.unsupportedProvider),
        reason: 'the built-in Supabase provider must be found, not reported as '
            'unimplemented',
      );
    });

    test('initialize never reports unsupportedProvider for Supabase', () async {
      BackendServiceFactory.reset();

      final failure = await _initializeAndCaptureFailure(
        const BackendConfiguration(provider: BackendProvider.supabase),
      );

      // Before the fix this was unsupportedProvider, because the built-in had
      // never been registered. It is now a configuration failure, reported
      // before any provider is resolved.
      expect(failure.type, BackendErrorType.configuration);
      expect(failure.type, isNot(BackendErrorType.unsupportedProvider));
      expect(failure.message, contains('backend URL is required'));
    });

    test('the built-in Supabase provider initializes end to end', () async {
      BackendServiceFactory.reset();
      // A real SupabaseClient, constructed offline: no plugin, no network.
      SupabaseProvider.clientFactoryOverride =
          (options) async => SupabaseClient(options.url, options.apiKey);

      // Nothing registered manually, no `BackendSdk.instance` read: this is
      // precisely the call that used to throw unsupportedProvider.
      await BackendSdk.initialize(
        provider: BackendProvider.supabase,
        configuration: supabaseConfig(),
      );

      expect(BackendSdk.isInitializedGlobally, isTrue);
      expect(BackendSdk.instance.products, isA<ProductsRepository>());
      expect(BackendSdk.instance.users, isA<UsersRepository>());
      expect(BackendSdk.instance.auth, isA<AuthRepository>());
      expect(BackendSdk.instance.storage, isA<StorageRepository>());
      expect(BackendSdk.instance.realtime, isA<RealtimeRepository>());
    });

    test('a missing URL is reported as configuration, not unsupportedProvider',
        () async {
      BackendServiceFactory.reset();

      final failure = await _initializeAndCaptureFailure(
        const BackendConfiguration(provider: BackendProvider.supabase),
      );

      expect(failure.type, BackendErrorType.configuration);
      expect(failure.message, contains('backend URL is required'));
    });

    test('no instance access is required before initialize', () async {
      BackendServiceFactory.reset();

      // A custom factory keeps this test free of platform channels while still
      // proving the full initialize path works with zero `instance` reads.
      BackendServiceFactory.register(
        BackendProvider.supabase,
        (BackendConfiguration configuration, BackendLogger logger) =>
            FakeServices(configuration),
      );

      await BackendSdk.initialize(
        provider: BackendProvider.supabase,
        configuration: supabaseConfig(),
      );
      expect(BackendSdk.isInitializedGlobally, isTrue);

      await BackendSdk.dispose();

      await BackendSdk.initialize(
        provider: BackendProvider.supabase,
        configuration: supabaseConfig(),
      );
      expect(BackendSdk.isInitializedGlobally, isTrue);
    });

    test('the happy path needs no instance read and no manual registration',
        () async {
      BackendServiceFactory.reset();
      BackendServiceFactory.register(
        BackendProvider.rest,
        (BackendConfiguration configuration, BackendLogger logger) =>
            FakeServices(configuration),
      );

      // `initialize` alone: no `BackendSdk.instance`, no
      // `registerBuiltInProviders`, no `register` for this provider.
      await BackendSdk.initialize(
        provider: BackendProvider.rest,
        configuration: const BackendConfiguration(
          provider: BackendProvider.rest,
          url: validUrl,
          apiKey: validKey,
        ),
      );

      expect(BackendSdk.isInitializedGlobally, isTrue);
      expect(BackendSdk.instance.products, isA<ProductsRepository>());
    });
  });

  group('Regression: unsupported providers are still reported', () {
    for (final provider in <BackendProvider>[
      BackendProvider.rest,
      BackendProvider.firebase,
    ]) {
      test('${provider.name} still fails with unsupportedProvider', () async {
        BackendServiceFactory.reset();

        await expectLater(
          BackendSdk.initialize(
            provider: provider,
            configuration: BackendConfiguration(
              provider: provider,
              url: validUrl,
              apiKey: validKey,
            ),
          ),
          throwsA(
            isA<BackendFailure>().having(
              (BackendFailure f) => f.type,
              'type',
              BackendErrorType.unsupportedProvider,
            ),
          ),
        );

        expect(BackendSdk.instance.isInitialized, isFalse);
      });
    }

    test('registering built-ins does not enable an unimplemented provider', () {
      BackendServiceFactory.reset();
      BackendSdk.registerBuiltInProviders();

      expect(BackendServiceFactory.registeredProviders, [
        BackendProvider.supabase,
      ]);
    });
  });

  group('Regression: custom factories still work', () {
    test('a custom factory for an unimplemented provider is honoured',
        () async {
      BackendServiceFactory.reset();
      var factoryCalls = 0;

      BackendServiceFactory.register(
        BackendProvider.rest,
        (configuration, logger) {
          factoryCalls++;
          return FakeServices(configuration);
        },
      );

      await BackendSdk.initialize(
        provider: BackendProvider.rest,
        configuration: const BackendConfiguration(
          provider: BackendProvider.rest,
          url: validUrl,
          apiKey: validKey,
        ),
      );

      expect(factoryCalls, 1);
      expect(BackendSdk.instance.isInitialized, isTrue);
    });

    test('a custom factory overrides the built-in Supabase provider', () async {
      BackendServiceFactory.reset();
      var factoryCalls = 0;

      BackendServiceFactory.register(
        BackendProvider.supabase,
        (configuration, logger) {
          factoryCalls++;
          return FakeServices(configuration);
        },
      );

      await BackendSdk.initialize(
        provider: BackendProvider.supabase,
        configuration: supabaseConfig(),
      );

      expect(
        factoryCalls,
        1,
        reason: 'initialize must not clobber an explicitly registered factory',
      );
    });

    test('registering built-ins never clobbers a custom factory', () {
      BackendServiceFactory.reset();

      BackendServiceFactory.register(
        BackendProvider.supabase,
        (configuration, logger) => FakeServices(configuration),
      );

      // Simulate every entry point in the package running.
      BackendSdk.registerBuiltInProviders();
      BackendSdk.registerBuiltInProviders();
      BackendSdk.instance;

      expect(
        BackendServiceFactory.registeredProviders,
        contains(BackendProvider.supabase),
      );
    });

    test('explicit re-registration still replaces the entry', () async {
      BackendServiceFactory.reset();
      var firstCalls = 0;
      var secondCalls = 0;

      BackendServiceFactory.register(
        BackendProvider.supabase,
        (configuration, logger) {
          firstCalls++;
          return FakeServices(configuration);
        },
      );
      // `register` keeps its original clobbering semantics.
      BackendServiceFactory.register(
        BackendProvider.supabase,
        (configuration, logger) {
          secondCalls++;
          return FakeServices(configuration);
        },
      );

      await BackendSdk.initialize(
        provider: BackendProvider.supabase,
        configuration: supabaseConfig(),
      );

      expect(firstCalls, 0);
      expect(secondCalls, 1);
    });
  });

  group('Regression: idempotency and retry', () {
    test('double initialization still throws and keeps the provider', () async {
      BackendServiceFactory.reset();
      SupabaseProvider.clientFactoryOverride =
          (options) async => SupabaseClient(options.url, options.apiKey);

      await BackendSdk.initialize(
        provider: BackendProvider.supabase,
        configuration: supabaseConfig(),
      );
      final first = BackendSdk.instance.products;

      await expectLater(
        BackendSdk.initialize(
          provider: BackendProvider.supabase,
          configuration: supabaseConfig().copyWith(apiKey: 'another-key'),
        ),
        throwsA(isA<BackendFailure>()),
      );

      expect(BackendSdk.instance.isInitialized, isTrue);
      expect(identical(BackendSdk.instance.products, first), isTrue);
      expect(BackendSdk.configuration?.apiKey, validKey);
    });

    test('a failed initialization can still be retried', () async {
      BackendServiceFactory.reset();
      SupabaseProvider.clientFactoryOverride =
          (options) async => SupabaseClient(options.url, options.apiKey);

      await expectLater(
        BackendSdk.initialize(
          provider: BackendProvider.supabase,
          configuration: const BackendConfiguration(
            provider: BackendProvider.supabase,
          ),
        ),
        throwsA(isA<BackendFailure>()),
      );
      expect(BackendSdk.isInitializedGlobally, isFalse);

      await BackendSdk.initialize(
        provider: BackendProvider.supabase,
        configuration: supabaseConfig(),
      );

      expect(BackendSdk.isInitializedGlobally, isTrue);
    });

    test('a factory that throws can still be retried', () async {
      BackendServiceFactory.reset();
      BackendServiceFactory.register(
        BackendProvider.supabase,
        (configuration, logger) => throw StateError('transient'),
      );

      await expectLater(
        BackendSdk.initialize(
          provider: BackendProvider.supabase,
          configuration: supabaseConfig(),
        ),
        throwsA(isA<BackendFailure>()),
      );

      BackendServiceFactory.register(
        BackendProvider.supabase,
        (configuration, logger) => FakeServices(configuration),
      );

      await BackendSdk.initialize(
        provider: BackendProvider.supabase,
        configuration: supabaseConfig(),
      );

      expect(BackendSdk.isInitializedGlobally, isTrue);
    });

    test('registering built-ins repeatedly is a no-op', () {
      BackendServiceFactory.reset();

      BackendSdk.registerBuiltInProviders();
      BackendSdk.registerBuiltInProviders();
      BackendSdk.registerBuiltInProviders();

      expect(BackendServiceFactory.registeredProviders, hasLength(1));
      expect(
        BackendServiceFactory.registeredProviders,
        contains(BackendProvider.supabase),
      );
    });

    test('built-in registration survives a registry reset and re-run', () {
      BackendServiceFactory.reset();
      BackendSdk.registerBuiltInProviders();
      expect(
        BackendServiceFactory.registeredProviders,
        contains(BackendProvider.supabase),
      );

      BackendServiceFactory.reset();
      expect(BackendServiceFactory.registeredProviders, isEmpty);

      BackendSdk.registerBuiltInProviders();
      expect(
        BackendServiceFactory.registeredProviders,
        contains(BackendProvider.supabase),
      );
    });
  });
}

/// Runs [BackendSdk.initialize] and returns the failure it produced.
///
/// Returns a synthetic success marker only if initialization unexpectedly
/// succeeded, so a caller asserting on `failure.type` fails loudly rather than
/// silently passing.
Future<BackendFailure> _initializeAndCaptureFailure(
  BackendConfiguration configuration,
) async {
  try {
    await BackendSdk.initialize(
      provider: configuration.provider,
      configuration: configuration,
    );
  } on BackendFailure catch (failure) {
    return failure;
  }
  return BackendErrorClassifier.build(
    type: BackendErrorType.unknown,
    message: 'initialize() unexpectedly succeeded',
  );
}

/// A `BackendServices` built from in-memory fakes.
///
/// Registered as a custom provider factory to prove the extension point works
/// for any provider value, including the unimplemented ones.
class FakeServices implements BackendServices {
  FakeServices(this.configuration) {
    executor = const RequestExecutor(
      retryPolicy: RetryPolicy.noRetries,
      requestTimeout: Duration.zero,
    );
    data = FakeDataBackend();
    authRepository = AuthRepository(
      backend: FakeAuthBackend(),
      executor: executor,
    );
    storageRepository = StorageRepository(
      backend: FakeStorageBackend(),
      executor: executor,
    );
    realtimeRepository = RealtimeRepository(backend: FakeRealtimeBackend());
    productsRepository = ProductsRepository(
      backend: data,
      executor: executor,
      realtime: realtimeRepository,
    );
    usersRepository = UsersRepository(
      backend: data,
      executor: executor,
      realtime: realtimeRepository,
    );
  }

  final BackendConfiguration configuration;

  late final RequestExecutor executor;
  @override
  late final FakeDataBackend data;
  late final AuthRepository authRepository;
  late final StorageRepository storageRepository;
  late final RealtimeRepository realtimeRepository;
  late final ProductsRepository productsRepository;
  late final UsersRepository usersRepository;

  @override
  AuthRepository get auth => authRepository;

  @override
  StorageRepository get storage => storageRepository;

  @override
  RealtimeRepository get realtime => realtimeRepository;

  @override
  ProductsRepository get products => productsRepository;

  @override
  UsersRepository get users => usersRepository;

  @override
  Future<void> dispose() async {
    await realtimeRepository.dispose();
    await authRepository.dispose();
    await storageRepository.dispose();
  }
}
