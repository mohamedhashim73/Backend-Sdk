import 'dart:async';

import '../contracts/auth_backend.dart';
import '../core/backend_logger.dart';
import '../errors/backend_error_type.dart';
import '../result/backend_result.dart';
import '../retry/cancellation_token.dart';
import '../retry/request_executor.dart';
import 'auth_session.dart';
import 'auth_state.dart';
import 'auth_user.dart';
import 'auth_validator.dart';

/// The complete, provider-agnostic authentication API.
///
/// Every method returns a [BackendResult], so no call throws a vendor
/// exception and no caller writes a `try`/`catch` around a login form.
///
/// ```dart
/// final result = await BackendSdk.instance.auth.login(
///   email: email,
///   password: password,
/// );
/// result.when(
///   success: (session) => navigateHome(session.user),
///   failure: (failure) => showMessage(failure.safeMessage),
/// );
/// ```
///
/// The implementation contains no backend-specific code: it validates input,
/// delegates to an [AuthBackend], and converts results. This is what allows a
/// REST or Firebase provider to be swapped in without changing any calling
/// code.
class AuthRepository {
  final AuthBackend _backend;
  final RequestExecutor _executor;
  final BackendLogger _logger;

  BackendSession? _session;

  Stream<AuthStateChange>? _stateChanges;
  StreamController<AuthStateChange>? _stateController;

  /// Creates an authentication repository over [backend].
  AuthRepository({
    required AuthBackend backend,
    required RequestExecutor executor,
    BackendLogger logger = const NoopBackendLogger(),
  })  : _backend = backend,
        _executor = executor,
        _logger = logger;

  /// Whether a session is currently held.
  ///
  /// Reflects the last observed state. Use [currentSession] when the answer must
  /// reflect a freshly restored persisted session.
  bool get isSignedIn => _session != null;

  /// The last observed session, without contacting the provider.
  BackendSession? get cachedSession => _session;

  /// Authentication state transitions.
  ///
  /// The stream is lazily created, broadcast, and never emits errors. Cancel the
  /// subscription when it is no longer needed; the underlying provider listener
  /// is released by [dispose].
  Stream<AuthStateChange> get authStateChanges {
    return _stateChanges ??= _createStateStream();
  }

