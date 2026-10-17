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
  final Map<String, String> defaultHeaders;

  const ApiConfiguration({
    required this.baseUrl,
    this.connectTimeout = const Duration(seconds: 30),
    this.sendTimeout = const Duration(seconds: 30),
    this.receiveTimeout = const Duration(seconds: 30),
    this.retryPolicy = RetryPolicy.noRetries,
    this.logger = const NoopBackendLogger(),
    this.isLoggingOn = false,
    this.defaultHeaders = const {},
  });
}
