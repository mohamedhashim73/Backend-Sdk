import '../core/backend_logger.dart';
import '../retry/retry_policy.dart';

/// Transport configuration for the SDK REST client.
class ApiConfiguration {
  final String baseUrl;
  final Duration connectTimeout;
  final Duration sendTimeout;
  final Duration receiveTimeout;
  final RetryPolicy retryPolicy;
  final BackendLogger logger;
  final bool isLoggingOn;

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
    this.redactSensitiveLogs = true,
    this.defaultHeaders = const {},
  });
}
