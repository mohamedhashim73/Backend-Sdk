import '../auth/auth_session.dart';
import '../auth/auth_state.dart';
import '../auth/auth_user.dart';
import '../result/backend_result.dart';

/// The provider-facing authentication contract.
///
/// A provider implements sign-in, session lifecycle and session-change
/// notifications in its own terms; `AuthRepository` turns them into the typed
/// API the application uses. Nothing above this interface knows which backend
/// is active.
abstract interface class AuthBackend {
  /// Creates a new account and returns the resulting session.
  ///
  /// When the provider requires email confirmation it returns a session with a
  /// user whose email is unverified; `AuthRepository.signUp` surfaces that
  /// state without treating it as a failure.
  Future<BackendResult<BackendSession>> signUp({
    required String email,
    required String password,
    Map<String, dynamic> metadata,
    String? emailRedirectTo,
  });

  /// Authenticates with an email and password.
  Future<BackendResult<BackendSession>> login({
    required String email,
    required String password,
  });

  /// Ends the current session.
  Future<BackendResult<void>> logout();

  /// The active session, or `null` when the user is signed out.
  Future<BackendResult<BackendSession?>> currentSession();

  /// The active user, or `null` when the user is signed out.
  Future<BackendResult<BackendUser?>> currentUser();

  /// Exchanges the refresh token for a new session.
  Future<BackendResult<BackendSession>> refreshSession();

  /// Sends a password-reset message to [email].
  Future<BackendResult<void>> requestPasswordReset({
    required String email,
    String? redirectTo,
  });

  /// Replaces the password of the signed-in user.
  Future<BackendResult<BackendUser>> updatePassword({
    required String newPassword,
  });

  /// Merges [metadata] into the signed-in user's profile attributes.
  Future<BackendResult<BackendUser>> updateUserMetadata(
    Map<String, dynamic> metadata,
  );

  /// Resends the email-confirmation message to [email].
  Future<BackendResult<void>> resendVerificationEmail({
    required String email,
    String? redirectTo,
  });

  /// Authentication state transitions.
  ///
  /// Implementations must not emit errors on this stream.
  Stream<AuthStateChange> get authStateChanges;

  /// Releases provider resources held for auth, including listeners.
  Future<void> dispose();
}
