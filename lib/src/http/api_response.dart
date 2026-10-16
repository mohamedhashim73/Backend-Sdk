/// A typed HTTP response returned by the SDK REST client.
class ApiResponse<T> {
  final T data;
  final int statusCode;
  final Map<String, List<String>> headers;

  const ApiResponse({
    required this.data,
    required this.statusCode,
    this.headers = const {},
  });
}

/// Decodes an HTTP response body into the model owned by an application.
typedef ApiDecoder<T> = T Function(Object? body);
