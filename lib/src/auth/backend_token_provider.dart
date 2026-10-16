import '../errors/backend_error_mapper.dart';
import '../errors/backend_error_type.dart';
import '../result/backend_result.dart';
import '../retry/cancellation_token.dart';
import 'auth_repository.dart';

/// Resolves the current bearer token without exposing provider session details
/// to application data sources.
abstract interface class BackendTokenProvider {
  /// Returns the active access token, or `null` for an anonymous request.
  ///
  /// When [requireAuthenticated] is true, an absent or unrefreshable session
  /// becomes an `unauthorized` failure.
  Future<BackendResult<String?>> accessToken({
    bool requireAuthenticated = false,
    CancellationToken? cancellationToken,
  });
}

/// Token provider backed by the SDK authentication repository.
class AuthRepositoryTokenProvider implements BackendTokenProvider {
  /// The SDK authentication facade.
  final AuthRepository auth;

  /// Creates the provider.
  const AuthRepositoryTokenProvider(this.auth);

  @override
  Future<BackendResult<String?>> accessToken({
    bool requireAuthenticated = false,
    CancellationToken? cancellationToken,
  }) async {
    final current = await auth.currentSession(
      cancellationToken: cancellationToken,
    );
    final currentFailure = current.failure;
    if (currentFailure != null) return failureOf<String?>(currentFailure);

    var session = current.data;
    if (session?.isExpired() ?? false) {
      final refreshed = await auth.refreshSession(
        cancellationToken: cancellationToken,
      );
      final refreshFailure = refreshed.failure;
      if (refreshFailure != null) return failureOf<String?>(refreshFailure);
      session = refreshed.data;
    }

    final token = session?.accessToken.trim();
    if (token != null && token.isNotEmpty) {
      return BackendSuccess<String?>(token);
    }
    if (!requireAuthenticated) return const BackendSuccess<String?>(null);
    return failureOf<String?>(
      BackendErrorClassifier.build(
        type: BackendErrorType.unauthorized,
        message: 'Authentication is required for this operation.',
      ),
    );
  }
}
