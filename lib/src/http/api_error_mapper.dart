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

    final message = _message(error.response?.data, error.message);
    return BackendErrorClassifier.build(
      type: type,
      message: message,
      // Validation messages describe the field the caller can correct. Unlike
      // authentication/server details, they are safe and useful to show.
      userMessage: type == BackendErrorType.validation ? message : null,
      statusCode: statusCode,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static String _message(Object? data, String? fallback) {
    if (data is Map) {
      final map = Map<Object?, Object?>.from(data);
      final validationMessage = _firstMessage(map['errors']);
      if (validationMessage != null) return validationMessage;
      for (final key in const ['message', 'error', 'detail', 'description']) {
        final message = _firstMessage(map[key]);
        if (message != null) return message;
      }
    }
    return fallback?.trim().isNotEmpty == true
        ? fallback!
        : 'The HTTP request failed.';
  }

  static String? _firstMessage(Object? value) {
    if (value is String && value.trim().isNotEmpty) return value;
    if (value is Iterable) {
      for (final item in value) {
        final message = _firstMessage(item);
        if (message != null) return message;
      }
      return null;
    }
    if (value is Map) {
      final map = Map<Object?, Object?>.from(value);
      for (final key in const ['message', 'error', 'detail', 'description']) {
        final message = _firstMessage(map[key]);
        if (message != null) return message;
      }
      for (final nested in map.values) {
        final message = _firstMessage(nested);
        if (message != null) return message;
      }
    }
    return null;
  }
}
