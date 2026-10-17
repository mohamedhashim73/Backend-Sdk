import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'api_method.dart';

/// A provider-neutral HTTP request.
///
/// Application data sources own paths, payloads and response decoders. The
/// SDK owns transport, authentication headers, token refresh, logging, retry
/// and failure mapping.
class ApiRequest {
  final ApiMethod method;
  final String path;
  final Object? body;
  final Map<String, Object?> queryParameters;
  final Map<String, String> headers;
  final bool requiresAuthentication;
  final bool allowSessionRefresh;
  final bool enableLogging;
  final ApiMultipartBody? multipart;

  const ApiRequest({
    required this.method,
    required this.path,
    this.body,
    this.queryParameters = const {},
    this.headers = const {},
    this.requiresAuthentication = true,
    this.allowSessionRefresh = true,
    this.enableLogging = false,
    this.multipart,
  }) : assert(body == null || multipart == null,
            'A request cannot contain both a body and multipart data.');

  const ApiRequest.get({
    required String path,
    Map<String, Object?> queryParameters = const {},
    Map<String, String> headers = const {},
    bool requiresAuthentication = true,
    bool allowSessionRefresh = true,
    bool enableLogging = false,
  }) : this(
          method: ApiMethod.get,
          path: path,
          queryParameters: queryParameters,
          headers: headers,
          requiresAuthentication: requiresAuthentication,
          allowSessionRefresh: allowSessionRefresh,
          enableLogging: enableLogging,
        );

  const ApiRequest.post({
    required String path,
    Object? body,
    Map<String, Object?> queryParameters = const {},
    Map<String, String> headers = const {},
    bool requiresAuthentication = true,
    bool allowSessionRefresh = true,
    bool enableLogging = false,
    ApiMultipartBody? multipart,
  }) : this(
          method: ApiMethod.post,
          path: path,
          body: body,
          queryParameters: queryParameters,
          headers: headers,
          requiresAuthentication: requiresAuthentication,
          allowSessionRefresh: allowSessionRefresh,
          enableLogging: enableLogging,
          multipart: multipart,
        );

  /// Creates an authenticated or public PUT request.
  const ApiRequest.put({
    required String path,
    Object? body,
    Map<String, Object?> queryParameters = const {},
    Map<String, String> headers = const {},
    bool requiresAuthentication = true,
    bool allowSessionRefresh = true,
    bool enableLogging = false,
    ApiMultipartBody? multipart,
  }) : this(
          method: ApiMethod.put,
          path: path,
          body: body,
          queryParameters: queryParameters,
          headers: headers,
          requiresAuthentication: requiresAuthentication,
          allowSessionRefresh: allowSessionRefresh,
          enableLogging: enableLogging,
          multipart: multipart,
        );

  /// Creates an authenticated or public PATCH request.
  const ApiRequest.patch({
    required String path,
    Object? body,
    Map<String, Object?> queryParameters = const {},
    Map<String, String> headers = const {},
    bool requiresAuthentication = true,
    bool allowSessionRefresh = true,
    bool enableLogging = false,
    ApiMultipartBody? multipart,
  }) : this(
          method: ApiMethod.patch,
          path: path,
          body: body,
          queryParameters: queryParameters,
          headers: headers,
          requiresAuthentication: requiresAuthentication,
          allowSessionRefresh: allowSessionRefresh,
          enableLogging: enableLogging,
          multipart: multipart,
        );

  /// Creates an authenticated or public DELETE request.
  const ApiRequest.delete({
    required String path,
    Object? body,
    Map<String, Object?> queryParameters = const {},
    Map<String, String> headers = const {},
    bool requiresAuthentication = true,
    bool allowSessionRefresh = true,
    bool enableLogging = false,
  }) : this(
          method: ApiMethod.delete,
          path: path,
          body: body,
          queryParameters: queryParameters,
          headers: headers,
          requiresAuthentication: requiresAuthentication,
          allowSessionRefresh: allowSessionRefresh,
          enableLogging: enableLogging,
        );
}

/// Multipart request payload that works on mobile, web and Dart without
/// exposing `dart:io` file handles through the SDK API.
class ApiMultipartBody {
  final Map<String, Object?> fields;
  final List<ApiMultipartFile> files;

  const ApiMultipartBody({this.fields = const {}, this.files = const []});

  FormData toFormData() {
    final formData = FormData();
    for (final entry in fields.entries) {
      final value = entry.value;
      if (value == null) continue;
      if (value is Iterable) {
        for (final item in value) {
          if (item != null) {
            formData.fields.add(MapEntry(entry.key, item.toString()));
          }
        }
      } else {
        formData.fields.add(MapEntry(entry.key, value.toString()));
      }
    }
    for (final file in files) {
      formData.files.add(MapEntry(file.field, file.toMultipartFile()));
    }
    return formData;
  }
}

/// In-memory file data used by [ApiMultipartBody].
class ApiMultipartFile {
  final String field;
  final Uint8List bytes;
  final String filename;
  final String? contentType;

  const ApiMultipartFile({
    required this.field,
    required this.bytes,
    required this.filename,
    this.contentType,
  });

  MultipartFile toMultipartFile() => MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType:
            contentType == null ? null : DioMediaType.parse(contentType!),
      );
}
