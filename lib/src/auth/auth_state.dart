import 'auth_session.dart';
import 'auth_user.dart';

/// The authentication status reported by [AuthStateChange].
enum AuthStatus {
  /// The SDK has not yet determined whether a session exists.
  ///
  /// Persisted sessions are restored asynchronously, so a briefly
  /// [AuthStatus.unknown] state at start-up is normal.
  unknown,

  /// No valid session is present.
  unauthenticated,

  /// A valid session is present.
  authenticated,

  /// The user followed a password-recovery link and must set a new password.
  ///
  /// The application should route to a "choose a new password" screen.
  recoveryRequired,
}

/// A single authentication state transition.
///
/// Emitted by `BackendSdk.instance.auth.authStateChanges`. The stream never
/// emits errors: transport problems surface as a transition back to
/// [AuthStatus.unknown] rather than as an unhandled stream exception, so a
/// listener cannot crash the app.
class AuthStateChange {
  /// The new status.
  final AuthStatus status;

  /// The active session, present when [status] is [AuthStatus.authenticated].
  final BackendSession? session;

  /// Creates an authentication state change.
  const AuthStateChange({required this.status, this.session});

  /// The signed-in user, when there is one.
  BackendUser? get user => session?.user;

  /// Whether a valid session is present.
  bool get isAuthenticated => status == AuthStatus.authenticated;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthStateChange &&
          other.status == status &&
          other.session?.accessToken == session?.accessToken;

  @override
  int get hashCode => Object.hash(status, session?.accessToken);

  @override
  String toString() {
    return 'AuthStateChange(status: ${status.name}, '
        'user: ${session?.user.id})';
  }
}
