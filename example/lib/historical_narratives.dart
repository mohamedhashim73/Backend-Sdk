import 'package:backend_sdk/backend_sdk.dart';

/// An application-owned resource. Adding this file never requires changing
/// backend_sdk or creating another provider client.
abstract final class HistoricalNarrativeResource {
  static const descriptor = BackendResourceDescriptor(
    key: 'historical_narratives',
    tableName: 'historical_narratives',
    searchableFields: {'title', 'description'},
    defaultSorting: [SortCondition.descending('published_at')],
  );
}

class HistoricalNarrative {
  final String id;
  final String title;
  final String description;

  const HistoricalNarrative({
    required this.id,
    required this.title,
    required this.description,
  });

  static HistoricalNarrative fromBackend(BackendRecord record) {
    return HistoricalNarrative(
      id: record['id'] as String,
      title: record['title'] as String,
      description: record['description'] as String,
    );
  }
}

class HistoricalNarrativeCodec
    implements ResourceCodec<HistoricalNarrative, Map<String, Object?>,
        Map<String, Object?>> {
  const HistoricalNarrativeCodec();

  @override
  BackendResourceDescriptor get descriptor =>
      HistoricalNarrativeResource.descriptor;

  @override
  BackendResult<HistoricalNarrative> decode(BackendRecord record) {
    try {
      return BackendSuccess(HistoricalNarrative.fromBackend(record));
    } on Object {
      return failureOf(CodecFailures.decode(
        'historical narrative',
        'required fields are missing or have an invalid type.',
      ));
    }
  }

  @override
  BackendResult<Map<String, Object?>> encodeCreate(Map<String, Object?> value) =>
      BackendSuccess(Map<String, Object?>.unmodifiable(value));

  @override
  BackendResult<Map<String, Object?>> encodeUpdate(Map<String, Object?> value) =>
      BackendSuccess(Map<String, Object?>.unmodifiable(value));

  @override
  BackendFailure? validateCreate(Map<String, Object?> value) => null;

  @override
  BackendFailure? validateUpdate(Map<String, Object?> value) => null;
}

class HistoricalNarrativesRepository extends BackendRepository<
    HistoricalNarrative, Map<String, Object?>, Map<String, Object?>> {
  HistoricalNarrativesRepository({
    required DataBackend backend,
    required RequestExecutor executor,
  }) : super(
          backend: backend,
          executor: executor,
          codec: const HistoricalNarrativeCodec(),
        );
}

Future<BackendResult<PageResult<HistoricalNarrative>>> loadNarratives(
  HistoricalNarrativesRepository repository,
) {
  return repository.getPage(
    request: const PageRequest(
      page: 1,
      pageSize: 20,
      search: 'museum',
      sorting: [SortCondition.descending('published_at')],
    ),
  );
}
