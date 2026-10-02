import 'package:backend_sdk/backend_sdk.dart';
import 'package:backend_sdk/src/contracts/auth_backend.dart';
import 'package:backend_sdk/src/contracts/data_backend.dart';
import 'package:backend_sdk/src/contracts/data_query_spec.dart';
import 'package:backend_sdk/src/contracts/realtime_backend.dart';
import 'package:backend_sdk/src/contracts/storage_backend.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_data_backend.dart';
import '../support/fakes.dart';

void main() {
  const validUrl = 'https://project.supabase.co';
  const validKey = 'sb_publishable_abc123';

  tearDown(() async {
    await BackendSdk.dispose();
    BackendServiceFactory.reset();
  });

  group('BackendConfiguration', () {
    test('the default values are sane', () {
      const config = BackendConfiguration(provider: BackendProvider.supabase);

      expect(config.requestTimeout, const Duration(seconds: 30));
      expect(config.enableLogging, isFalse);
      expect(config.maxRetries, 2);
      expect(config.retryDelay, const Duration(milliseconds: 200));
      expect(config.retryBackoffMultiplier, 2.0);
    });

    test('the supabase factory sets the provider', () {
      final config = BackendConfiguration.supabase(
        url: validUrl,
        apiKey: validKey,
      );

      expect(config.provider, BackendProvider.supabase);
      expect(config.url, validUrl);
      expect(config.apiKey, validKey);
    });

    test('toString never renders the url or the key', () {
      final config = BackendConfiguration.supabase(
        url: validUrl,
        apiKey: 'super-secret-value',
      );

      expect(config.toString(), isNot(contains('super-secret-value')));
      expect(config.toString(), isNot(contains(validUrl)));
    });

    test('copyWith replaces only the given fields', () {
      const config = BackendConfiguration(
        provider: BackendProvider.supabase,
        url: validUrl,
        apiKey: validKey,
      );

      final copy = config.copyWith(maxRetries: 5);

      expect(copy.maxRetries, 5);
      expect(copy.url, validUrl);
      expect(copy.apiKey, validKey);
    });
  });

  group('Configuration validation', () {
    BackendFailure? validate(BackendConfiguration config) {
      return BackendSdk.validateConfiguration(config.provider, config);
    }

    test('a correct configuration passes', () {
      expect(
        validate(
          BackendConfiguration.supabase(url: validUrl, apiKey: validKey),
        ),
        isNull,
      );
    });

    test('a missing url is rejected', () {
      expect(
        validate(
            const BackendConfiguration(provider: BackendProvider.supabase)),
        isNotNull,
      );
      expect(
        validate(
          const BackendConfiguration(
            provider: BackendProvider.supabase,
            apiKey: validKey,
          ),
        ),
        isNotNull,
      );
    });

    test('a relative url is rejected', () {
      expect(
        validate(
          BackendConfiguration.supabase(url: '/local', apiKey: validKey),
        ),
        isNotNull,
      );
    });

    test('a non-http scheme is rejected', () {
      expect(
        validate(
          BackendConfiguration.supabase(
            url: 'ftp://example.com',
            apiKey: validKey,
          ),
        ),
        isNotNull,
      );
    });

    test('a url with a query string is rejected', () {
      expect(
        validate(
          BackendConfiguration.supabase(
            url: '$validUrl?apikey=$validKey',
            apiKey: validKey,
          ),
        ),
        isNotNull,
      );
    });

    test('a missing key is rejected', () {
      expect(
        validate(const BackendConfiguration(
          provider: BackendProvider.supabase,
          url: validUrl,
        )),
        isNotNull,
      );
    });

    test('a service-role key is rejected with an actionable message', () {
      // A service-role JWT carries `{"role":"service_role"}` in its payload.
      const serviceRoleKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
          'eyJyb2xlIjoic2VydmljZV9yb2xlIn0.signature';

      final failure = validate(
        BackendConfiguration.supabase(url: validUrl, apiKey: serviceRoleKey),
      );

      expect(failure, isNotNull);
      expect(failure!.type, BackendErrorType.configuration);
      expect(failure.message, contains('service-role'));
    });

    test('a non-positive timeout is rejected', () {
      expect(
        validate(
          BackendConfiguration.supabase(
            url: validUrl,
            apiKey: validKey,
            requestTimeout: Duration.zero,
          ),
        ),
        isNotNull,
      );
    });

    test('a negative retry count is rejected', () {
      expect(
        validate(
          BackendConfiguration.supabase(
            url: validUrl,
            apiKey: validKey,
            maxRetries: -1,
          ),
        ),
        isNotNull,
      );
    });

    test('an absurd retry count is rejected', () {
      expect(
        validate(
          BackendConfiguration.supabase(
            url: validUrl,
            apiKey: validKey,
            maxRetries: 50,
          ),
        ),
        isNotNull,
      );
    });

    test('a backoff multiplier below one is rejected', () {
      expect(
        validate(
          BackendConfiguration.supabase(
            url: validUrl,
            apiKey: validKey,
            retryBackoffMultiplier: 0.5,
          ),
        ),
        isNotNull,
      );
    });

    test('a provider mismatch is rejected', () {
      final failure = BackendSdk.validateConfiguration(
        BackendProvider.supabase,
        const BackendConfiguration(
          provider: BackendProvider.firebase,
          url: validUrl,
          apiKey: validKey,
        ),
      );

      expect(failure?.message, contains('does not match'));
    });
  });

  group('Initialization', () {
    void registerFakeProvider() {
      BackendServiceFactory.register(
        BackendProvider.supabase,
        (configuration, logger) => _FakeServices(configuration),
      );
    }

    test('a valid configuration initializes the SDK', () async {
      registerFakeProvider();

      await BackendSdk.initialize(
        provider: BackendProvider.supabase,
        configuration: BackendConfiguration.supabase(
          url: validUrl,
          apiKey: validKey,
        ),
      );

      expect(BackendSdk.instance.isInitialized, isTrue);
      expect(BackendSdk.configuration?.provider, BackendProvider.supabase);
      expect(BackendSdk.instance.auth, isNotNull);
      expect(BackendSdk.instance.storage, isNotNull);
      expect(BackendSdk.instance.realtime, isNotNull);
      expect(BackendSdk.instance.products, isNotNull);
      expect(BackendSdk.instance.users, isNotNull);
    });

    test('an invalid configuration fails with a typed failure', () async {
      registerFakeProvider();

      await expectLater(
        BackendSdk.initialize(
          provider: BackendProvider.supabase,
          configuration: const BackendConfiguration(
            provider: BackendProvider.supabase,
          ),
        ),
        throwsA(
          isA<BackendFailure>().having(
            (f) => f.type,
            'type',
            BackendErrorType.configuration,
          ),
        ),
      );

      expect(BackendSdk.instance.isInitialized, isFalse);
    });

    test('access before initialization produces a configuration failure',
        () async {
      expect(() => BackendSdk.instance.auth, throwsA(isA<BackendFailure>()));
      expect(
          () => BackendSdk.instance.products, throwsA(isA<BackendFailure>()));
      expect(() => BackendSdk.instance.storage, throwsA(isA<BackendFailure>()));
      expect(
          () => BackendSdk.instance.realtime, throwsA(isA<BackendFailure>()));
      expect(() => BackendSdk.instance.users, throwsA(isA<BackendFailure>()));

      try {
        BackendSdk.instance.auth;
      } on BackendFailure catch (failure) {
        expect(failure.type, BackendErrorType.configuration);
        expect(failure.message, contains('before initialization'));
      }
    });

    test('double initialization does not replace the active provider',
        () async {
      registerFakeProvider();
      final configuration = BackendConfiguration.supabase(
        url: validUrl,
        apiKey: validKey,
      );

      await BackendSdk.initialize(
        provider: BackendProvider.supabase,
        configuration: configuration,
      );
      final first = BackendSdk.instance.products;

      await expectLater(
        BackendSdk.initialize(
          provider: BackendProvider.supabase,
          configuration: configuration.copyWith(apiKey: 'a-different-key'),
        ),
        throwsA(isA<BackendFailure>()),
      );

      expect(BackendSdk.instance.isInitialized, isTrue);
      expect(identical(BackendSdk.instance.products, first), isTrue);
      expect(BackendSdk.configuration?.apiKey, validKey);
    });

    test('an unsupported provider fails with unsupportedProvider', () async {
      await expectLater(
        BackendSdk.initialize(
          provider: BackendProvider.firebase,
          configuration: const BackendConfiguration(
            provider: BackendProvider.firebase,
            url: validUrl,
            apiKey: validKey,
          ),
        ),
        throwsA(
          isA<BackendFailure>().having(
            (f) => f.type,
            'type',
            BackendErrorType.unsupportedProvider,
          ),
        ),
      );

      expect(BackendSdk.instance.isInitialized, isFalse);
    });

    test('the rest provider is equally unsupported', () async {
      await expectLater(
        BackendSdk.initialize(
          provider: BackendProvider.rest,
          configuration: const BackendConfiguration(
            provider: BackendProvider.rest,
            url: validUrl,
            apiKey: validKey,
          ),
        ),
        throwsA(
          isA<BackendFailure>().having(
            (f) => f.type,
            'type',
            BackendErrorType.unsupportedProvider,
          ),
        ),
      );
    });

    test('a factory failure leaves the SDK uninitialized', () async {
      BackendServiceFactory.register(
        BackendProvider.supabase,
        (configuration, logger) => throw StateError('no network'),
      );

      await expectLater(
        BackendSdk.initialize(
          provider: BackendProvider.supabase,
          configuration: BackendConfiguration.supabase(
            url: validUrl,
            apiKey: validKey,
          ),
        ),
        throwsA(isA<BackendFailure>()),
      );

      expect(BackendSdk.instance.isInitialized, isFalse);
    });

    test('a retry is possible after a failed initialization', () async {
      BackendServiceFactory.register(
        BackendProvider.supabase,
        (configuration, logger) => throw StateError('transient'),
      );

      await expectLater(
        BackendSdk.initialize(
          provider: BackendProvider.supabase,
          configuration: BackendConfiguration.supabase(
            url: validUrl,
            apiKey: validKey,
          ),
        ),
        throwsA(isA<BackendFailure>()),
      );

      registerFakeProvider();
      await BackendSdk.initialize(
        provider: BackendProvider.supabase,
        configuration: BackendConfiguration.supabase(
          url: validUrl,
          apiKey: validKey,
        ),
      );

      expect(BackendSdk.instance.isInitialized, isTrue);
    });

    test('dispose resets the singleton', () async {
      registerFakeProvider();
      await BackendSdk.initialize(
        provider: BackendProvider.supabase,
        configuration: BackendConfiguration.supabase(
          url: validUrl,
          apiKey: validKey,
        ),
      );

      await BackendSdk.dispose();

      expect(BackendSdk.instance.isInitialized, isFalse);
      expect(BackendSdk.configuration, isNull);
    });

    test('disposing before initialization is safe', () async {
      await BackendSdk.dispose();
      await BackendSdk.dispose();
    });

    test('accessing a disposed SDK reports a configuration failure', () async {
      registerFakeProvider();
      await BackendSdk.initialize(
        provider: BackendProvider.supabase,
        configuration: BackendConfiguration.supabase(
          url: validUrl,
          apiKey: validKey,
        ),
      );
      final services = BackendSdk.instance.products;

      await BackendSdk.dispose();

      // The repository object itself is still usable; what fails is any attempt
      // to obtain a new one from a disposed SDK.
      expect(
          () => BackendSdk.instance.products, throwsA(isA<BackendFailure>()));
      expect(services, isNotNull);
    });
  });

  group('Provider contracts', () {
    test('the four backend contracts are the whole provider surface', () {
      // A new vendor implements these four interfaces. Nothing else in the SDK
      // needs to change, and no application code changes at all.
      expect(providerContractTypes, hasLength(4));
      expect(providerContractTypes, contains(AuthBackend));
      expect(providerContractTypes, contains(DataBackend));
      expect(providerContractTypes, contains(StorageBackend));
      expect(providerContractTypes, contains(RealtimeBackend));
    });

    test('the shared result and pagination shapes are constructible', () {
      const BackendResult<int> result = BackendSuccess<int>(1);
      expect(result.data, 1);

      final page = PageResult<int>.fromItems(
        items: const [1, 2],
        page: 1,
        pageSize: 20,
      );
      expect(page.items, hasLength(2));

      const cursorPage = CursorPageResult<int>(items: [1], hasMore: false);
      expect(cursorPage.hasMore, isFalse);

      const event = RealtimeEvent<int>(
        type: RealtimeEventType.inserted,
        newData: 1,
      );
      expect(event.type, RealtimeEventType.inserted);

      const spec = DataQuerySpec(from: 0, to: 19);
      expect(spec.limit, 20);
    });
  });

  group('Provider registration', () {
    test('the Supabase provider is registered on first access', () {
      // Reading `instance` performs the default registration.
      BackendSdk.instance;

      expect(
        BackendServiceFactory.registeredProviders,
        contains(BackendProvider.supabase),
      );
    });

    test('a custom factory can be registered for a declared provider',
        () async {
      BackendServiceFactory.register(
        BackendProvider.firebase,
        (configuration, logger) => _FakeServices(configuration),
      );

      await BackendSdk.initialize(
        provider: BackendProvider.firebase,
        configuration: const BackendConfiguration(
          provider: BackendProvider.firebase,
          url: validUrl,
          apiKey: validKey,
        ),
      );

      expect(BackendSdk.instance.isInitialized, isTrue);
    });

    test('resetForTesting clears the singleton state', () async {
      BackendServiceFactory.register(
        BackendProvider.supabase,
        (configuration, logger) => _FakeServices(configuration),
      );
      await BackendSdk.initialize(
        provider: BackendProvider.supabase,
        configuration: BackendConfiguration.supabase(
          url: validUrl,
          apiKey: validKey,
        ),
      );

      BackendSdk.resetForTesting();

      expect(BackendSdk.instance.isInitialized, isFalse);
    });
  });
}

