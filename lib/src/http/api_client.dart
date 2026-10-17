import 'dart:async';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';

import '../core/backend_logger.dart';
import '../errors/backend_error_mapper.dart';
import '../errors/backend_error_type.dart';
import '../result/backend_result.dart';
import '../retry/backend_request.dart';
import '../retry/request_executor.dart';
import 'api_configuration.dart';
import 'api_error_mapper.dart';
import 'api_method.dart';
import 'api_request.dart';
import 'api_response.dart';
import 'api_session.dart';

/// Dio-backed REST client that returns only [BackendResult] values.
///
/// It centralizes auth headers, locale headers, serialized token refresh,
/// retry, timeout, redacted logging, response decoding and failure mapping.
/// Apps keep only endpoint paths and their own response decoders.
class ApiClient {
  final Dio _dio;
  final ApiConfiguration configuration;
  final ApiSessionConfiguration? session;
  final BackendLogger _logger;
  final RequestExecutor _executor;
  final ApiSessionExpiryCoordinator? _expiryCoordinator;
  Future<BackendResult<ApiSessionTokens>>? _refreshing;

  ApiClient({
    required this.configuration,
    this.session,
    Dio? dio,
  })  : _dio = dio ?? Dio(),
        _logger = _resolveLogger(configuration),
        _executor = RequestExecutor(
          retryPolicy: configuration.retryPolicy,
          requestTimeout: configuration.receiveTimeout,
          logger: _resolveLogger(configuration),
        ),
        _expiryCoordinator = session == null
            ? null
            : ApiSessionExpiryCoordinator(session.onSessionExpired) {
    _dio.options
      ..baseUrl = configuration.baseUrl
      ..connectTimeout = configuration.connectTimeout
      ..sendTimeout = configuration.sendTimeout
      ..receiveTimeout = configuration.receiveTimeout
      ..contentType = Headers.jsonContentType
      ..headers.addAll(configuration.defaultHeaders);
  }

  /// Sends [request], mapping its body through [decode] when supplied.
  Future<BackendResult<ApiResponse<T>>> send<T>(
    ApiRequest request, {
    ApiDecoder<T>? decode,
  }) {
    return _executor.executeResult(
      request: BackendRequest(
        operation: '${request.method.value} ${request.path}',
        fallbackErrorType: BackendErrorType.network,
      ),
      action: () => _send<T>(request, decode: decode),
    );
  }

  /// Sends a GET request without exposing a transport-specific response type.
  Future<BackendResult<ApiResponse<T>>> get<T>({
    required String path,
    Map<String, Object?> queryParameters = const {},
    Map<String, String> headers = const {},
    bool requiresAuthentication = true,
    bool allowSessionRefresh = true,
    bool enableLogging = false,
    ApiDecoder<T>? decode,
  }) =>
      send<T>(
        ApiRequest.get(
          path: path,
          queryParameters: queryParameters,
          headers: headers,
          requiresAuthentication: requiresAuthentication,
          allowSessionRefresh: allowSessionRefresh,
          enableLogging: enableLogging,
        ),
        decode: decode,
      );

  /// Sends a POST request without exposing a transport-specific response type.
  Future<BackendResult<ApiResponse<T>>> post<T>({
    required String path,
    Object? body,
    Map<String, Object?> queryParameters = const {},
    Map<String, String> headers = const {},
    bool requiresAuthentication = true,
    bool allowSessionRefresh = true,
    bool enableLogging = false,
    ApiMultipartBody? multipart,
    ApiDecoder<T>? decode,
  }) =>
      send<T>(
        ApiRequest.post(
          path: path,
          body: body,
          queryParameters: queryParameters,
          headers: headers,
          requiresAuthentication: requiresAuthentication,
          allowSessionRefresh: allowSessionRefresh,
          enableLogging: enableLogging,
          multipart: multipart,
        ),
        decode: decode,
      );

  /// Sends a PUT request without exposing a transport-specific response type.
  Future<BackendResult<ApiResponse<T>>> put<T>({
    required String path,
    Object? body,
    Map<String, Object?> queryParameters = const {},
    Map<String, String> headers = const {},
    bool requiresAuthentication = true,
    bool allowSessionRefresh = true,
    bool enableLogging = false,
    ApiMultipartBody? multipart,
    ApiDecoder<T>? decode,
  }) =>
      send<T>(
        ApiRequest.put(
          path: path,
          body: body,
          queryParameters: queryParameters,
          headers: headers,
          requiresAuthentication: requiresAuthentication,
          allowSessionRefresh: allowSessionRefresh,
          enableLogging: enableLogging,
          multipart: multipart,
        ),
        decode: decode,
      );

  /// Sends a PATCH request without exposing a transport-specific response type.
  Future<BackendResult<ApiResponse<T>>> patch<T>({
    required String path,
    Object? body,
    Map<String, Object?> queryParameters = const {},
    Map<String, String> headers = const {},
    bool requiresAuthentication = true,
    bool allowSessionRefresh = true,
    bool enableLogging = false,
    ApiMultipartBody? multipart,
    ApiDecoder<T>? decode,
  }) =>
      send<T>(
        ApiRequest.patch(
          path: path,
          body: body,
          queryParameters: queryParameters,
          headers: headers,
          requiresAuthentication: requiresAuthentication,
          allowSessionRefresh: allowSessionRefresh,
          enableLogging: enableLogging,
          multipart: multipart,
        ),
        decode: decode,
      );

