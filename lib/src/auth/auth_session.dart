import 'auth_user.dart';

/// A provider-agnostic authenticated session.
///
/// The access token is exposed so applications that talk to their own custom
/// backend endpoints can present it, but it is never logged by this package and
/// should never be written to logs, analytics or crash reports.
class BackendSession {
  /// The short-lived bearer token for API calls.
  final String accessToken;

  /// When [accessToken] stops being valid, when the provider reports it.
  final DateTime? expiresAt;

  /// The authenticated account.
  final BackendUser user;

  /// Creates a backend session.
  const BackendSession({
    required this.accessToken,
    required this.user,
    this.expiresAt,
  });

  /// Whether [expiresAt] is in the past.
  ///
  /// Useful for skipping a doomed request. Providers refresh sessions
  /// automatically, so this is a hint rather than a guarantee.
  bool isExpired({DateTime? now}) =>
      expiresAt != null && expiresAt!.isBefore(now ?? DateTime.now());

  @override
  String toString() {
    // The access token is intentionally omitted.
    return 'BackendSession(user: ${user.id}, expiresAt: $expiresAt)';
  }
}
