import '../errors/backend_error_type.dart';
import 'cancellation_token.dart';

/// Provider-neutral metadata for one SDK request.
///
/// It gives retries, timeouts, cancellation and diagnostics one stable input
/// regardless of whether the underlying provider is Supabase, Firebase or REST.
class BackendRequest {
  /// A stable non-sensitive operation label, such as `news.list`.
  final String operation;

  /// The error type used for unclassified transport exceptions.
  final BackendErrorType fallbackErrorType;

  /// Cancels the request before a new attempt starts.
  final CancellationToken? cancellationToken;

  /// Creates request metadata.
  const BackendRequest({
    required this.operation,
    this.fallbackErrorType = BackendErrorType.unknown,
    this.cancellationToken,
  });
}
