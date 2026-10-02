import 'dart:typed_data';

import 'package:supabase/supabase.dart'
    show FileOptions, SearchOptions, SupabaseClient, SupabaseStorageClient;

import '../../contracts/storage_backend.dart';
import '../../errors/backend_error_mapper.dart';
import '../../errors/backend_error_type.dart';
import '../../errors/backend_failure.dart';
import '../../result/backend_result.dart';
import '../../storage/storage_bucket.dart';
import '../../storage/storage_requests.dart';
import '../../storage/uploaded_file.dart';
import 'supabase_error_mapper.dart';
import 'supabase_mappers.dart';

/// Adapts Supabase Storage to the `StorageBackend` contract.
///
/// The bucket mapping lives here, and only here. `StorageBucket.general` and
/// `'general'` never appear in the same layer, so a bucket rename is a single
/// edit in this package.
///
/// No `StorageFileApi`, `FileObject` or raw provider URL leaves this class.
class SupabaseStorageBackend implements StorageBackend {
  final SupabaseStorageClient _storage;
  final SupabaseErrorMapper _errorMapper;

  /// Maps an SDK bucket onto its Supabase bucket identifier.
  static const Map<StorageBucket, String> _bucketIds = <StorageBucket, String>{
    StorageBucket.general: 'general',
    StorageBucket.avatars: 'avatars',
    StorageBucket.products: 'products',
    StorageBucket.documents: 'documents',
  };

  /// Creates the adapter over the storage client of [client].
  SupabaseStorageBackend({
    required SupabaseClient client,
    SupabaseErrorMapper errorMapper = const SupabaseErrorMapper(),
  })  : _storage = client.storage,
        _errorMapper = errorMapper;

  /// The Supabase bucket identifier for [bucket].
  static String bucketIdOf(StorageBucket bucket) {
    final id = _bucketIds[bucket];
    if (id == null) {
      throw BackendErrorClassifier.build(
        type: BackendErrorType.configuration,
        message: 'No Supabase bucket is configured for $bucket.',
      );
    }
    return id;
  }

  @override
  Future<BackendResult<UploadedFile>> upload({
    required StorageBucket bucket,
    required String path,
    required Uint8List bytes,
    required String contentType,
    required bool upsert,
  }) {
    return _guard('upload', () async {
      await _storage.from(bucketIdOf(bucket)).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(upsert: upsert, contentType: contentType),
          );
      return UploadedFile(
        bucket: bucket,
        path: path,
        contentType: contentType,
        sizeInBytes: bytes.length,
        updatedAt: DateTime.now().toUtc(),
      );
    });
  }

  @override
  Future<BackendResult<Uint8List>> download({
    required StorageBucket bucket,
    required String path,
  }) {
    return _guard<Uint8List>('download', () async {
      return _storage.from(bucketIdOf(bucket)).download(path);
    });
  }

  @override
  Future<BackendResult<String>> publicUrl({
    required StorageBucket bucket,
    required String path,
  }) {
    return _guard<String>('publicUrl', () async {
      // `getPublicUrl` is synchronous and never fails, so the only way to report
      // a problem is a bad bucket mapping, which is a configuration error.
      return _storage.from(bucketIdOf(bucket)).getPublicUrl(path);
    });
  }

  @override
  Future<BackendResult<SignedFileUrl>> createSignedUrl({
    required StorageBucket bucket,
    required String path,
    required int expiresInSeconds,
  }) {
    return _guard<SignedFileUrl>('createSignedUrl', () async {
      final url = await _storage
          .from(bucketIdOf(bucket))
          .createSignedUrl(path, expiresInSeconds);
      return SignedFileUrl(
        bucket: bucket,
        path: path,
        url: url,
        expiresAt: DateTime.now().add(Duration(seconds: expiresInSeconds)),
      );
    });
  }

  @override
  Future<BackendResult<void>> deleteFile({
    required StorageBucket bucket,
    required String path,
  }) {
    return _guard<void>('deleteFile', () async {
      final removed =
          await _storage.from(bucketIdOf(bucket)).remove(<String>[path]);
      if (removed.isEmpty) {
        // Removing a missing object is a `notFound` failure, so a typo cannot
        // look like a successful cleanup.
        throw BackendErrorClassifier.build(
          type: BackendErrorType.notFound,
          message: 'No object was deleted from the ${bucket.key} bucket.',
        );
      }
    });
  }

  @override
  Future<BackendResult<UploadedFile>> moveFile(MoveFileRequest request) {
    return _guard<UploadedFile>('moveFile', () async {
      final destination = _storage.from(
        bucketIdOf(request.toBucket ?? request.fromBucket),
      );
      await destination.move(request.fromPath, request.toPath);
      return UploadedFile(
        bucket: request.toBucket ?? request.fromBucket,
        path: request.toPath,
        contentType: _unknownContentType,
        sizeInBytes: 0,
        updatedAt: DateTime.now().toUtc(),
      );
    });
  }

  @override
  Future<BackendResult<UploadedFile>> copyFile(CopyFileRequest request) {
    return _guard<UploadedFile>('copyFile', () async {
      final destination = _storage.from(
        bucketIdOf(request.toBucket ?? request.fromBucket),
      );
      await destination.copy(request.fromPath, request.toPath);
      // The destination size and type are unknown without a second round trip;
      // callers that need them should `download` or list the bucket.
      return UploadedFile(
        bucket: request.toBucket ?? request.fromBucket,
        path: request.toPath,
        contentType: _unknownContentType,
        sizeInBytes: 0,
        updatedAt: DateTime.now().toUtc(),
      );
    });
  }

  @override
  Future<BackendResult<List<StorageFileEntry>>> listFiles(
    ListFilesRequest request,
  ) {
    return _guard<List<StorageFileEntry>>('listFiles', () async {
      final objects = await _storage.from(bucketIdOf(request.bucket)).list(
            path: request.prefix.isEmpty ? null : request.prefix,
            searchOptions: SearchOptions(
              limit: request.limit,
              offset: request.offset,
            ),
          );
      return List<StorageFileEntry>.unmodifiable(
        objects.map(
          (object) => StorageFileEntry(
            path: object.name,
            bucket: request.bucket,
            sizeInBytes: object.metadata?['size'] is num
                ? (object.metadata!['size']! as num).toInt()
                : null,
            contentType: object.metadata?['mimetype'] as String?,
            updatedAt: SupabaseMappers.parseTimestamp(object.updatedAt),
          ),
        ),
      );
    });
  }

  @override
  Future<void> dispose() async {
    // Supabase Storage holds no per-client resources that the SDK owns; the
    // shared client is disposed by the provider.
  }

  /// Content type used when a move or copy does not report one.
  static const String _unknownContentType = 'application/octet-stream';

  Future<BackendResult<T>> _guard<T>(
    String operation,
    Future<T> Function() action,
  ) async {
    try {
      return BackendSuccess<T>(await action());
    } on BackendFailure catch (failure) {
      return BackendFailureResult<T>(error: failure);
    } catch (error, stackTrace) {
      return BackendFailureResult<T>(
        error: _errorMapper.map(
          error,
          stackTrace,
          fallbackType: BackendErrorType.storage,
          context: {'operation': 'storage.$operation'},
        ),
      );
    }
  }
}
