import 'dart:async';

/// Tokens held by an application's persistence layer after an API refresh.
class ApiSessionTokens {
  final String accessToken;
  final String? refreshToken;

  const ApiSessionTokens({required this.accessToken, this.refreshToken});
}

typedef ApiAccessTokenProvider = FutureOr<String?> Function();
typedef ApiRefreshTokenProvider = FutureOr<String?> Function();
typedef ApiLocaleProvider = FutureOr<String?> Function();
typedef ApiTokensUpdatedCallback = FutureOr<void> Function(
    ApiSessionTokens tokens);
typedef ApiSessionExpiredCallback = FutureOr<void> Function();

/// App-owned callbacks used by the SDK REST client for authenticated APIs.
///
/// The SDK never persists credentials itself. It asks the application for the
/// active tokens and tells it when refreshed tokens must be stored or a session
/// must be cleared.
class ApiSessionConfiguration {
  final ApiAccessTokenProvider accessTokenProvider;
  final ApiRefreshTokenProvider refreshTokenProvider;
  final ApiLocaleProvider? localeProvider;
  final String localeHeaderName;
  final ApiTokensUpdatedCallback onTokensUpdated;
  final ApiSessionExpiredCallback onSessionExpired;
  final String refreshPath;
  final Set<int> expiredStatusCodes;

  const ApiSessionConfiguration({
    required this.accessTokenProvider,
    required this.refreshTokenProvider,
    required this.onTokensUpdated,
    required this.onSessionExpired,
    required this.refreshPath,
    this.localeProvider,
    this.localeHeaderName = 'X-Locale',
    this.expiredStatusCodes = const {401, 419},
  }) : assert(localeHeaderName != '');
}

/// Ensures one expiry callback runs for a failed token, even when concurrent
/// requests all receive the same unauthorized response.
class ApiSessionExpiryCoordinator {
  final ApiSessionExpiredCallback _onSessionExpired;
  Future<void>? _inProgress;
  String? _handledToken;
  bool _handledWithoutToken = false;

  ApiSessionExpiryCoordinator(this._onSessionExpired);

  Future<void> handle(String? requestToken) {
    final token = requestToken?.trim();
    if (token != null && token.isNotEmpty) {
      if (_handledToken == token) return Future<void>.value();
    } else if (_handledWithoutToken) {
      return Future<void>.value();
    }

    final active = _inProgress;
    if (active != null) return active;

    if (token != null && token.isNotEmpty) {
      _handledToken = token;
    } else {
      _handledWithoutToken = true;
    }

    final operation = _run(token);
    _inProgress = operation;
    return operation;
  }

  Future<void> _run(String? token) async {
    try {
      await _onSessionExpired();
    } catch (_) {
      if (token == null || token.isEmpty) {
        _handledWithoutToken = false;
      } else {
        _handledToken = null;
      }
      rethrow;
    } finally {
      _inProgress = null;
    }
  }

  void reset() {
    _handledToken = null;
    _handledWithoutToken = false;
    _inProgress = null;
  }
}
