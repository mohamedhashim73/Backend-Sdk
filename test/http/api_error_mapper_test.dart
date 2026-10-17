import 'package:backend_sdk/backend_sdk.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exposes the first nested validation message to the user', () {
    final failure = ApiErrorMapper.fromDio(
      DioException(
        requestOptions: RequestOptions(path: '/auth/register'),
        response: Response<Object?>(
          requestOptions: RequestOptions(path: '/auth/register'),
          statusCode: 422,
          data: <String, Object?>{
            'message': 'One or more validation errors occurred.',
            'errors': <String, Object?>{
              'image': <String>['The image field must be an image.'],
            },
          },
        ),
        type: DioExceptionType.badResponse,
      ),
      StackTrace.current,
    );

    expect(failure.type, BackendErrorType.validation);
    expect(failure.message, 'The image field must be an image.');
    expect(failure.safeMessage, 'The image field must be an image.');
  });
}
