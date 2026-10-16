import 'package:backend_sdk/backend_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_data_backend.dart';

void main() {
  const routing = BackendRouting(
    operationTargets: <String, String>{'home.load': 'get_home_feed'},
  );
  const operation = BackendOperation<_HomeRequest, _HomeResponse>(
    key: 'home.load',
    authScope: BackendAuthScope.required,
    encode: _HomeRequest.toJson,
    decode: _HomeResponse.fromJson,
  );

  test('operation client resolves a logical route and decodes a typed result',
      () async {
    final backend = FakeDataBackend()
      ..rpcResponses['get_home_feed'] = <String, Object?>{'title': 'Welcome'};
    final tokens = _FakeTokenProvider();
    final client = BackendOperationClient(
      backend: backend,
      routing: routing,
      tokens: tokens,
      executor: const RequestExecutor(
        retryPolicy: RetryPolicy.noRetries,
        requestTimeout: Duration(seconds: 1),
      ),
    );

    final result = await client.execute(operation, const _HomeRequest('ar'));

    expect(result.data?.title, 'Welcome');
    expect(tokens.requiredCalls, 1);
  });

  test('operation client rejects a missing route before provider dispatch',
      () async {
    final backend = FakeDataBackend();
    final client = BackendOperationClient(
      backend: backend,
      routing: const BackendRouting(),
      tokens: _FakeTokenProvider(),
      executor: const RequestExecutor(
        retryPolicy: RetryPolicy.noRetries,
        requestTimeout: Duration(seconds: 1),
      ),
    );

    final result = await client.execute(operation, const _HomeRequest('ar'));

    expect(result.failure?.type, BackendErrorType.configuration);
  });

  test('resource definition decodes without a hand-written codec', () {
    const definition =
        BackendResourceDefinition<_Story, _StoryRequest, _StoryRequest>(
      descriptor: BackendResourceDescriptor(key: 'stories'),
      fromJson: _Story.fromJson,
      toCreateJson: _StoryRequest.toJson,
      toUpdateJson: _StoryRequest.toJson,
    );

    final result = definition.toCodec().decode(<String, dynamic>{
      'id': 'story-1',
      'title': 'Welcome',
    });

    expect(result.data, const _Story('story-1', 'Welcome'));
  });
}

class _FakeTokenProvider implements BackendTokenProvider {
  int requiredCalls = 0;

  @override
  Future<BackendResult<String?>> accessToken({
    bool requireAuthenticated = false,
    CancellationToken? cancellationToken,
  }) async {
    if (requireAuthenticated) requiredCalls++;
    return const BackendSuccess<String?>('token');
  }
}

class _HomeRequest {
  final String locale;

  const _HomeRequest(this.locale);

  static Map<String, Object?> toJson(_HomeRequest request) =>
      <String, Object?>{'locale': request.locale};
}

class _HomeResponse {
  final String title;

  const _HomeResponse(this.title);

  static _HomeResponse fromJson(Object? value) {
    final json = Map<String, Object?>.from(value! as Map);
    return _HomeResponse(json['title']! as String);
  }
}

class _Story {
  final String id;
  final String title;

  const _Story(this.id, this.title);

  static _Story fromJson(Map<String, dynamic> json) =>
      _Story(json['id']! as String, json['title']! as String);

  @override
  bool operator ==(Object other) =>
      other is _Story && other.id == id && other.title == title;

  @override
  int get hashCode => Object.hash(id, title);
}

class _StoryRequest {
  final String title;

  const _StoryRequest(this.title);

  static Map<String, Object?> toJson(_StoryRequest request) =>
      <String, Object?>{'title': request.title};
}
