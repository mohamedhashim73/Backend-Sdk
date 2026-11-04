import 'dart:typed_data';

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

  test('uses the configured locale header name', () async {
    late RequestOptions requestOptions;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requestOptions = options;
            handler.resolve(
              Response<Object?>(
                requestOptions: options,
                statusCode: 200,
                data: null,
              ),
            );
          },
        ),
      );
    final client = ApiClient(
      configuration: const ApiConfiguration(baseUrl: 'https://api.example.com'),
      dio: dio,
      session: ApiSessionConfiguration(
        accessTokenProvider: () => null,
        refreshTokenProvider: () => null,
        localeProvider: () => 'ar',
        localeHeaderName: 'X-Language',
        onTokensUpdated: (_) {},
        onSessionExpired: () {},
        refreshPath: '/auth/refresh-token',
      ),
    );

    await client.send<void>(
      const ApiRequest.get(path: '/public', requiresAuthentication: false),
    );

    expect(requestOptions.headers['X-Language'], 'ar');
    expect(requestOptions.headers.containsKey('X-Locale'), isFalse);
  });

  test('logs every API request when configuration logging is enabled',
      () async {
    final entries = <LogEntry>[];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response<Object?>(
              requestOptions: options,
              statusCode: 200,
              data: <String, Object?>{'ok': true},
            ),
          ),
        ),
      );
    final client = ApiClient(
      configuration: ApiConfiguration(
        baseUrl: 'https://api.example.com',
        isLoggingOn: true,
        logger: CallbackBackendLogger(sink: entries.add),
      ),
      dio: dio,
    );

    await client.get<void>(path: '/news', requiresAuthentication: false);

    expect(entries.map((entry) => entry.message), contains('➡️ API Request'));
    expect(entries.map((entry) => entry.message), contains('✅ API Response'));
    final responseEntry = entries.singleWhere(
      (entry) => entry.message == '✅ API Response',
    );
    expect(responseEntry.context['response'], {'ok': true});
  });

  test('logs failed response bodies without exposing sensitive fields',
      () async {
    final entries = <LogEntry>[];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.reject(
            DioException(
              requestOptions: options,
              response: Response<Object?>(
                requestOptions: options,
                statusCode: 422,
                data: <String, Object?>{
                  'message': 'Validation failed',
                  'access_token': 'secret-access-token',
                  'errors': <String, Object?>{
                    'apple_id': <String>['Apple ID is already used'],
                  },
                },
              ),
              type: DioExceptionType.badResponse,
            ),
          ),
        ),
      );
    final client = ApiClient(
      configuration: ApiConfiguration(
        baseUrl: 'https://api.example.com',
        isLoggingOn: true,
        logger: CallbackBackendLogger(sink: entries.add),
      ),
      dio: dio,
    );

    final result = await client.post<void>(
      path: '/auth/register/complete',
      requiresAuthentication: false,
      body: {'apple_id': 'apple-user-id'},
    );

    expect(result.failure?.statusCode, 422);
    final errorEntry = entries.singleWhere(
      (entry) => entry.message == '❌ API Error',
    );
    expect(errorEntry.context['response'], {
      'message': 'Validation failed',
      'access_token': CallbackBackendLogger.redactedValue,
      'errors': {
        'apple_id': ['Apple ID is already used'],
      },
    });
  });

  test('logs JSON and multipart payload shapes without sensitive values',
      () async {
    final entries = <LogEntry>[];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response<Object?>(
              requestOptions: options,
              statusCode: 200,
              data: null,
            ),
          ),
        ),
      );
    final client = ApiClient(
      configuration: ApiConfiguration(
        baseUrl: 'https://api.example.com',
        isLoggingOn: true,
        logger: CallbackBackendLogger(sink: entries.add),
      ),
      dio: dio,
    );

    await client.post<void>(
      path: '/profile',
      requiresAuthentication: false,
      body: {'name': 'Sara', 'fcmToken': 'secret'},
    );
    await client.post<void>(
      path: '/profile/image',
      requiresAuthentication: false,
      multipart: ApiMultipartBody(
        fields: {'fullName': 'Sara', 'tempToken': 'secret'},
        files: [
          ApiMultipartFile(
            field: 'image',
            filename: 'avatar.jpg',
            bytes: Uint8List(4),
          ),
        ],
      ),
    );

    final requestBodies = entries
        .where((entry) => entry.message == '➡️ API Request')
        .map((entry) => entry.context['body'])
        .toList();
    expect(requestBodies[0], {
      'name': 'Sara',
      'fcmToken': CallbackBackendLogger.redactedValue,
    });
    expect(requestBodies[1], {
      'type': 'multipart',
      'fields': {
        'fullName': 'Sara',
        'tempToken': CallbackBackendLogger.redactedValue,
      },
      'files': [
        {
          'field': 'image',
          'filename': 'avatar.jpg',
          'contentType': 'image/jpeg',
          'bytes': 4,
        },
      ],
    });
  });
}
