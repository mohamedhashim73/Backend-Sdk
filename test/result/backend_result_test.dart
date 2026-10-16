import 'dart:async';

import 'package:backend_sdk/backend_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_data_backend.dart';
import '../support/test_helpers.dart';

void main() {
  group('BackendResult', () {
    test('a success exposes its value and no failure', () {
      const result = BackendSuccess<int>(7);

      expect(result.isSuccess, isTrue);
      expect(result.isFailure, isFalse);
      expect(result.data, 7);
      expect(result.failure, isNull);
    });

    test('a failure exposes its error and no value', () {
      final failure = BackendErrorClassifier.build(
        type: BackendErrorType.notFound,
        message: 'missing',
      );
      final result = failureOf<int>(failure);

      expect(result.isSuccess, isFalse);
      expect(result.isFailure, isTrue);
      expect(result.data, isNull);
      expect(result.failure, same(failure));
    });

    test('when dispatches to the matching branch', () {
      const success = BackendSuccess<int>(1);
      final failure = failureOf<int>(
        BackendErrorClassifier.build(
          type: BackendErrorType.server,
          message: 'boom',
        ),
      );

      expect(success.when(success: (v) => 'ok:$v', failure: (f) => f.type.name),
          'ok:1');
      expect(failure.when(success: (v) => 'ok:$v', failure: (f) => f.type.name),
          'server');
    });

    test('map transforms a success and preserves a failure identity', () {
      const success = BackendSuccess<int>(2);
      final original = BackendErrorClassifier.build(
        type: BackendErrorType.validation,
        message: 'bad',
      );

      expect(success.map((v) => v * 10).data, 20);
      expect(
          failureOf<int>(original).map((v) => v * 10).failure, same(original));
    });

    test('getOrElse falls back only for a failure', () {
      expect(const BackendSuccess<int>(5).getOrElse((_) => -1), 5);
      expect(
        failureOf<int>(
          BackendErrorClassifier.build(
            type: BackendErrorType.network,
            message: 'offline',
          ),
        ).getOrElse((_) => -1),
        -1,
      );
    });

    test('unwrap returns the value and throws the failure', () {
      expect(unwrap(const BackendSuccess<int>(3)), 3);

      final failure = BackendErrorClassifier.build(
        type: BackendErrorType.forbidden,
        message: 'denied',
      );
      expect(() => unwrap(failureOf<int>(failure)), throwsA(same(failure)));
    });

    test('extensions unwrap and resolve asynchronous branches', () async {
      const success = BackendSuccess<int>(3);
      expect(success.unwrapOrThrow(), 3);
      expect(
        await success.whenAsync(
          success: (value) async => value * 2,
          failure: (_) async => -1,
        ),
        6,
      );

      final failure = BackendErrorClassifier.build(
        type: BackendErrorType.forbidden,
        message: 'denied',
      );
      expect(
        () => failureOf<int>(failure).unwrapOrThrow(),
        throwsA(same(failure)),
      );
      expect(
        await failureOf<int>(failure).whenAsync(
          success: (_) async => 'success',
          failure: (error) async => error.type.name,
        ),
        'forbidden',
      );
    });
  });

  group('BackendFailure', () {
    test('derives retryability from the error type', () {
      expect(BackendErrorType.network.isRetryable, isTrue);
      expect(BackendErrorType.timeout.isRetryable, isTrue);
      expect(BackendErrorType.rateLimited.isRetryable, isTrue);
      expect(BackendErrorType.server.isRetryable, isTrue);

      for (final type in <BackendErrorType>[
        BackendErrorType.configuration,
        BackendErrorType.cancelled,
        BackendErrorType.unauthorized,
        BackendErrorType.forbidden,
        BackendErrorType.validation,
        BackendErrorType.notFound,
        BackendErrorType.conflict,
        BackendErrorType.database,
        BackendErrorType.storage,
        BackendErrorType.realtime,
        BackendErrorType.unsupportedProvider,
        BackendErrorType.unknown,
      ]) {
        expect(type.isRetryable, isFalse,
            reason: '$type must not be retryable');
      }
    });

    test('safeMessage falls back to a default per type', () {
      final failure = BackendErrorClassifier.build(
        type: BackendErrorType.unauthorized,
        message: 'JWT expired',
      );

      expect(failure.safeMessage, contains('sign in'));
      expect(failure.message, 'JWT expired');
    });

    test('an explicit userMessage wins over the default', () {
      final failure = BackendErrorClassifier.build(
        type: BackendErrorType.validation,
        message: 'internal detail',
        userMessage: 'Please check your email.',
      );

      expect(failure.safeMessage, 'Please check your email.');
    });

    test('toString omits the cause and any secret-looking content', () {
      final failure = BackendFailure(
        type: BackendErrorType.unknown,
        message: 'failed',
        isRetryable: false,
        cause: StateError('inner detail with a token'),
      );

      expect(failure.toString(), isNot(contains('inner detail')));
    });

    test('copyWith keeps or clears fields explicitly', () {
      final original = BackendErrorClassifier.build(
        type: BackendErrorType.network,
        message: 'a',
        userMessage: 'b',
      );

      expect(original.copyWith(type: BackendErrorType.timeout).type,
          BackendErrorType.timeout);
      expect(
          original.copyWith(type: BackendErrorType.timeout).userMessage, 'b');
      expect(original.copyWith(clearUserMessage: true).userMessage, isNull);
    });
  });

  group('BackendErrorClassifier', () {
    test('maps HTTP status codes', () {
      expect(BackendErrorClassifier.fromStatusCode(400),
          BackendErrorType.validation);
      expect(BackendErrorClassifier.fromStatusCode(401),
          BackendErrorType.unauthorized);
      expect(BackendErrorClassifier.fromStatusCode(403),
          BackendErrorType.forbidden);
      expect(BackendErrorClassifier.fromStatusCode(404),
          BackendErrorType.notFound);
      expect(BackendErrorClassifier.fromStatusCode(409),
          BackendErrorType.conflict);
      expect(BackendErrorClassifier.fromStatusCode(429),
          BackendErrorType.rateLimited);
      expect(
          BackendErrorClassifier.fromStatusCode(503), BackendErrorType.server);
      expect(BackendErrorClassifier.fromStatusCode(200), isNull);
      expect(BackendErrorClassifier.fromStatusCode(null), isNull);
    });

    test('maps SQLSTATE codes', () {
      expect(
          BackendErrorClassifier.fromCode('23505'), BackendErrorType.conflict);
      expect(BackendErrorClassifier.fromCode('23503'),
          BackendErrorType.validation);
      expect(
          BackendErrorClassifier.fromCode('42501'), BackendErrorType.forbidden);
      expect(
          BackendErrorClassifier.fromCode('23502'), BackendErrorType.database);
    });

    test('maps auth provider codes', () {
      expect(BackendErrorClassifier.fromCode('invalid_credentials'),
          BackendErrorType.unauthorized);
      expect(BackendErrorClassifier.fromCode('email_exists'),
          BackendErrorType.conflict);
      expect(BackendErrorClassifier.fromCode('email_not_confirmed'),
          BackendErrorType.validation);
      expect(BackendErrorClassifier.fromCode('over_request_rate_limit'),
          BackendErrorType.rateLimited);
    });

    test('a code takes precedence over the status code', () {
      expect(
        BackendErrorClassifier.resolve(
          code: 'email_exists',
          statusCode: 500,
          fallbackType: BackendErrorType.unknown,
        ),
        BackendErrorType.conflict,
      );
    });

    test('falls back to the operation category', () {
      expect(
        BackendErrorClassifier.resolve(
          statusCode: null,
          fallbackType: BackendErrorType.storage,
        ),
        BackendErrorType.storage,
      );
    });

    test('classifies a TimeoutException as retryable timeout', () {
      final failure = BackendErrorClassifier.fromException(
        TimeoutException('slow'),
        StackTrace.current,
        fallbackType: BackendErrorType.database,
      );

      expect(failure.type, BackendErrorType.timeout);
      expect(failure.isRetryable, isTrue);
    });

    test('classifies a socket failure as network without importing dart:io',
        () {
      final failure = BackendErrorClassifier.fromException(
        _FakeSocketException(),
        StackTrace.current,
        fallbackType: BackendErrorType.database,
      );

      expect(failure.type, BackendErrorType.network);
      expect(failure.isRetryable, isTrue);
    });

    test('classifies a malformed response as a validation failure', () {
      final failure = BackendErrorClassifier.fromException(
        const FormatException('bad json'),
        StackTrace.current,
        fallbackType: BackendErrorType.database,
      );

      expect(failure.type, BackendErrorType.validation);
    });
  });

  group('FakeDataBackend sanity', () {
    test('the test double never touches the network', () async {
      final backend = FakeDataBackend();
      backend.seed(BackendResource.products, productRow(id: 'p1'));

      final result = await backend.readById(
        resource: BackendResource.products,
        id: 'p1',
      );

      expect(result.data?['id'], 'p1');
    });
  });
}

/// A stand-in whose runtime type name contains `SocketException`.
///
/// The real `dart:io` type cannot be referenced because this package must also
/// compile for the web, which is why the classifier matches on the type name.
class _FakeSocketException implements Exception {
  @override
  String toString() => 'SocketException: connection refused';
}
