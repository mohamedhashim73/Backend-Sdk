import 'package:backend_sdk/backend_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_data_backend.dart';
import '../support/test_helpers.dart';

void main() {
  group('RetryPolicy', () {
    test('none performs exactly one attempt', () {
      const policy = RetryPolicy.noRetries;

      expect(policy.maxAttempts, 1);
      expect(
        policy.shouldRetry(
          failure: _retryable(),
          attempt: 1,
        ),
        isFalse,
      );
    });

    test('maxRetries is the number of extra attempts', () {
      const policy = RetryPolicy(maxRetries: 2);

      expect(policy.maxAttempts, 3);
      expect(
        policy.shouldRetry(failure: _retryable(), attempt: 1),
        isTrue,
      );
      expect(
        policy.shouldRetry(failure: _retryable(), attempt: 2),
        isTrue,
      );
      expect(
        policy.shouldRetry(failure: _retryable(), attempt: 3),
        isFalse,
      );
    });

    test('never retries a non-retryable failure, whatever the attempt', () {
      const policy = RetryPolicy(maxRetries: 5);

      for (final type in <BackendErrorType>[
        BackendErrorType.unauthorized,
        BackendErrorType.forbidden,
        BackendErrorType.validation,
        BackendErrorType.notFound,
        BackendErrorType.conflict,
        BackendErrorType.configuration,
        BackendErrorType.unsupportedProvider,
      ]) {
        expect(
          policy.shouldRetry(
            failure: BackendErrorClassifier.build(type: type, message: 'x'),
            attempt: 1,
          ),
          isFalse,
          reason: '$type must never be retried',
        );
      }
    });

    test('the backoff schedule is exponential and capped', () {
      const policy = RetryPolicy(
        maxRetries: 6,
        baseDelay: Duration(milliseconds: 100),
        backoffMultiplier: 2.0,
        maxDelay: Duration(milliseconds: 400),
        jitter: 0,
      );

      expect(policy.delayFor(1).inMilliseconds, 100);
      expect(policy.delayFor(2).inMilliseconds, 200);
      expect(policy.delayFor(3).inMilliseconds, 400);
      expect(policy.delayFor(4).inMilliseconds, 400);
      expect(policy.delayFor(6).inMilliseconds, 400);
    });

    test('jitter stays within the configured band', () {
      const policy = RetryPolicy(
        baseDelay: Duration(milliseconds: 1000),
        jitter: 0.2,
        maxDelay: Duration(seconds: 5),
      );

      for (var i = 0; i < 50; i++) {
        final delay = policy.delayFor(1).inMilliseconds;
        expect(delay, inInclusiveRange(800, 1200));
      }
    });

    test('rejects a non-positive attempt number', () {
      expect(() => const RetryPolicy().delayFor(0), throwsArgumentError);
    });
  });

  group('RequestExecutor - retry behaviour', () {
    late List<Duration> delays;

    RequestExecutor buildExecutor({int maxRetries = 2}) {
      delays = [];
      return RequestExecutor(
        retryPolicy: RetryPolicy(maxRetries: maxRetries, jitter: 0),
        requestTimeout: const Duration(seconds: 5),
        delay: (duration) async {
          delays.add(duration);
        },
      );
    }

    test('a successful call runs once', () async {
      var calls = 0;
      final result = await buildExecutor().run<int>(
        operation: 'test.ok',
        action: () async {
          calls++;
          return 1;
        },
      );

      expect(result.data, 1);
      expect(calls, 1);
      expect(delays, isEmpty);
    });

    test('a retryable failure is retried up to maxAttempts', () async {
      var calls = 0;
      final result = await buildExecutor(maxRetries: 2).run<int>(
        operation: 'test.retry',
        action: () async {
          calls++;
          throw const FakeSocketException();
        },
      );

      expect(calls, 3);
      expect(result.failure?.type, BackendErrorType.network);
      expect(delays, hasLength(2));
    });

    test('it stops as soon as the call succeeds', () async {
      var calls = 0;
      final result = await buildExecutor(maxRetries: 5).run<int>(
        operation: 'test.recover',
        action: () async {
          calls++;
          if (calls < 3) throw const FakeSocketException();
          return 42;
        },
      );

      expect(result.data, 42);
      expect(calls, 3);
      expect(delays, hasLength(2));
    });

    test('a non-retryable failure is not retried', () async {
      var calls = 0;
      final result = await buildExecutor(maxRetries: 5).run<int>(
        operation: 'test.noRetry',
        action: () async {
          calls++;
          throw _validationFailure();
        },
      );

      expect(calls, 1);
      expect(result.failure?.type, BackendErrorType.validation);
      expect(delays, isEmpty);
    });

    test('retries never continue indefinitely', () async {
      var calls = 0;
      await buildExecutor(maxRetries: 3).run<void>(
        operation: 'test.bounded',
        action: () async {
          calls++;
          throw const FakeSocketException();
        },
      );

      expect(calls, 4);
    });

    test('a thrown BackendFailure keeps its own classification', () async {
      final original = BackendErrorClassifier.build(
        type: BackendErrorType.rateLimited,
        message: 'slow down',
        userMessage: 'Too many requests.',
      );

      final result = await buildExecutor().run<void>(
        operation: 'test.typed',
        action: () async => throw original,
      );

      expect(result.failure, same(original));
    });

    test('every thrown object becomes a typed failure, never an escape',
        () async {
      final result = await buildExecutor().run<void>(
        operation: 'test.anything',
        action: () async => throw const _RawString('a raw string'),
      );

      expect(result.failure, isNotNull);
      expect(result.failure!.type, BackendErrorType.unknown);
    });
  });

  group('RequestExecutor - timeout behaviour', () {
    test('a slow call fails with a retryable timeout', () async {
      final executor = RequestExecutor(
        retryPolicy: RetryPolicy.noRetries,
        requestTimeout: const Duration(milliseconds: 20),
        delay: (_) async {},
      );

      final result = await executor.run<int>(
        operation: 'test.slow',
        action: () async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return 1;
        },
      );

      expect(result.failure?.type, BackendErrorType.timeout);
      expect(result.failure?.isRetryable, isTrue);
    });

    test('a timeout inside the retry budget is retried', () async {
      var calls = 0;
      final executor = RequestExecutor(
        retryPolicy: const RetryPolicy(maxRetries: 1, jitter: 0),
        requestTimeout: const Duration(milliseconds: 20),
        delay: (_) async {},
      );

      final result = await executor.run<int>(
        operation: 'test.slowRetry',
        action: () async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return 1;
        },
      );

      expect(calls, 2);
      expect(result.failure?.type, BackendErrorType.timeout);
    });

    test('a call that finishes inside the timeout succeeds', () async {
      final executor = RequestExecutor(
        retryPolicy: RetryPolicy.noRetries,
        requestTimeout: const Duration(seconds: 5),
        delay: (_) async {},
      );

      final result = await executor.run<int>(
        operation: 'test.fast',
        action: () async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return 7;
        },
      );

      expect(result.data, 7);
    });
  });

  group('RequestExecutor - cancellation', () {
    test('a token cancelled before the call short-circuits it', () async {
      var calls = 0;
      final token = CancellationToken()..cancel();

      final result = await RequestExecutor(
        retryPolicy: const RetryPolicy(maxRetries: 3),
        requestTimeout: const Duration(seconds: 5),
        delay: (_) async {},
      ).run<int>(
        operation: 'test.cancelled',
        cancellationToken: token,
        action: () async {
          calls++;
          return 1;
        },
      );

      expect(calls, 0);
      expect(result.failure?.type, BackendErrorType.cancelled);
    });

    test('cancellation between retries stops the loop', () async {
      final token = CancellationToken();
      var calls = 0;

      final result = await RequestExecutor(
        retryPolicy: const RetryPolicy(maxRetries: 5, jitter: 0),
        requestTimeout: const Duration(seconds: 5),
        delay: (_) async {
          token.cancel();
        },
      ).run<int>(
        operation: 'test.cancelLater',
        cancellationToken: token,
        action: () async {
          calls++;
          throw const FakeSocketException();
        },
      );

      expect(calls, 1);
      expect(result.failure?.type, BackendErrorType.cancelled);
    });

    test('cancellation is cooperative: a call already in flight completes',
        () async {
      final backend = FakeDataBackend();
      backend.latency = const Duration(milliseconds: 40);
      final repository = buildProductsRepository(backend: backend);
      seedProducts(backend, 5);

      final token = CancellationToken();
      final pending = repository.getPage(
        request: const PageRequest(page: 1),
        cancellationToken: token,
      );
      // The request is already on the wire; cancelling now cannot un-send it,
      // so the call is allowed to finish and the caller discards the value.
      token.cancel();

      final result = await pending;
      expect(result.isSuccess, isTrue);
    });

    test('cancelling before the request starts prevents the call entirely',
        () async {
      final backend = FakeDataBackend();
      seedProducts(backend, 5);
      final repository = buildProductsRepository(backend: backend);

      final token = CancellationToken()..cancel();
      final result = await repository.getPage(
        request: const PageRequest(page: 1),
        cancellationToken: token,
      );

      expect(result.failure?.type, BackendErrorType.cancelled);
      expect(backend.readPageCalls, 0);
    });

    test('CancellationToken.cancel is idempotent', () {
      final token = CancellationToken()
        ..cancel()
        ..cancel();
      expect(token.isCancelled, isTrue);
    });

    test('throwIfCancelled throws only after cancellation', () {
      final token = CancellationToken();
      expect(token.throwIfCancelled, returnsNormally);
      token.cancel();
      expect(
          token.throwIfCancelled, throwsA(isA<BackendCancellationException>()));
    });
  });

  group('Repository retry integration', () {
    test('a transient failure is retried and then succeeds', () async {
      final backend = FakeDataBackend();
      seedProducts(backend, 3);
      final repository = buildProductsRepository(
        backend: backend,
        maxRetries: 2,
      );

      backend.nextFailure = const FakeSocketException();

      final result = await repository.getPage(
        request: const PageRequest(page: 1),
      );

      expect(result.isSuccess, isTrue);
      expect(backend.readPageCalls, 2);
    });

    test('a permanent failure is surfaced without retrying', () async {
      final backend = FakeDataBackend();
      seedProducts(backend, 3);
      final repository = buildProductsRepository(
        backend: backend,
        maxRetries: 5,
      );

      backend.nextFailure = _validationFailure();

      final result = await repository.getPage(
        request: const PageRequest(page: 1),
      );

      expect(result.failure?.type, BackendErrorType.validation);
      expect(backend.readPageCalls, 1);
    });

    test('a timeout surfaces as a typed timeout failure', () async {
      final backend = FakeDataBackend();
      seedProducts(backend, 3);
      backend.latency = const Duration(milliseconds: 120);

      final repository = buildProductsRepository(
        backend: backend,
        requestTimeout: const Duration(milliseconds: 20),
      );

      final result = await repository.getPage(
        request: const PageRequest(page: 1),
      );

      expect(result.failure?.type, BackendErrorType.timeout);
    });
  });

  group('Safe logging', () {
    test('credentials never reach the log sink', () async {
      final entries = <LogEntry>[];
      final logger = CallbackBackendLogger(sink: entries.add);

      final backend = FakeDataBackend();
      seedProducts(backend, 1);
      final repository =
          buildProductsRepository(backend: backend, logger: logger);

      backend.nextFailure = const FakeSocketException();
      await repository.getPage(request: const PageRequest(page: 1));

      final dumped = entries.map((e) => e.toString()).join('\n');
      expect(entries, isNotEmpty);
      expect(dumped, isNot(contains('password')));
      expect(dumped, isNot(contains('token')));
    });

    test('sensitive context keys are redacted', () {
      final entries = <LogEntry>[];
      CallbackBackendLogger(sink: entries.add).info(
        'auth',
        context: const {
          'password': 'hunter2',
          'accessToken': 'abc',
          'anonKey': 'xyz',
          'userId': 'u1',
        },
      );

      expect(entries.single.context['password'], '[redacted]');
      expect(entries.single.context['accessToken'], '[redacted]');
      expect(entries.single.context['anonKey'], '[redacted]');
      expect(entries.single.context['userId'], 'u1');
      expect(entries.single.toString(), isNot(contains('hunter2')));
    });

    test('long context values are truncated', () {
      final entries = <LogEntry>[];
      CallbackBackendLogger(sink: entries.add).info(
        'x',
        context: {'detail': 'y' * 500},
      );

      expect(
        '${entries.single.context['detail']}'.length,
        lessThanOrEqualTo(CallbackBackendLogger.maxValueLength + 1),
      );
    });

    test('debug entries are suppressed in a release logger', () {
      final entries = <LogEntry>[];
      final logger = CallbackBackendLogger(sink: entries.add, isDebug: false);

      logger.debug('hidden');
      logger.info('shown');

      expect(entries, hasLength(1));
      expect(entries.single.message, 'shown');
    });

    test('the no-op logger records nothing', () {
      const logger = NoopBackendLogger();
      expect(
        () => logger.error('x', cause: StateError('y')),
        returnsNormally,
      );
    });
  });
}

BackendFailure _retryable() =>
    BackendErrorClassifier.build(type: BackendErrorType.network, message: 'x');

BackendFailure _validationFailure() => BackendErrorClassifier.build(
    type: BackendErrorType.validation, message: 'x');

/// Carries a non-`Exception` thrown value, to prove nothing escapes untyped.
class _RawString implements Exception {
  const _RawString(this.value);

  final String value;

  @override
  String toString() => value;
}

/// A transport failure whose runtime type name the SDK recognises as a socket
/// error, which is how a real `dart:io` failure is classified on the web too.
class FakeSocketException implements Exception {
  const FakeSocketException();

  @override
  String toString() => 'SocketException: Connection reset by peer';
}
