import 'dart:async';

import 'package:supabase/supabase.dart'
    show AuthState, OtpType, SupabaseClient, UserAttributes;

import '../../auth/auth_session.dart';
import '../../auth/auth_state.dart';
import '../../auth/auth_user.dart';
import '../../contracts/auth_backend.dart';
import '../../errors/backend_error_type.dart';
import '../../errors/backend_failure.dart';
import '../../result/backend_result.dart';
import 'supabase_error_mapper.dart';
import 'supabase_mappers.dart';

/// Adapts Supabase Auth to the `AuthBackend` contract.
///
/// Every Supabase exception is converted by [SupabaseErrorMapper] and rethrown
/// as a `BackendFailure`; the repository above re-wraps it into a
/// `BackendResult`. No `User`, `Session` or `AuthException` escapes this class.
class SupabaseAuthBackend implements AuthBackend {
  final SupabaseClient _client;
  final SupabaseErrorMapper _errorMapper;

  Stream<AuthStateChange>? _stateChanges;
  StreamController<AuthStateChange>? _stateController;

  /// Creates the adapter over [client].
  SupabaseAuthBackend({
    required SupabaseClient client,
    SupabaseErrorMapper errorMapper = const SupabaseErrorMapper(),
  })  : _client = client,
        _errorMapper = errorMapper;

