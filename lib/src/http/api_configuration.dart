import '../core/backend_logger.dart';
import '../errors/backend_failure.dart';
import '../retry/retry_policy.dart';
import 'api_error_language.dart';

/// Transport configuration for the SDK REST client.
class ApiConfiguration {
  final String baseUrl;
  final Duration connectTimeout;
  final Duration sendTimeout;
  final Duration receiveTimeout;
  final RetryPolicy retryPolicy;
  final BackendLogger logger;
  final bool isLoggingOn;

  /// Whether response log entries and response bodies on error logs are
  /// emitted.
  ///
  /// This is opt-in even when [isLoggingOn] is enabled because response bodies
  /// may contain more application data than request/error metadata. It
  /// defaults to `false`.
  final bool isResponseLoggingOn;

  /// Language used for the user-facing [BackendFailure.safeMessage] returned
  /// by the REST client.
  ///
  /// Defaults to English. Technical failure details remain unchanged.
  final ApiErrorLanguage errorLanguage;

  /// Whether sensitive values are redacted before log entries are emitted.
  ///
  /// Keep this enabled outside local diagnostics. It defaults to `true` so
  /// enabling request logging cannot expose credentials by accident. When set
  /// to `false`, diagnostic values are emitted in full.
  final bool redactSensitiveLogs;
  final Map<String, String> defaultHeaders;

  const ApiConfiguration({
    required this.baseUrl,
    this.connectTimeout = const Duration(seconds: 30),
    this.sendTimeout = const Duration(seconds: 30),
    this.receiveTimeout = const Duration(seconds: 30),
    this.retryPolicy = RetryPolicy.noRetries,
    this.logger = const NoopBackendLogger(),
    this.isLoggingOn = false,
    this.isResponseLoggingOn = false,
    this.errorLanguage = ApiErrorLanguage.en,
    this.redactSensitiveLogs = true,
    this.defaultHeaders = const {},
  });
}
