import 'backend_auth_scope.dart';

/// The typed, application-owned definition of one non-CRUD backend operation.
///
/// Keep domain models and request objects in the application. This SDK type
/// only standardizes how they are encoded, routed and decoded.
class BackendOperation<TRequest extends Object?, TResponse extends Object?> {
  /// Stable logical operation key, for example `home.load`.
  final String key;

  /// Whether an authenticated session is required.
  final BackendAuthScope authScope;

  /// Serializes the typed request to JSON-compatible values.
  final Map<String, Object?> Function(TRequest request) encode;

  /// Converts the provider response to the typed result.
  final TResponse Function(Object? payload) decode;

  /// Creates an application operation.
  const BackendOperation({
    required this.key,
    required this.encode,
    required this.decode,
    this.authScope = BackendAuthScope.optional,
  });
}