  Stream<AuthStateChange> _createStateStream() {
    late final StreamController<AuthStateChange> controller;
    StreamSubscription<AuthStateChange>? subscription;

    final created = StreamController<AuthStateChange>.broadcast(
      onListen: () {
        subscription = _backend.authStateChanges.listen(
          (change) {
            if (change.status == AuthStatus.authenticated ||
                change.status == AuthStatus.unauthenticated) {
              _session = change.session;
            }
            if (!controller.isClosed) {
              controller.add(change);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            // Realtime/auth transports can fail. Surface it as a state
            // transition instead of an unhandled stream error so a listener can
            // never crash the app.
            _logger.error(
              'Auth state stream error.',
              cause: error,
              stackTrace: stackTrace,
            );
            if (!controller.isClosed) {
              controller.add(const AuthStateChange(status: AuthStatus.unknown));
            }
          },
          cancelOnError: false,
        );
      },
      onCancel: () async {
        await subscription?.cancel();
        subscription = null;
      },
    );
    _stateController = created;
    controller = created;

    return controller.stream;
  }

  /// Creates an account with an email and password.
  ///
  /// Returns the new session on success. When the backend requires email
  /// confirmation the session is returned with an unverified email; check
  /// [BackendUser.email] and prompt for verification rather than treating the
  /// result as a failure.
  Future<BackendResult<BackendSession>> signUp({
    required String email,
    required String password,
    Map<String, dynamic> metadata = const {},
    String? emailRedirectTo,
    CancellationToken? cancellationToken,
  }) async {
    final invalid = AuthValidator.validateCredentials(
          email: email,
          password: password,
        ) ??
        AuthValidator.validateRedirectTo(emailRedirectTo) ??
        (metadata.isEmpty ? null : AuthValidator.validateMetadata(metadata));
    if (invalid != null) {
      return failureOf<BackendSession>(invalid);
    }

    final result = await _executor.run<BackendSession>(
      operation: 'auth.signUp',
      fallbackErrorType: BackendErrorType.unauthorized,
      cancellationToken: cancellationToken,
      action: () async => unwrap(
        await _backend.signUp(
          email: email.trim(),
          password: password,
          metadata: metadata,
          emailRedirectTo: emailRedirectTo,
        ),
      ),
    );
    return _remember(result);
  }

  /// Authenticates with an email and password.
  ///
  /// Invalid credentials produce a single, non-enumerating message: the
  /// repository never reveals whether an email is registered.
  Future<BackendResult<BackendSession>> login({
    required String email,
    required String password,
    CancellationToken? cancellationToken,
  }) async {
    final invalid = AuthValidator.validateCredentials(
      email: email,
      password: password,
    );
    if (invalid != null) {
      return failureOf<BackendSession>(invalid);
    }

    final result = await _executor.run<BackendSession>(
      operation: 'auth.login',
      fallbackErrorType: BackendErrorType.unauthorized,
      cancellationToken: cancellationToken,
      action: () async => unwrap(
        await _backend.login(email: email.trim(), password: password),
      ),
    );
    return _remember(result);
  }

  /// Ends the current session.
  ///
  /// The local session is cleared even when the provider call fails, so a user
  /// can always escape to a signed-out state. The failure is still returned so
  /// the caller can log it.
  Future<BackendResult<void>> logout(
      {CancellationToken? cancellationToken}) async {
    final result = await _executor.run<void>(
      operation: 'auth.logout',
      fallbackErrorType: BackendErrorType.unauthorized,
      cancellationToken: cancellationToken,
      action: () async => unwrap(await _backend.logout()),
    );
    _session = null;
    return result;
  }

  /// The active user, or `null` when signed out.
  Future<BackendResult<BackendUser?>> currentUser({
    CancellationToken? cancellationToken,
  }) {
    return _executor.run<BackendUser?>(
      operation: 'auth.currentUser',
      fallbackErrorType: BackendErrorType.unauthorized,
      cancellationToken: cancellationToken,
      action: () async => unwrap(await _backend.currentUser()),
    );
  }

  /// The active session, or `null` when signed out.
  Future<BackendResult<BackendSession?>> currentSession({
    CancellationToken? cancellationToken,
  }) async {
    final result = await _executor.run<BackendSession?>(
      operation: 'auth.currentSession',
      fallbackErrorType: BackendErrorType.unauthorized,
      cancellationToken: cancellationToken,
      action: () async => unwrap(await _backend.currentSession()),
    );
    final session = result.data;
    if (session != null) {
      _session = session;
    }
    return result;
  }

  /// Refreshes the access token using the stored refresh token.
  ///
  /// Returns an `unauthorized` failure when the refresh token is missing,
  /// expired or has already been used, which is the signal to send the user
  /// back to the sign-in screen.
  Future<BackendResult<BackendSession>> refreshSession({
    CancellationToken? cancellationToken,
  }) async {
    final result = await _executor.run<BackendSession>(
      operation: 'auth.refreshSession',
      fallbackErrorType: BackendErrorType.unauthorized,
      cancellationToken: cancellationToken,
      action: () async => unwrap(await _backend.refreshSession()),
    );
    return _remember(result);
  }

  /// Sends a password-reset link to [email].
  ///
  /// Always succeeds locally when the input is valid, whether or not the
  /// address exists, so the screen cannot be used to enumerate accounts.
  Future<BackendResult<void>> resetPassword({
    required String email,
    String? redirectTo,
    CancellationToken? cancellationToken,
  }) async {
    final invalid = AuthValidator.validateEmail(email) ??
        AuthValidator.validateRedirectTo(redirectTo);
    if (invalid != null) {
      return failureOf<void>(invalid);
    }

    return _executor.run<void>(
      operation: 'auth.resetPassword',
      fallbackErrorType: BackendErrorType.unauthorized,
      cancellationToken: cancellationToken,
      action: () async => unwrap(
        await _backend.requestPasswordReset(
          email: email.trim(),
          redirectTo: redirectTo,
        ),
      ),
    );
  }

  /// Sets a new password for the signed-in user.
  Future<BackendResult<BackendUser>> updatePassword({
    required String newPassword,
    CancellationToken? cancellationToken,
  }) async {
    final invalid = AuthValidator.validatePassword(newPassword);
    if (invalid != null) {
      return failureOf<BackendUser>(invalid);
    }

    return _executor.run<BackendUser>(
      operation: 'auth.updatePassword',
      fallbackErrorType: BackendErrorType.unauthorized,
      cancellationToken: cancellationToken,
      action: () async => unwrap(
        await _backend.updatePassword(newPassword: newPassword),
      ),
    );
  }

  /// Merges [metadata] into the signed-in user's profile attributes.
  Future<BackendResult<BackendUser>> updateUserMetadata({
    required Map<String, dynamic> metadata,
    CancellationToken? cancellationToken,
  }) async {
    final invalid = AuthValidator.validateMetadata(metadata);
    if (invalid != null) {
      return failureOf<BackendUser>(invalid);
    }

    return _executor.run<BackendUser>(
      operation: 'auth.updateUserMetadata',
      fallbackErrorType: BackendErrorType.unauthorized,
      cancellationToken: cancellationToken,
      action: () async => unwrap(await _backend.updateUserMetadata(metadata)),
    );
  }

  /// Resends the email-confirmation message to [email].
  Future<BackendResult<void>> resendVerificationEmail({
    required String email,
    String? redirectTo,
    CancellationToken? cancellationToken,
  }) async {
    final invalid = AuthValidator.validateEmail(email) ??
        AuthValidator.validateRedirectTo(redirectTo);
    if (invalid != null) {
      return failureOf<void>(invalid);
    }

    return _executor.run<void>(
      operation: 'auth.resendVerificationEmail',
      fallbackErrorType: BackendErrorType.unauthorized,
      cancellationToken: cancellationToken,
      action: () async => unwrap(
        await _backend.resendVerificationEmail(
          email: email.trim(),
          redirectTo: redirectTo,
        ),
      ),
    );
  }

  /// Releases the auth state listener held by this repository.
  Future<void> dispose() async {
    await _stateController?.close();
    _stateController = null;
    _stateChanges = null;
    _session = null;
    await _backend.dispose();
  }

  BackendResult<BackendSession> _remember(
      BackendResult<BackendSession> result) {
    final session = result.data;
    if (session != null) {
      _session = session;
    }
    return result;
  }
}
