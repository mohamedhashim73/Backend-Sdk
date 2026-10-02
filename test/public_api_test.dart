import 'dart:io';

import 'package:backend_sdk/backend_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

/// Enforces the package's hardest architectural rule: **no Supabase type and no
/// vendor identifier may appear in the public API surface**.
///
/// This is checked by reading the source of the public barrel and every library
/// it exports, rather than by trusting a review. A regression - an accidental
/// `export 'package:supabase/supabase.dart'`, a leaked `PostgrestResponse` in a
/// signature, a table name promoted into the SDK - fails here instead of in a
/// downstream application.
void main() {
  final packageRoot = _findPackageRoot();
  final barrel = File('${packageRoot.path}/lib/backend_sdk.dart');

  group('Public API boundary', () {
    test('the public barrel exists', () {
      expect(barrel.existsSync(), isTrue);
    });

    test('the barrel exports no provider package', () {
      final source = barrel.readAsStringSync();

      expect(
        source,
        isNot(contains("import 'package:supabase")),
        reason: 'the barrel must not import a provider package',
      );
      expect(
        source,
        isNot(contains("export 'package:supabase")),
        reason: 'the barrel must not re-export a provider package',
      );
      expect(source, isNot(contains('package:gotrue')));
      expect(source, isNot(contains('package:postgrest')));
      expect(source, isNot(contains('package:storage_client')));
      expect(source, isNot(contains('package:realtime_client')));
    });

    test('no exported library leaks a Supabase type', () {
      final offenders = <String>[];

      for (final file in _publicLibraries(barrel)) {
        final source = file.readAsStringSync();
        // Strip doc comments, which legitimately *mention* provider names to
        // explain what is being hidden.
        final code = _stripComments(source);
        for (final type in _forbiddenTypes) {
          if (code.contains(type)) {
            offenders.add('${file.path}: $type');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'These Supabase types leaked into the public API:\n'
            '${offenders.join('\n')}',
      );
    });

    test('no exported library exposes a raw provider record type', () {
      final offenders = <String>[];

      for (final file in _publicLibraries(barrel)) {
        final code = _stripComments(file.readAsStringSync());
        if (code.contains('BackendRecord')) {
          offenders.add('${file.path}: BackendRecord');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'A raw provider record type must never reach the public API:\n'
            '${offenders.join('\n')}',
      );
    });

    test('no provider-specific code exists outside the provider directory', () {
      final offenders = <String>[];
      final providersDir = Directory('${packageRoot.path}/lib/src/providers');

      for (final file in _allDartFiles(Directory('${packageRoot.path}/lib'))) {
        if (file.path.contains(providersDir.path)) continue;
        final code = _stripComments(file.readAsStringSync());
        if (code.contains('package:supabase') ||
            code.contains('package:gotrue') ||
            code.contains('package:postgrest') ||
            code.contains('package:storage_client') ||
            code.contains('package:realtime_client')) {
          offenders.add(file.path);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'Provider imports must stay inside lib/src/providers/: '
            '${offenders.join(', ')}',
      );
    });

    test('the provider directory is self-contained', () {
      final providers =
          Directory('${packageRoot.path}/lib/src/providers/supabase');

      expect(providers.existsSync(), isTrue);
      final files = providers.listSync().whereType<File>().toList();

      expect(
        files.map((f) => f.uri.pathSegments.last),
        containsAll(<String>[
          'supabase_provider.dart',
          'supabase_auth_backend.dart',
          'supabase_data_backend.dart',
          'supabase_storage_backend.dart',
          'supabase_realtime_backend.dart',
          'supabase_error_mapper.dart',
          'supabase_mappers.dart',
        ]),
      );
    });

    test('the contracts a provider must implement are not exported publicly',
        () {
      // `BackendRecord` is the giveaway: if the barrel exported the data
      // contract, the type alias would be public too.
      final source = barrel.readAsStringSync();
      expect(source, isNot(contains('contracts/data_backend.dart')));
      expect(source, isNot(contains('contracts/data_query_spec.dart')));
    });

    test('no table or bucket name is baked into the public API', () {
      final offenders = <String>[];

      // Bucket identifiers are legitimately private to the provider; the
      // public enum only carries `key == name`, never a literal.
      for (final file in _publicLibraries(barrel)) {
        final code = _stripComments(file.readAsStringSync());
        for (final table in const <String>[
          "'products'",
          "'users'",
          "'avatars'",
          "'documents'",
        ]) {
          if (code.contains(table)) {
            offenders.add('${file.path}: $table');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'A physical table or bucket name must not appear in the public '
            'API:\n${offenders.join('\n')}',
      );
    });

    test('every public member is documented', () {
      final undocumented = <String>[];

      for (final file in _publicLibraries(barrel)) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final trimmed = line.trim();
          final declaresPublicMember = RegExp(
            r'^\s*(final|const|late|static|[A-Z][A-Za-z0-9_<>?, ]*)\s+'
            r'(get\s+)?[a-zA-Z][A-Za-z0-9_]*\s*[({=;]',
          ).hasMatch(line);
          final isPrivate = RegExp(r'[_$]\w').hasMatch(
            trimmed.split(RegExp(r'\s+')).first.replaceFirst('get ', ''),
          );
          if (!declaresPublicMember || isPrivate) continue;
          if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;

          final previous = i > 0 ? lines[i - 1].trim() : '';
          final isDocumented = previous.startsWith('///') ||
              previous.endsWith(',') ||
              previous.startsWith('///') ||
              trimmed.startsWith('@');

          if (!isDocumented) {
            undocumented.add('${file.path}:${i + 1}: $trimmed');
          }
        }
      }

      expect(
        undocumented,
        isEmpty,
        reason: 'Undocumented public API:\n${undocumented.join('\n')}',
      );
    });

    test('the expected modules are present and exported', () {
      final source = barrel.readAsStringSync();

      for (final module in const <String>[
        'core/backend_sdk.dart',
        'core/backend_configuration.dart',
        'core/backend_provider.dart',
        'auth/auth_repository.dart',
        'storage/storage_repository.dart',
        'realtime/realtime_repository.dart',
        'modules/products/products_repository.dart',
        'modules/users/users_repository.dart',
        'result/backend_result.dart',
        'errors/backend_failure.dart',
      ]) {
        expect(source, contains(module), reason: '$module must be exported');
      }
    });
  });

  group('Public API is provider-agnostic in practice', () {
    test('the documented usage example compiles against the public API', () {
      // If any of the documented symbols were missing from the barrel, this
      // would not compile.
      const BackendConfiguration configuration = BackendConfiguration(
        provider: BackendProvider.supabase,
      );
      const PageRequest pageRequest = PageRequest(page: 1, pageSize: 20);
      const CursorRequest cursorRequest = CursorRequest(limit: 20);
      const FilterCondition filter =
          FilterCondition.equals('categoryId', 'electronics');
      const SortCondition sort = SortCondition.descending('createdAt');
      const UploadFileRequest upload = UploadFileRequest(
        bucket: StorageBucket.general,
        path: 'products/p1/image.jpg',
        bytes: [],
        contentType: 'image/jpeg',
      );
      const CreateProductRequest create =
          CreateProductRequest(name: 'Phone', price: 1000);
      const UpdateProductRequest update =
          UpdateProductRequest(name: 'Updated Phone');
      const BackendFailure failure = BackendFailure(
        type: BackendErrorType.validation,
        message: 'x',
        isRetryable: false,
      );

      expect(configuration.provider, BackendProvider.supabase);
      expect(pageRequest.page, 1);
      expect(cursorRequest.limit, 20);
      expect(filter.field, 'categoryId');
      expect(sort.ascending, isFalse);
      expect(upload.bucket, StorageBucket.general);
      expect(create.price, 1000);
      expect(update.name, 'Updated Phone');
      expect(failure.type, BackendErrorType.validation);
    });

    test('the application can act on a result without a provider type', () {
      const BackendResult<Product> result = BackendSuccess<Product>(
        Product(
          id: 'p1',
          name: 'Phone',
          price: 1,
          stock: 1,
          isActive: true,
        ),
      );

      final label = result.when(
        success: (product) => product.name,
        failure: (failure) => failure.safeMessage,
      );

      expect(label, 'Phone');
    });
  });
}

/// Supabase and provider type names that must never appear in public code.
const List<String> _forbiddenTypes = <String>[
  'SupabaseClient',
  'SupabaseStorageClient',
  'PostgrestResponse',
  'PostgrestException',
  'PostgrestFilterBuilder',
  'PostgrestTransformBuilder',
  'PostgrestList',
  'PostgrestMap',
  'AuthException',
  'StorageException',
  'StorageFileApi',
  'RealtimeChannel',
  'RealtimeSubscribeStatus',
  'PostgresChangePayload',
  'PostgresChangeEvent',
  'RealtimeClient',
  'GoTrueClient',
  'AuthApiException',
];

/// Resolves the package root by walking up until `pubspec.yaml` is found.
Directory _findPackageRoot() {
  var directory = Directory.current;
  while (!File('${directory.path}/pubspec.yaml').existsSync()) {
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Could not locate the package root.');
    }
    directory = parent;
  }
  return directory;
}

/// Collects the libraries the barrel exports, transitively.
List<File> _publicLibraries(File barrel) {
  final libDir = barrel.parent;
  final visited = <File>{barrel};
  final queue = <File>[barrel];

  while (queue.isNotEmpty) {
    final file = queue.removeLast();
    final source = file.readAsStringSync();
    for (final match in RegExp(
      r"""^export\s+'([^']+)'""",
      multiLine: true,
    ).allMatches(source)) {
      final target = match.group(1)!;
      if (target.startsWith('dart:') || target.startsWith('package:')) {
        continue;
      }
      final resolved = File(_resolve(file.parent, target));
      if (resolved.existsSync() && visited.add(resolved)) {
        queue.add(resolved);
      }
    }
  }

  // Only files under lib/ belong to the public surface; anything reached by a
  // path that leaves lib/ is a bug worth surfacing too.
  if (!libDir.existsSync()) {
    throw StateError('The public library directory is missing.');
  }

  return visited.where((f) => f.path.contains('/lib/')).toList();
}

String _resolve(Directory from, String relative) {
  final normalized = relative.startsWith('src/')
      ? relative.substring('src/'.length)
      : relative;
  return '${from.path}/$normalized';
}

/// Removes `//` and block comments so a doc mention is not a false positive.
String _stripComments(String source) {
  final withoutBlocks = source.replaceAll(
    RegExp(r'/\*[\s\S]*?\*/'),
    '',
  );
  return withoutBlocks.split('\n').map((line) {
    final index = line.indexOf('//');
    return index < 0 ? line : line.substring(0, index);
  }).join('\n');
}

List<File> _allDartFiles(Directory directory) {
  return directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
}