  @override
  Future<BackendResult<BackendSession>> signUp({
    required String email,
    required String password,
    Map<String, dynamic> metadata = const {},
    String? emailRedirectTo,
  }) {
    return _guard('signUp', BackendErrorType.unauthorized, () async {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: emailRedirectTo,
        data: metadata.isEmpty ? null : metadata,
      );
      final session = response.session;
      if (session == null) {
        // Sign-up succeeded but produced no session, which is what happens when
        // the project requires email confirmation. The repository surfaces the
        // unverified user rather than failing.
        final user = response.user;
        if (user == null) {
          throw _errorMapper.map(
            StateError('Sign-up returned neither a session nor a user.'),
            StackTrace.current,
            fallbackType: BackendErrorType.unknown,
          );
        }
        return BackendSession(
          accessToken: '',
          user: SupabaseMappers.toUser(user),
        );
      }
      return SupabaseMappers.toSession(session);
    });
  }

  @override
  Future<BackendResult<BackendSession>> login({
    required String email,
    required String password,
  }) {
    return _guard('login', BackendErrorType.unauthorized, () async {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final session = response.session;
      if (session == null) {
        throw _errorMapper.map(
          StateError('Sign-in returned no session.'),
          StackTrace.current,
          fallbackType: BackendErrorType.unauthorized,
        );
      }
      return SupabaseMappers.toSession(session);
    });
  }

  @override
  Future<BackendResult<void>> logout() {
    return _guard<void>('logout', BackendErrorType.unauthorized, () async {
      await _client.auth.signOut();
    });
  }

  @override
  Future<BackendResult<BackendSession?>> currentSession() {
    return _guard<BackendSession?>(
      'currentSession',
      BackendErrorType.unauthorized,
      () async {
        final session = _client.auth.currentSession;
        return session == null ? null : SupabaseMappers.toSession(session);
      },
    );
  }

  @override
  Future<BackendResult<BackendUser?>> currentUser() {
    return _guard<BackendUser?>(
      'currentUser',
      BackendErrorType.unauthorized,
      () async {
        final user = _client.auth.currentUser;
        return user == null ? null : SupabaseMappers.toUser(user);
      },
    );
  }

  @override
  Future<BackendResult<BackendSession>> refreshSession() {
    return _guard<BackendSession>(
      'refreshSession',
      BackendErrorType.unauthorized,
      () async {
        final response = await _client.auth.refreshSession();
        final session = response.session;
        if (session == null) {
          throw _errorMapper.map(
            StateError('Refreshing the session produced no session.'),
            StackTrace.current,
            fallbackType: BackendErrorType.unauthorized,
          );
        }
        return SupabaseMappers.toSession(session);
      },
    );
  }

  @override
  Future<BackendResult<void>> requestPasswordReset({
    required String email,
    String? redirectTo,
  }) {
    return _guard<void>(
      'requestPasswordReset',
      BackendErrorType.unauthorized,
      () async {
        await _client.auth.resetPasswordForEmail(
          email,
          redirectTo: redirectTo,
        );
      },
    );
  }

  @override
  Future<BackendResult<BackendUser>> updatePassword({
    required String newPassword,
  }) {
    return _guard<BackendUser>(
      'updatePassword',
      BackendErrorType.unauthorized,
      () async {
        final response = await _client.auth.updateUser(
          UserAttributes(password: newPassword),
        );
        final user = response.user;
        if (user == null) {
          throw _errorMapper.map(
            StateError('Updating the password returned no user.'),
            StackTrace.current,
            fallbackType: BackendErrorType.unauthorized,
          );
        }
        return SupabaseMappers.toUser(user);
      },
    );
  }

  @override
  Future<BackendResult<BackendUser>> updateUserMetadata(
    Map<String, dynamic> metadata,
  ) {
    return _guard<BackendUser>(
      'updateUserMetadata',
      BackendErrorType.unauthorized,
      () async {
        final response = await _client.auth.updateUser(
          UserAttributes(data: metadata),
        );
        final user = response.user;
        if (user == null) {
          throw _errorMapper.map(
            StateError('Updating the user returned no user.'),
            StackTrace.current,
            fallbackType: BackendErrorType.unauthorized,
          );
        }
        return SupabaseMappers.toUser(user);
      },
    );
  }

  @override
  Future<BackendResult<void>> resendVerificationEmail({
    required String email,
    String? redirectTo,
  }) {
    return _guard<void>(
      'resendVerificationEmail',
      BackendErrorType.unauthorized,
      () async {
        await _client.auth.resend(
          type: OtpType.signup,
          email: email,
          emailRedirectTo: redirectTo,
        );
      },
    );
  }

  @override
  Stream<AuthStateChange> get authStateChanges {
    return _stateChanges ??= _createStateStream();
  }

  Stream<AuthStateChange> _createStateStream() {
    late final StreamController<AuthStateChange> controller;
    StreamSubscription<AuthState>? subscription;

    controller = StreamController<AuthStateChange>.broadcast(
      onListen: () {
        subscription = _client.auth.onAuthStateChange.listen(
          (state) {
            if (controller.isClosed) return;
            controller.add(SupabaseMappers.toAuthStateChange(state));
          },
          onError: (Object error, StackTrace stackTrace) {
            // A transport failure must not reach listeners as a stream error.
            // The repository's own onError handler records the failure and
            // reports `AuthStatus.unknown` instead.
            if (controller.isClosed) return;
            controller.addError(_errorMapper.map(
              error,
              stackTrace,
              fallbackType: BackendErrorType.unauthorized,
            ));
          },
          cancelOnError: false,
        );
      },
      onCancel: () async {
        await subscription?.cancel();
        subscription = null;
      },
    );

    _stateController = controller;
    return controller.stream;
  }

  @override
  Future<void> dispose() async {
    final controller = _stateController;
    _stateController = null;
    _stateChanges = null;
    await controller?.close();
  }

  Future<BackendResult<T>> _guard<T>(
    String operation,
    BackendErrorType fallbackType,
    Future<T> Function() action,
  ) async {
    try {
      return BackendSuccess<T>(await action());
    } on BackendFailure catch (failure) {
      return BackendFailureResult<T>(error: failure);
    } catch (error, stackTrace) {
      return BackendFailureResult<T>(
        error: _errorMapper.map(
          error,
          stackTrace,
          fallbackType: fallbackType,
          context: {'operation': 'auth.$operation'},
        ),
      );
    }
  }
}
