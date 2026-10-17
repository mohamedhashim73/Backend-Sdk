import 'package:dio/dio.dart';

import '../errors/backend_error_mapper.dart';
import '../errors/backend_error_type.dart';
import '../errors/backend_failure.dart';

/// Converts Dio transport failures into the SDK's provider-neutral error type.
class ApiErrorMapper {
  const ApiErrorMapper._();

  static BackendFailure fromDio(DioException error, StackTrace stackTrace) {
    final statusCode = error.response?.statusCode;
    final type = switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        BackendErrorType.timeout,
      DioExceptionType.connectionError ||
      DioExceptionType.badCertificate =>
        BackendErrorType.network,
      DioExceptionType.cancel => BackendErrorType.cancelled,
      DioExceptionType.badResponse => BackendErrorClassifier.resolve(
          statusCode: statusCode,
          fallbackType: BackendErrorType.server,
        ),
      DioExceptionType.unknown => BackendErrorClassifier.resolve(
          statusCode: statusCode,
          fallbackType: BackendErrorType.unknown,
        ),
      _ => BackendErrorType.timeout,
    };

    return BackendErrorClassifier.build(
      type: type,
      message: _message(error.response?.data, error.message),
      statusCode: statusCode,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static String _message(Object? data, String? fallback) {
    if (data is Map) {
      final map = Map<Object?, Object?>.from(data);
      for (final key in const ['message', 'error', 'detail', 'description']) {
        final value = map[key];
        if (value is String && value.trim().isNotEmpty) return value;
      }
      final errors = map['errors'];
      if (errors is List && errors.isNotEmpty && errors.first is Map) {
        return _message(errors.first, fallback);
      }
    }
    return fallback?.trim().isNotEmpty == true
        ? fallback!
        : 'The HTTP request failed.';
  }
}
