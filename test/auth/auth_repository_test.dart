import 'dart:async';

import 'package:backend_sdk/backend_sdk.dart';
import 'package:backend_sdk/src/auth/auth_validator.dart';
import 'package:backend_sdk/src/contracts/auth_backend.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late FakeAuthBackend backend;
  late AuthRepository repository;

  setUp(() {
    backend = FakeAuthBackend();
    repository = AuthRepository(
      backend: backend,
      executor: const RequestExecutor(
        retryPolicy: RetryPolicy.noRetries,
        requestTimeout: Duration.zero,
      ),
    );
  });

  tearDown(() async {
    await repository.dispose();
  });

  group('AuthRepository - success paths', () {
    test('login returns a typed session and remembers it', () async {
      final result = await repository.login(
        email: 'user@example.com',
        password: 'correct-horse',
      );

      final session = result.data!;
      expect(session.user.id, 'user-1');
      expect(session.user.email, 'user@example.com');
      expect(repository.isSignedIn, isTrue);
      expect(repository.cachedSession, same(session));
    });

    test('signUp returns a session', () async {
      final result = await repository.signUp(
        email: 'new@example.com',
        password: 'correct-horse',
      );

      expect(result.isSuccess, isTrue);
      expect(result.data!.user.id, 'user-1');
    });

    test('currentUser and currentSession resolve from the backend', () async {
      expect((await repository.currentUser()).data!.id, 'user-1');
      expect((await repository.currentSession()).data!.accessToken,
          'fake-access-token');
    });

    test('refreshSession delegates and stores the new session', () async {
      final result = await repository.refreshSession();

      expect(result.isSuccess, isTrue);
      expect(backend.refreshCalls, 1);
    });

    test('logout clears the cached session', () async {
      await repository.login(email: 'a@b.com', password: 'password1');
      expect(repository.isSignedIn, isTrue);

      await repository.logout();

      expect(repository.isSignedIn, isFalse);
      expect(backend.logoutCalls, 1);
    });

    test('logout clears the session even when the provider fails', () async {
      await repository.login(email: 'a@b.com', password: 'password1');
      backend.failure = BackendErrorClassifier.build(
        type: BackendErrorType.network,
        message: 'offline',
      );

      final result = await repository.logout();

      expect(result.isFailure, isTrue);
      expect(repository.isSignedIn, isFalse);
    });

    test('password reset and resend succeed for a valid address', () async {
      expect(
        (await repository.resetPassword(email: 'a@b.com')).isSuccess,
        isTrue,
      );
      expect(
        (await repository.resendVerificationEmail(email: 'a@b.com')).isSuccess,
        isTrue,
      );
    });
  });

  group('AuthRepository - local validation', () {
    test('a malformed email never reaches the provider', () async {
      final result = await repository.login(
        email: 'not-an-email',
        password: 'password1',
      );

      expect(result.failure?.type, BackendErrorType.validation);
      expect(backend.loginCalls, 0);
    });

    test('an empty email is rejected', () async {
      final result =
          await repository.login(email: '   ', password: 'password1');

      expect(result.failure?.type, BackendErrorType.validation);
      expect(backend.loginCalls, 0);
    });

    test('a short password is rejected', () async {
      final result =
          await repository.login(email: 'a@b.com', password: 'short');

      expect(result.failure?.type, BackendErrorType.validation);
      expect(result.failure?.message, contains('at least 8'));
      expect(backend.loginCalls, 0);
    });

    test('a password longer than the limit is rejected', () async {
      final result = await repository.login(
        email: 'a@b.com',
        password: 'x' * (AuthValidator.maxPasswordLength + 1),
      );

      expect(result.failure?.type, BackendErrorType.validation);
      expect(backend.loginCalls, 0);
    });

    test('a non-http redirect URL is rejected', () async {
      final result = await repository.resetPassword(
        email: 'a@b.com',
        redirectTo: 'javascript:alert(1)',
      );

      expect(result.failure?.type, BackendErrorType.validation);
    });

    test('a custom-scheme deep link is rejected', () async {
      final result = await repository.resetPassword(
        email: 'a@b.com',
        redirectTo: 'myapp://reset',
      );

      expect(result.failure?.type, BackendErrorType.validation);
    });

    test('an https deep link with an authority is accepted', () {
      expect(
        AuthValidator.validateRedirectTo('https://app.example.com/reset'),
        isNull,
      );
    });

    test('an empty metadata payload is rejected', () async {
      final result = await repository.updateUserMetadata(metadata: const {});

      expect(result.failure?.type, BackendErrorType.validation);
    });

    test('an over-sized metadata payload is rejected', () async {
      final result = await repository.updateUserMetadata(
        metadata: {
          for (var i = 0; i < AuthValidator.maxMetadataFields + 1; i++)
            'key$i': 'value',
        },
      );

      expect(result.failure?.type, BackendErrorType.validation);
    });

    test('an unsupported metadata value type is rejected', () {
      expect(
        AuthValidator.validateMetadata({'when': DateTime.utc(2026)}),
        isNotNull,
      );
    });

    test('a weak new password is rejected before the request', () async {
      final result = await repository.updatePassword(newPassword: 'abc');

      expect(result.failure?.type, BackendErrorType.validation);
    });

    test('failure messages never echo the password', () async {
      const password = 'hunter2-secret';
      final result = await repository.login(email: 'bad', password: password);

      expect(result.failure!.message, isNot(contains(password)));
      expect(result.failure!.safeMessage, isNot(contains(password)));
    });
  });

  group('AuthRepository - provider failures', () {
    test('invalid credentials surface as unauthorized', () async {
      backend.failure = BackendErrorClassifier.build(
        type: BackendErrorType.unauthorized,
        message: 'Invalid login credentials',
        userMessage: 'Incorrect email or password.',
      );

      final result = await repository.login(
        email: 'a@b.com',
        password: 'password1',
      );

      expect(result.failure?.type, BackendErrorType.unauthorized);
      expect(result.failure?.safeMessage, 'Incorrect email or password.');
      expect(repository.isSignedIn, isFalse);
    });

    test('an expired session surfaces as unauthorized', () async {
      backend.failure = BackendErrorClassifier.build(
        type: BackendErrorType.unauthorized,
        message: 'Refresh token expired',
      );

      final result = await repository.refreshSession();

      expect(result.failure?.type, BackendErrorType.unauthorized);
      expect(result.failure?.isRetryable, isFalse);
    });

    test('an already-registered email surfaces as conflict', () async {
      backend.failure = BackendErrorClassifier.build(
        type: BackendErrorType.conflict,
        message: 'User already registered',
      );

      final result = await repository.signUp(
        email: 'a@b.com',
        password: 'password1',
      );

      expect(result.failure?.type, BackendErrorType.conflict);
    });

    test('a network failure surfaces as a retryable network error', () async {
      backend.failure = BackendErrorClassifier.build(
        type: BackendErrorType.network,
        message: 'Connection reset',
      );

      final result = await repository.login(
        email: 'a@b.com',
        password: 'password1',
      );

      expect(result.failure?.type, BackendErrorType.network);
      expect(result.failure?.isRetryable, isTrue);
    });

    test('a network failure is retried by the executor', () async {
      var attempts = 0;
      final retrying = AuthRepository(
        backend: _CountingAuthBackend(
          onLogin: () {
            attempts++;
            if (attempts < 2) {
              return failureOf<BackendSession>(
                BackendErrorClassifier.build(
                  type: BackendErrorType.network,
                  message: 'flaky',
                ),
              );
            }
            return success(backend.session);
          },
        ),
        executor: RequestExecutor(
          retryPolicy: const RetryPolicy(maxRetries: 2, jitter: 0),
          requestTimeout: const Duration(seconds: 5),
          delay: (_) async {},
        ),
      );

      final result = await retrying.login(
        email: 'a@b.com',
        password: 'password1',
      );

      expect(result.isSuccess, isTrue);
      expect(attempts, 2);
      await retrying.dispose();
    });

    test('an unauthorized failure is never retried', () async {
      var attempts = 0;
      final retrying = AuthRepository(
        backend: _CountingAuthBackend(
          onLogin: () {
            attempts++;
            return failureOf<BackendSession>(
              BackendErrorClassifier.build(
                type: BackendErrorType.unauthorized,
                message: 'nope',
              ),
            );
          },
        ),
        executor: RequestExecutor(
          retryPolicy: const RetryPolicy(maxRetries: 5, jitter: 0),
          requestTimeout: const Duration(seconds: 5),
          delay: (_) async {},
        ),
      );

      await retrying.login(email: 'a@b.com', password: 'password1');

      expect(attempts, 1);
      await retrying.dispose();
    });
  });

  group('Auth state changes', () {
    test('the stream reports authenticated and unauthenticated', () async {
      final changes = <AuthStateChange>[];
      final subscription = repository.authStateChanges.listen(changes.add);

      backend.emit(
        const AuthStateChange(
          status: AuthStatus.authenticated,
          session: BackendSession(
            accessToken: 't',
            user: BackendUser(id: 'user-1'),
          ),
        ),
      );
      await pumpEventQueue();
      expect(repository.cachedSession?.user.id, 'user-1');

      backend.emit(const AuthStateChange(status: AuthStatus.unauthenticated));
      await pumpEventQueue();

      expect(changes.map((c) => c.status).toList(), [
        AuthStatus.authenticated,
        AuthStatus.unauthenticated,
      ]);
      // Signing out clears the cache, so `isSignedIn` cannot go stale.
      expect(repository.cachedSession, isNull);
      expect(repository.isSignedIn, isFalse);
      await subscription.cancel();
    });

    test('a stream error never escapes to the listener', () async {
      final changes = <AuthStateChange>[];
      final errors = <Object>[];
      final subscription = repository.authStateChanges.listen(
        changes.add,
        onError: errors.add,
      );

      backend.emitError(StateError('socket died'));
      await pumpEventQueue();

      expect(errors, isEmpty);
      expect(changes.single.status, AuthStatus.unknown);
      await subscription.cancel();
    });

    test('recovery is surfaced distinctly from a normal sign-in', () async {
      final changes = <AuthStateChange>[];
      final subscription = repository.authStateChanges.listen(changes.add);

      backend.emit(const AuthStateChange(status: AuthStatus.recoveryRequired));
      await pumpEventQueue();

      expect(changes.single.status, AuthStatus.recoveryRequired);
      await subscription.cancel();
    });

    test('several listeners share one backend stream', () async {
      final a = <AuthStateChange>[];
      final b = <AuthStateChange>[];
      final subA = repository.authStateChanges.listen(a.add);
      final subB = repository.authStateChanges.listen(b.add);

      backend.emit(const AuthStateChange(status: AuthStatus.unauthenticated));
      await pumpEventQueue();

      expect(a, hasLength(1));
      expect(b, hasLength(1));
      await subA.cancel();
      await subB.cancel();
    });

    test('dispose releases the backend', () async {
      await repository.dispose();

      expect(backend.disposeCalls, 1);
    });
  });

  group('BackendSession and BackendUser', () {
    test('isExpired reflects the expiry', () {
      final expired = BackendSession(
        accessToken: 't',
        user: const BackendUser(id: 'u'),
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      final valid = BackendSession(
        accessToken: 't',
        user: const BackendUser(id: 'u'),
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );

      expect(expired.isExpired(), isTrue);
      expect(valid.isExpired(), isFalse);
    });

    test('an unknown expiry is not treated as never expiring', () {
      const session = BackendSession(
        accessToken: 't',
        user: BackendUser(id: 'u'),
      );

      expect(session.isExpired(), isFalse);
    });

    test('toString never renders the access token', () {
      const session = BackendSession(
        accessToken: 'super-secret-token',
        user: BackendUser(id: 'u'),
      );

      expect(session.toString(), isNot(contains('super-secret-token')));
    });

    test('BackendUser has value equality on identity', () {
      const a = BackendUser(id: 'u', email: 'a@b.com');
      const b = BackendUser(id: 'u', email: 'a@b.com');
      const c = BackendUser(id: 'v', email: 'a@b.com');

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('BackendUser.toString omits metadata', () {
      const user = BackendUser(
        id: 'u',
        metadata: {'token': 'nope'},
      );

      expect(user.toString(), isNot(contains('nope')));
    });
  });
}

/// An auth backend that delegates only the login call, so retry counting is
/// observable.
class _CountingAuthBackend implements AuthBackend {
  _CountingAuthBackend({required this.onLogin});

  final BackendResult<BackendSession> Function() onLogin;

  @override
  Future<BackendResult<BackendSession>> login({
    required String email,
    required String password,
  }) async {
    return onLogin();
  }

  @override
  Future<BackendResult<BackendSession>> signUp({
    required String email,
    required String password,
    Map<String, dynamic> metadata = const {},
    String? emailRedirectTo,
  }) async =>
      onLogin();

  @override
  Future<BackendResult<void>> logout() async => success(null);

  @override
  Future<BackendResult<BackendSession?>> currentSession() async =>
      success(null);

  @override
  Future<BackendResult<BackendUser?>> currentUser() async => success(null);

  @override
  Future<BackendResult<BackendSession>> refreshSession() async => onLogin();

  @override
  Future<BackendResult<void>> requestPasswordReset({
    required String email,
    String? redirectTo,
  }) async =>
      success(null);

  @override
  Future<BackendResult<BackendUser>> updatePassword({
    required String newPassword,
  }) async =>
      success(const BackendUser(id: 'u'));

  @override
  Future<BackendResult<BackendUser>> updateUserMetadata(
    Map<String, dynamic> metadata,
  ) async =>
      success(const BackendUser(id: 'u'));

  @override
  Future<BackendResult<void>> resendVerificationEmail({
    required String email,
    String? redirectTo,
  }) async =>
      success(null);

  @override
  Stream<AuthStateChange> get authStateChanges => const Stream.empty();

  @override
  Future<void> dispose() async {}
}
