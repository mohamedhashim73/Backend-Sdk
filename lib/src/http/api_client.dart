import 'dart:async';

import 'package:dio/dio.dart';

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
  final RequestExecutor _executor;
  final ApiSessionExpiryCoordinator? _expiryCoordinator;
  Future<BackendResult<ApiSessionTokens>>? _refreshing;

  ApiClient({
    required this.configuration,
    this.session,
    Dio? dio,
  })  : _dio = dio ?? Dio(),
        _executor = RequestExecutor(
          retryPolicy: configuration.retryPolicy,
          requestTimeout: configuration.receiveTimeout,
          logger: configuration.logger,
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
        await _expireSession(tokens.accessToken);
        return BackendFailureResult<ApiResponse<T>>(
          error: ApiErrorMapper.fromDio(retryError, retryStackTrace),
        );
      } on Object catch (retryError, retryStackTrace) {
        return BackendFailureResult<ApiResponse<T>>(
          error: BackendErrorClassifier.fromException(
            retryError,
            retryStackTrace,
            fallbackType: BackendErrorType.validation,
          ),
        );
      }
    } on Object catch (error, stackTrace) {
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
    if (!request.enableLogging) return;
    configuration.logger.debug(
      'HTTP request',
      context: {
        'method': request.method.value,
        'path': request.path,
        'query': request.queryParameters,
        'retry': isRetriedRequest,
      },
    );
  }

  void _logResponse(ApiRequest request, int? statusCode) {
    if (!request.enableLogging) return;
    configuration.logger.info(
      'HTTP response',
      context: {
        'method': request.method.value,
        'path': request.path,
        'statusCode': statusCode,
      },
    );
  }
}