  /// Sends a DELETE request without exposing a transport-specific response type.
  Future<BackendResult<ApiResponse<T>>> delete<T>({
    required String path,
    Object? body,
    Map<String, Object?> queryParameters = const {},
    Map<String, String> headers = const {},
    bool requiresAuthentication = true,
    bool allowSessionRefresh = true,
    bool enableLogging = false,
    ApiDecoder<T>? decode,
  }) =>
      send<T>(
        ApiRequest.delete(
          path: path,
          body: body,
          queryParameters: queryParameters,
          headers: headers,
          requiresAuthentication: requiresAuthentication,
          allowSessionRefresh: allowSessionRefresh,
          enableLogging: enableLogging,
        ),
        decode: decode,
      );

  /// Clears the once-per-token session-expiry guard after a user signs in.
  void resetSessionExpiryGuard() => _expiryCoordinator?.reset();

  Future<BackendResult<ApiResponse<T>>> _send<T>(
    ApiRequest request, {
    required ApiDecoder<T>? decode,
  }) async {
    final accessToken = await _accessTokenFor(request);
    try {
      return BackendSuccess<ApiResponse<T>>(
        await _perform<T>(request, accessToken: accessToken, decode: decode),
      );
    } on DioException catch (error, stackTrace) {
      _logError(request, error);
      if (!_shouldRefresh(request, error)) {
        return BackendFailureResult<ApiResponse<T>>(
          error: ApiErrorMapper.fromDio(error, stackTrace),
        );
      }

      final refreshed = await _refreshSession();
      final tokens = refreshed.data;
      if (tokens == null) {
        await _expireSession(accessToken);
        return BackendFailureResult<ApiResponse<T>>(
          error: refreshed.failure ?? ApiErrorMapper.fromDio(error, stackTrace),
        );
      }

      try {
        return BackendSuccess<ApiResponse<T>>(
          await _perform<T>(
            request,
            accessToken: tokens.accessToken,
            decode: decode,
            isRetriedRequest: true,
          ),
        );
      } on DioException catch (retryError, retryStackTrace) {
        _logError(request, retryError);
        await _expireSession(tokens.accessToken);
        return BackendFailureResult<ApiResponse<T>>(
          error: ApiErrorMapper.fromDio(retryError, retryStackTrace),
        );
      } on Object catch (retryError, retryStackTrace) {
        _logError(request, retryError);
        return BackendFailureResult<ApiResponse<T>>(
          error: BackendErrorClassifier.fromException(
            retryError,
            retryStackTrace,
            fallbackType: BackendErrorType.validation,
          ),
        );
      }
    } on Object catch (error, stackTrace) {
      _logError(request, error);
      return BackendFailureResult<ApiResponse<T>>(
        error: BackendErrorClassifier.fromException(
          error,
          stackTrace,
          fallbackType: BackendErrorType.validation,
        ),
      );
    }
  }

