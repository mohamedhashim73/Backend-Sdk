import 'package:backend_sdk/backend_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_data_backend.dart';

void main() {
  test('deleteWhere forwards exact filters to the optional provider capability',
      () async {
    final backend = _DeleteBackend();
    final client = _client(backend);

    final result = await client.deleteWhere(
      filters: const <FilterCondition>[
        FilterCondition.equals('user_id', 'user-1'),
      ],
    );

    expect(result.isSuccess, isTrue);
    expect(backend.lastResource?.key, 'user_roles');
    expect(backend.lastSpec?.filters.single.field, 'user_id');
    expect(backend.lastSpec?.filters.single.value, 'user-1');
  });

  test('deleteWhere rejects an unbounded or non-exact delete', () async {
    final backend = _DeleteBackend();
    final client = _client(backend);

    final empty = await client.deleteWhere(filters: const <FilterCondition>[]);
    final range = await client.deleteWhere(
      filters: const <FilterCondition>[
        FilterCondition.greaterThan('user_id', 'user-1'),
      ],
    );

    expect(empty.failure?.type, BackendErrorType.validation);
    expect(range.failure?.type, BackendErrorType.validation);
    expect(backend.calls, 0);
  });
}

BackendResourceClient<_Link, Map<String, Object?>, Map<String, Object?>>
    _client(
  DataBackend backend,
) {
  return BackendResourceClient<_Link, Map<String, Object?>,
      Map<String, Object?>>(
    backend: backend,
    definition: BackendResourceDefinition<_Link, Map<String, Object?>,
        Map<String, Object?>>(
      descriptor: const BackendResourceDescriptor(key: 'user_roles'),
      fromJson: _Link.fromJson,
      toCreateJson: (request) => request,
      toUpdateJson: (request) => request,
    ),
    executor: const RequestExecutor(
      retryPolicy: RetryPolicy.noRetries,
      requestTimeout: Duration(seconds: 1),
    ),
    logger: const NoopBackendLogger(),
  );
}

class _DeleteBackend extends FakeDataBackend
    implements DescriptorDeleteBackend {
  BackendResourceDescriptor? lastResource;
  DataQuerySpec? lastSpec;
  int calls = 0;

  @override
  Future<BackendResult<void>> deleteWhere({
    required BackendResourceDescriptor resource,
    required DataQuerySpec spec,
  }) async {
    calls++;
    lastResource = resource;
    lastSpec = spec;
    return const BackendSuccess<void>(null);
  }
}

class _Link {
  final String id;

  const _Link(this.id);

  static _Link fromJson(Map<String, dynamic> json) =>
      _Link(json['id']! as String);
}
