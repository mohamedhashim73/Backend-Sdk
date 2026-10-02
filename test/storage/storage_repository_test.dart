import 'dart:typed_data';

import 'package:backend_sdk/backend_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late FakeStorageBackend backend;
  late StorageRepository repository;

  setUp(() {
    backend = FakeStorageBackend();
    repository = StorageRepository(
      backend: backend,
      executor: const RequestExecutor(
        retryPolicy: RetryPolicy.noRetries,
        requestTimeout: Duration.zero,
      ),
    );
  });

  Uint8List bytes([int length = 8]) =>
      Uint8List.fromList(List<int>.generate(length, (i) => i));

  group('StorageRepository - upload', () {
    test('a valid upload stores the bytes and returns a typed file', () async {
      final result = await repository.upload(
        request: UploadFileRequest(
          bucket: StorageBucket.products,
          path: 'products/p1/image.jpg',
          bytes: bytes(64),
          contentType: 'image/jpeg',
        ),
      );

      final file = result.data!;
      expect(file.bucket, StorageBucket.products);
      expect(file.path, 'products/p1/image.jpg');
      expect(file.sizeInBytes, 64);
      expect(backend.uploadCalls, 1);
    });

    test('an unsafe path never reaches the provider', () async {
      for (final path in <String>[
        '',
        '/absolute.jpg',
        '../escape.jpg',
        'a/../../b.jpg',
        'a//b.jpg',
        'a\\b.jpg',
        'a/./b.jpg',
        'a/b.jpg?token=leak',
        'a/b.jpg#frag',
        'a/b .jpg/../..',
      ]) {
        final result = await repository.upload(
          request: UploadFileRequest(
            bucket: StorageBucket.general,
            path: path,
            bytes: bytes(),
            contentType: 'image/jpeg',
          ),
        );
        expect(
          result.failure?.type,
          BackendErrorType.validation,
          reason: 'the path "$path" must be rejected',
        );
      }
      expect(backend.uploadCalls, 0);
    });

    test('a path with unsupported characters is rejected', () async {
      final result = await repository.upload(
        request: UploadFileRequest(
          bucket: StorageBucket.general,
          path: 'a/evil;rm.jpg',
          bytes: bytes(),
          contentType: 'image/jpeg',
        ),
      );

      expect(result.failure?.type, BackendErrorType.validation);
      expect(result.failure?.message, contains('unsupported characters'));
    });

    test('an over-long path is rejected', () async {
      final result = await repository.upload(
        request: UploadFileRequest(
          bucket: StorageBucket.general,
          path: 'a' * (StoragePathValidator.maxPathLength + 1),
          bytes: bytes(),
          contentType: 'image/jpeg',
        ),
      );

      expect(result.failure?.type, BackendErrorType.validation);
    });

    test('a malformed content type is rejected', () async {
      for (final contentType in <String>[
        '',
        'image',
        'image/',
        '/jpeg',
        'image jpeg',
        'image/jpeg\r\nX-Injected: 1',
      ]) {
        final result = await repository.upload(
          request: UploadFileRequest(
            bucket: StorageBucket.general,
            path: 'a.jpg',
            bytes: bytes(),
            contentType: contentType,
          ),
        );
        expect(
          result.failure?.type,
          BackendErrorType.validation,
          reason: 'the content type "$contentType" must be rejected',
        );
      }
      expect(backend.uploadCalls, 0);
    });

    test('an empty payload is rejected', () async {
      final result = await repository.upload(
        request: const UploadFileRequest(
          bucket: StorageBucket.general,
          path: 'a.jpg',
          bytes: [],
          contentType: 'image/jpeg',
        ),
      );

      expect(result.failure?.type, BackendErrorType.validation);
    });

    test('an oversized payload is rejected against the configured limit',
        () async {
      final small = StorageRepository(
        backend: backend,
        executor: const RequestExecutor(
          retryPolicy: RetryPolicy.noRetries,
          requestTimeout: Duration.zero,
        ),
        maxFileSizeInBytes: 16,
      );

      final result = await small.upload(
        request: UploadFileRequest(
          bucket: StorageBucket.general,
          path: 'a.bin',
          bytes: bytes(64),
          contentType: 'application/octet-stream',
        ),
      );

      expect(result.failure?.type, BackendErrorType.validation);
      expect(result.failure?.message, contains('exceeds'));
      expect(backend.uploadCalls, 0);
    });

    test('re-uploading without upsert surfaces a conflict', () async {
      const request = UploadFileRequest(
        bucket: StorageBucket.general,
        path: 'a.jpg',
        bytes: [],
        contentType: 'image/jpeg',
      );

      await repository.upload(
        request: UploadFileRequest(
          bucket: request.bucket,
          path: request.path,
          bytes: bytes(4),
          contentType: request.contentType,
        ),
      );
      final second = await repository.upload(
        request: UploadFileRequest(
          bucket: request.bucket,
          path: request.path,
          bytes: bytes(4),
          contentType: request.contentType,
        ),
      );

      expect(second.failure?.type, BackendErrorType.conflict);
    });

    test('upsert overwrites an existing object', () async {
      Future<BackendResult<UploadedFile>> put(bool upsert) {
        return repository.upload(
          request: UploadFileRequest(
            bucket: StorageBucket.general,
            path: 'a.jpg',
            bytes: bytes(4),
            contentType: 'image/jpeg',
            upsert: upsert,
          ),
        );
      }

      await put(false);
      final second = await put(true);

      expect(second.isSuccess, isTrue);
    });

    test('toString reports the size but never the contents', () {
      const request = UploadFileRequest(
        bucket: StorageBucket.avatars,
        path: 'avatars/u1.png',
        bytes: [],
        contentType: 'image/png',
      );

      // The length is safe and useful; the payload never appears.
      expect(request.toString(), contains('bytes: 0'));
      expect(request.toString(), isNot(contains('[')));
    });
  });

  group('StorageRepository - read', () {
    setUp(() async {
      await repository.upload(
        request: UploadFileRequest(
          bucket: StorageBucket.documents,
          path: 'documents/u1/report.pdf',
          bytes: bytes(16),
          contentType: 'application/pdf',
        ),
      );
    });

    test('download returns the stored bytes', () async {
      final result = await repository.download(
        bucket: StorageBucket.documents,
        path: 'documents/u1/report.pdf',
      );

      expect(result.data, hasLength(16));
    });

    test('downloading a missing object is a notFound failure', () async {
      final result = await repository.download(
        bucket: StorageBucket.documents,
        path: 'documents/u1/missing.pdf',
      );

      expect(result.failure?.type, BackendErrorType.notFound);
    });

    test('downloading with an unsafe path is rejected locally', () async {
      final result = await repository.download(
        bucket: StorageBucket.documents,
        path: '../escape.pdf',
      );

      expect(result.failure?.type, BackendErrorType.validation);
    });

    test('a public URL is returned for a public bucket', () async {
      final result = await repository.getPublicUrl(
        bucket: StorageBucket.general,
        path: 'logo.png',
      );

      expect(result.data, contains('general/logo.png'));
    });
  });

  group('StorageRepository - signed URLs', () {
    test('a signed URL is created with the requested lifetime', () async {
      final result = await repository.createSignedUrl(
        bucket: StorageBucket.documents,
        path: 'documents/u1/report.pdf',
        expiresIn: 600,
      );

      final signed = result.data!;
      expect(signed.bucket, StorageBucket.documents);
      expect(signed.isExpired(), isFalse);
      expect(
        signed.expiresAt.difference(DateTime.now()).inSeconds,
        closeTo(600, 5),
      );
    });

    test('the default lifetime is the documented five minutes', () async {
      final result = await repository.createSignedUrl(
        bucket: StorageBucket.documents,
        path: 'a.pdf',
      );

      expect(
        result.data!.expiresAt.difference(DateTime.now()).inSeconds,
        closeTo(StoragePathValidator.defaultSignedUrlSeconds, 5),
      );
    });

    test('a too-short lifetime is rejected', () async {
      final result = await repository.createSignedUrl(
        bucket: StorageBucket.documents,
        path: 'a.pdf',
        expiresIn: StoragePathValidator.minSignedUrlSeconds - 1,
      );

      expect(result.failure?.type, BackendErrorType.validation);
    });

    test('an unbounded lifetime is rejected', () async {
      final result = await repository.createSignedUrl(
        bucket: StorageBucket.documents,
        path: 'a.pdf',
        expiresIn: StoragePathValidator.maxSignedUrlSeconds + 1,
      );

      expect(result.failure?.type, BackendErrorType.validation);
      expect(result.failure?.message, contains('must not remain valid'));
    });

    test('a signed URL is never rendered by toString', () {
      final signed = SignedFileUrl(
        bucket: StorageBucket.documents,
        path: 'a.pdf',
        url: 'https://cdn.example.com/a.pdf?token=secret',
        expiresAt: DateTime.now(),
      );

      expect(signed.toString(), isNot(contains('secret')));
    });
  });

  group('StorageRepository - move, copy and delete', () {
    setUp(() async {
      await repository.upload(
        request: UploadFileRequest(
          bucket: StorageBucket.general,
          path: 'src/a.txt',
          bytes: bytes(4),
          contentType: 'text/plain',
        ),
      );
    });

    test('move relocates the object', () async {
      final result = await repository.moveFile(
        request: const MoveFileRequest(
          fromBucket: StorageBucket.general,
          fromPath: 'src/a.txt',
          toPath: 'dst/a.txt',
        ),
      );

      expect(result.data!.path, 'dst/a.txt');
      expect(
        backend.files.containsKey('general/src/a.txt'),
        isFalse,
      );
      expect(backend.files.containsKey('general/dst/a.txt'), isTrue);
    });

    test('move across buckets relocates the object', () async {
      final result = await repository.moveFile(
        request: const MoveFileRequest(
          fromBucket: StorageBucket.general,
          fromPath: 'src/a.txt',
          toBucket: StorageBucket.avatars,
          toPath: 'u1.png',
        ),
      );

      expect(result.data!.bucket, StorageBucket.avatars);
      expect(backend.files.containsKey('avatars/u1.png'), isTrue);
    });

    test('move rejects an identical source and destination', () async {
      final result = await repository.moveFile(
        request: const MoveFileRequest(
          fromBucket: StorageBucket.general,
          fromPath: 'src/a.txt',
          toPath: 'src/a.txt',
        ),
      );

      expect(result.failure?.type, BackendErrorType.validation);
    });

    test('copy leaves the original in place', () async {
      final result = await repository.copyFile(
        request: const CopyFileRequest(
          fromBucket: StorageBucket.general,
          fromPath: 'src/a.txt',
          toPath: 'dst/copy.txt',
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(backend.files.containsKey('general/src/a.txt'), isTrue);
      expect(backend.files.containsKey('general/dst/copy.txt'), isTrue);
    });

    test('copy rejects an identical source and destination', () async {
      final result = await repository.copyFile(
        request: const CopyFileRequest(
          fromBucket: StorageBucket.general,
          fromPath: 'src/a.txt',
          toPath: 'src/a.txt',
        ),
      );

      expect(result.failure?.type, BackendErrorType.validation);
    });

    test('moving a missing object is a notFound failure', () async {
      final result = await repository.moveFile(
        request: const MoveFileRequest(
          fromBucket: StorageBucket.general,
          fromPath: 'src/missing.txt',
          toPath: 'dst/x.txt',
        ),
      );

      expect(result.failure?.type, BackendErrorType.notFound);
    });

    test('delete removes the object', () async {
      final result = await repository.deleteFile(
        bucket: StorageBucket.general,
        path: 'src/a.txt',
      );

      expect(result.isSuccess, isTrue);
      expect(backend.files.containsKey('general/src/a.txt'), isFalse);
    });

    test('deleting a missing object is a notFound failure', () async {
      final result = await repository.deleteFile(
        bucket: StorageBucket.general,
        path: 'src/missing.txt',
      );

      expect(result.failure?.type, BackendErrorType.notFound);
    });
  });

  group('StorageRepository - listing', () {
    setUp(() async {
      for (var i = 0; i < 5; i++) {
        await repository.upload(
          request: UploadFileRequest(
            bucket: StorageBucket.general,
            path: 'images/$i.png',
            bytes: bytes(2),
            contentType: 'image/png',
          ),
        );
      }
    });

    test('lists entries under a prefix', () async {
      final result = await repository.listFiles(
        request: const ListFilesRequest(bucket: StorageBucket.general),
      );

      expect(result.data, hasLength(5));
    });

    test('a limit bounds the result', () async {
      final result = await repository.listFiles(
        request: const ListFilesRequest(
          bucket: StorageBucket.general,
          limit: 2,
        ),
      );

      expect(result.data, hasLength(2));
    });

    test('an offset skips entries', () async {
      final all = (await repository.listFiles(
        request: const ListFilesRequest(bucket: StorageBucket.general),
      ))
          .data!
          .map((e) => e.path)
          .toList();
      final skipped = (await repository.listFiles(
        request: const ListFilesRequest(
          bucket: StorageBucket.general,
          offset: 2,
        ),
      ))
          .data!
          .map((e) => e.path)
          .toList();

      expect(skipped, all.skip(2).toList());
    });

    test('a zero limit is rejected locally', () async {
      final result = await repository.listFiles(
        request:
            const ListFilesRequest(bucket: StorageBucket.general, limit: 0),
      );

      expect(result.failure?.type, BackendErrorType.validation);
    });

    test('a negative offset is rejected locally', () async {
      final result = await repository.listFiles(
        request: const ListFilesRequest(
          bucket: StorageBucket.general,
          offset: -1,
        ),
      );

      expect(result.failure?.type, BackendErrorType.validation);
    });

    test('a prefix with traversal is rejected locally', () async {
      final result = await repository.listFiles(
        request: const ListFilesRequest(
          bucket: StorageBucket.general,
          prefix: '../',
        ),
      );

      expect(result.failure?.type, BackendErrorType.validation);
    });
  });

  group('StorageRepository - failure mapping', () {
    test('a transient storage failure is retried', () async {
      final retrying = StorageRepository(
        backend: backend,
        executor: RequestExecutor(
          retryPolicy: const RetryPolicy(maxRetries: 2, jitter: 0),
          requestTimeout: Duration.zero,
          delay: (_) async {},
        ),
      );

      backend.nextFailure = BackendErrorClassifier.build(
        type: BackendErrorType.network,
        message: 'flaky',
      );

      final result = await retrying.upload(
        request: UploadFileRequest(
          bucket: StorageBucket.general,
          path: 'a.txt',
          bytes: bytes(2),
          contentType: 'text/plain',
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(backend.uploadCalls, 2);
    });

    test('a typed failure from the provider is preserved', () async {
      backend.nextFailure = BackendErrorClassifier.build(
        type: BackendErrorType.forbidden,
        message: 'policy denied',
      );

      final result = await repository.download(
        bucket: StorageBucket.documents,
        path: 'a.pdf',
      );

      expect(result.failure?.type, BackendErrorType.forbidden);
    });
  });

  group('StorageBucket', () {
    test('each bucket has a stable key', () {
      expect(StorageBucket.general.key, 'general');
      expect(StorageBucket.avatars.key, 'avatars');
      expect(StorageBucket.products.key, 'products');
      expect(StorageBucket.documents.key, 'documents');
    });
  });
}