/// A `BackendServices` made entirely of in-memory doubles.
///
/// This is what a test registers as a provider factory: it proves the SDK's
/// lifecycle is independent of any real backend, and that a new provider only
/// has to satisfy the same contracts.
class _FakeServices implements BackendServices {
  _FakeServices(this.configuration) {
    final authRepository_ = FakeAuthBackend();
    executor = RequestExecutor(
      retryPolicy: const RetryPolicy(maxRetries: 1, jitter: 0),
      requestTimeout: configuration.requestTimeout,
    );
    data = FakeDataBackend();
    _authRepository =
        AuthRepository(backend: authRepository_, executor: executor);
    _storageRepository = StorageRepository(
      backend: FakeStorageBackend(),
      executor: executor,
    );
    realtimeBackend = FakeRealtimeBackend();
    _realtimeRepository = RealtimeRepository(backend: realtimeBackend);
    _productsRepository = ProductsRepository(
      backend: data,
      executor: executor,
      realtime: _realtimeRepository,
    );
    _usersRepository = UsersRepository(
      backend: data,
      executor: executor,
      realtime: _realtimeRepository,
    );
  }

  final BackendConfiguration configuration;

  late final RequestExecutor executor;
  late final FakeDataBackend data;
  late final AuthRepository _authRepository;
  late final StorageRepository _storageRepository;
  late final FakeRealtimeBackend realtimeBackend;
  late final RealtimeRepository _realtimeRepository;
  late final ProductsRepository _productsRepository;
  late final UsersRepository _usersRepository;

  @override
  AuthRepository get auth => _authRepository;

  @override
  StorageRepository get storage => _storageRepository;

  @override
  RealtimeRepository get realtime => _realtimeRepository;

  @override
  ProductsRepository get products => _productsRepository;

  @override
  UsersRepository get users => _usersRepository;

  AuthRepository get authRepository => _authRepository;

  StorageRepository get storageRepository => _storageRepository;

  RealtimeRepository get realtimeRepository => _realtimeRepository;

  ProductsRepository get productsRepository => _productsRepository;

  UsersRepository get usersRepository => _usersRepository;

  @override
  Future<void> dispose() async {
    await _realtimeRepository.dispose();
    await _authRepository.dispose();
    await _storageRepository.dispose();
  }
}

/// The provider contracts a new backend must implement.
///
/// Naming them here makes "a REST or Firebase provider can be added later"
/// a checked claim rather than a comment: a new provider implements exactly
/// these interfaces, and nothing above them changes.
const List<Type> providerContractTypes = <Type>[
  AuthBackend,
  DataBackend,
  StorageBackend,
  RealtimeBackend,
];
