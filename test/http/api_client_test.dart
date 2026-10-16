import 'package:backend_sdk/backend_sdk.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes a Dio response into the provider-neutral result', () async {
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response<Object?>(
              requestOptions: options,
              statusCode: 200,
              data: <String, Object?>{'id': 'news-1'},
            ),
          ),
        ),
      );
    final client = ApiClient(
      configuration: const ApiConfiguration(baseUrl: 'https://api.example.com'),
      dio: dio,
    );

    final result = await client.send<String>(
      const ApiRequest.get(path: '/news', requiresAuthentication: false),
      decode: (body) => (body as Map<Object?, Object?>)['id']! as String,
    );

    expect(result.data?.data, 'news-1');
    expect(result.data?.statusCode, 200);
    expect(result.failure, isNull);
  });
}