  Future<ApiResponse<T>> _perform<T>(
    ApiRequest request, {
    required String? accessToken,
    required ApiDecoder<T>? decode,
    bool isRetriedRequest = false,
  }) async {
    final headers = <String, dynamic>{...request.headers};
    final locale = await session?.localeProvider?.call();
    if (locale?.trim().isNotEmpty == true) {
      headers[session!.localeHeaderName] = locale;
    }
    if (request.requiresAuthentication &&
        accessToken?.trim().isNotEmpty == true) {
      headers['Authorization'] = 'Bearer $accessToken';
    }

    _logRequest(request, isRetriedRequest: isRetriedRequest);
    final response = await _dio.request<Object?>(
      request.path,
      data: request.multipart?.toFormData() ?? request.body,
      queryParameters: Map<String, dynamic>.from(request.queryParameters),
      options: Options(
        method: request.method.value,
        headers: headers,
        contentType: request.multipart == null
            ? Headers.jsonContentType
            : Headers.multipartFormDataContentType,
      ),
    );
    _logResponse(request, response.statusCode);

    final statusCode = response.statusCode;
    if (statusCode == null || statusCode < 200 || statusCode >= 300) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      );
    }

    final value = decode == null ? response.data as T : decode(response.data);
    return ApiResponse<T>(
      data: value,
      statusCode: statusCode,
      headers: response.headers.map.map(
        (key, value) => MapEntry(key, List<String>.unmodifiable(value)),
      ),
    );
  }

  Future<String?> _accessTokenFor(ApiRequest request) async {
    if (!request.requiresAuthentication) return null;
    final provider = session?.accessTokenProvider;
    return provider == null ? null : await provider();
  }

  bool _shouldRefresh(ApiRequest request, DioException error) {
    final session = this.session;
    if (session == null || !request.requiresAuthentication) return false;
    if (!request.allowSessionRefresh) return false;
    return session.expiredStatusCodes.contains(error.response?.statusCode);
  }

  Future<BackendResult<ApiSessionTokens>> _refreshSession() {
    final active = _refreshing;
    if (active != null) return active;

    final operation = _refresh();
    _refreshing = operation;
    return operation.then(
      (result) {
        _refreshing = null;
        return result;
      },
    );
  }

  Future<BackendResult<ApiSessionTokens>> _refresh() async {
    final session = this.session;
    if (session == null) {
      return BackendFailureResult<ApiSessionTokens>(
        error: BackendErrorClassifier.build(
          type: BackendErrorType.configuration,
          message:
              'API session refresh was requested without a session configuration.',
        ),
      );
    }

    final refreshToken = await session.refreshTokenProvider();
    if (refreshToken?.trim().isEmpty ?? true) {
      return BackendFailureResult<ApiSessionTokens>(
        error: BackendErrorClassifier.build(
          type: BackendErrorType.unauthorized,
          message: 'No refresh token is available.',
        ),
      );
    }

    try {
      final locale = await session.localeProvider?.call();
      final response = await _dio.post<Object?>(
        session.refreshPath,
        data: <String, Object?>{'refresh_token': refreshToken},
        options: Options(
          headers: {
            if (locale?.trim().isNotEmpty == true)
              session.localeHeaderName: locale,
          },
        ),
      );
      final tokens = _tokensFrom(response.data);
      if (tokens == null) {
        return BackendFailureResult<ApiSessionTokens>(
          error: BackendErrorClassifier.build(
            type: BackendErrorType.unauthorized,
            message: 'The refresh endpoint did not return an access token.',
          ),
        );
      }
      await session.onTokensUpdated(tokens);
      return BackendSuccess<ApiSessionTokens>(tokens);
    } on DioException catch (error, stackTrace) {
      return BackendFailureResult<ApiSessionTokens>(
        error: ApiErrorMapper.fromDio(error, stackTrace),
      );
    } on Object catch (error, stackTrace) {
      return BackendFailureResult<ApiSessionTokens>(
        error: BackendErrorClassifier.fromException(
          error,
          stackTrace,
          fallbackType: BackendErrorType.unauthorized,
        ),
      );
    }
  }

  ApiSessionTokens? _tokensFrom(Object? body) {
    if (body is! Map) return null;
    final root = Map<Object?, Object?>.from(body);
    final nested = root['data'];
    final tokens = nested is Map ? Map<Object?, Object?>.from(nested) : root;
    final accessToken = tokens['access_token']?.toString();
    if (accessToken == null || accessToken.trim().isEmpty) return null;
    final refreshToken = tokens['refresh_token']?.toString();
    return ApiSessionTokens(
      accessToken: accessToken,
      refreshToken:
          refreshToken?.trim().isNotEmpty == true ? refreshToken : null,
    );
  }

  Future<void> _expireSession(String? requestToken) async {
    try {
      await _expiryCoordinator?.handle(requestToken);
    } catch (_) {
      // The original backend failure is more useful than a cleanup callback error.
    }
  }

  void _logRequest(ApiRequest request, {required bool isRetriedRequest}) {
    if (!_shouldLog(request)) return;
    _logger.debug(
      '➡️ API Request',
      context: {
        'method': request.method.value,
        'url': _urlFor(request),
        'query': request.queryParameters,
        'retry': isRetriedRequest,
      },
    );
  }

  void _logResponse(ApiRequest request, int? statusCode) {
    if (!_shouldLog(request)) return;
    _logger.info(
      '✅ API Response',
      context: {
        'method': request.method.value,
        'url': _urlFor(request),
        'statusCode': statusCode,
      },
    );
  }

  void _logError(ApiRequest request, Object error) {
    if (!_shouldLog(request)) return;
    final dioError = error is DioException ? error : null;
    _logger.error(
      '❌ API Error',
      context: {
        'method': request.method.value,
        'url': _urlFor(request),
        'statusCode': dioError?.response?.statusCode,
        'type': dioError?.type.name ?? error.runtimeType.toString(),
        'message': dioError?.message ?? error.toString(),
      },
    );
  }

  bool _shouldLog(ApiRequest request) =>
      configuration.isLoggingOn || request.enableLogging;

  Uri _urlFor(ApiRequest request) {
    final path = Uri.parse(request.path);
    final uri = path.hasScheme
        ? path
        : Uri.parse(configuration.baseUrl).resolveUri(path);
    return uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        for (final entry in request.queryParameters.entries)
          if (entry.value != null) entry.key: entry.value.toString(),
      },
    );
  }

  static BackendLogger _resolveLogger(ApiConfiguration configuration) {
    if (configuration.logger is! NoopBackendLogger) {
      return configuration.logger;
    }
    if (!configuration.isLoggingOn) return const NoopBackendLogger();
    return const CallbackBackendLogger(sink: _writeToDeveloperLog);
  }
}

void _writeToDeveloperLog(LogEntry entry) {
  developer.log(entry.toString(), name: 'backend_sdk');
}
