import '../auth/backend_token_provider.dart';
import '../contracts/data_backend.dart';
import '../core/backend_routing.dart';
import '../errors/backend_error_mapper.dart';
import '../errors/backend_error_type.dart';
import '../result/backend_result.dart';
import '../retry/backend_request.dart';
import '../retry/cancellation_token.dart';
import '../retry/request_executor.dart';
import 'backend_auth_scope.dart';
import 'backend_operation.dart';

/// Executes typed application operations through the configured provider.
///
/// A data source depends on this client instead of knowing an RPC/function/path,
/// token, provider client, retry policy or raw response decoder.
class BackendOperationClient {
  final DataBackend _backend;
  final BackendRouting _routing;
  final BackendTokenProvider _tokens;
  final RequestExecutor _executor;

  /// Creates an operation client.
  const BackendOperationClient({
    required DataBackend backend,
    required BackendRouting routing,
    required BackendTokenProvider tokens,
    required RequestExecutor executor,
  })  : _backend = backend,
        _routing = routing,
        _tokens = tokens,
        _executor = executor;

  /// Executes [operation] using its logical key and typed request/response.
  Future<BackendResult<TResponse>>
      execute<TRequest extends Object?, TResponse extends Object?>(
    BackendOperation<TRequest, TResponse> operation,
    TRequest request, {
    CancellationToken? cancellationToken,
  }) async {
    final target = _routing.operationTarget(operation.key);
    if (target == null) {
      return failureOf<TResponse>(
        BackendErrorClassifier.build(
          type: BackendErrorType.configuration,
          message: 'No provider route is configured for "${operation.key}".',
        ),
      );
    }

    if (operation.authScope == BackendAuthScope.required) {
      final token = await _tokens.accessToken(
        requireAuthenticated: true,
        cancellationToken: cancellationToken,
      );
      final failure = token.failure;
      if (failure != null) return failureOf<TResponse>(failure);
    }

    return _executor.executeResult<TResponse>(
      request: BackendRequest(
        operation: operation.key,
        fallbackErrorType: BackendErrorType.database,
        cancellationToken: cancellationToken,
      ),
      action: () {
        final functionBackend = _backend;
        if (functionBackend is BackendFunctionBackend) {
          return (functionBackend as BackendFunctionBackend)
              .executeFunction<TResponse>(
            target: target,
            parameters: operation.encode(request),
            decoder: operation.decode,
          );
        }
        return _backend.callRpc<TResponse>(
          functionName: target,
          parameters: operation.encode(request),
          decoder: operation.decode,
        );
      },
    );
  }
}
