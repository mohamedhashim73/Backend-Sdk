import 'dart:typed_data';

import '../contracts/storage_backend.dart';
import '../core/backend_logger.dart';
import '../errors/backend_error_mapper.dart';
import '../errors/backend_error_type.dart';
import '../result/backend_result.dart';
import '../retry/cancellation_token.dart';
import '../retry/request_executor.dart';
import 'storage_bucket.dart';
import 'storage_path_validator.dart';
import 'storage_requests.dart';
import 'upload_file_request.dart';
import 'uploaded_file.dart';

/// The complete, provider-agnostic file storage API.
///
/// Path validation, content-type validation, size limits, typed error mapping
/// and retries all live here or below, so an application never manipulates a
/// raw URL, a vendor file handle, or a provider exception.
///
/// ```dart
/// final result = await BackendSdk.instance.storage.upload(
///   request: UploadFileRequest(
///     bucket: StorageBucket.products,
///     path: 'products/$productId/image.jpg',
///     bytes: bytes,
///     contentType: 'image/jpeg',
///   ),
/// );
/// result.when(
///   success: (file) => showPath(file.path),
///   failure: (failure) => showMessage(failure.safeMessage),
/// );
/// ```
class StorageRepository {
  final StorageBackend _backend;
  final RequestExecutor _executor;
  final BackendLogger _logger;

  /// The largest upload this repository accepts, in bytes.
  final int maxFileSizeInBytes;

  /// Creates a storage repository over [backend].
  StorageRepository({
    required StorageBackend backend,
    required RequestExecutor executor,
    BackendLogger logger = const NoopBackendLogger(),
    this.maxFileSizeInBytes = StoragePathValidator.maxFileSizeInBytes,
  })  : _backend = backend,
        _executor = executor,
        _logger = logger;

  /// Uploads in-memory bytes to [request].
  ///
  /// The path, content type and size are validated locally first, so a rejected
  /// upload never reaches the network. Re-uploading to an existing path fails
  /// with a `conflict` unless `UploadFileRequest.upsert` is `true`.
  Future<BackendResult<UploadedFile>> upload({
    required UploadFileRequest request,
    CancellationToken? cancellationToken,
  }) async {
    final invalid = StoragePathValidator.validatePath(
          request.path,
          operation: 'upload',
        ) ??
        StoragePathValidator.validateContentType(request.contentType) ??
        StoragePathValidator.validateSize(
          request.bytes,
          maxBytes: maxFileSizeInBytes,
        );
    if (invalid != null) {
      return failureOf(invalid);
    }

    _logger.debug(
      'Uploading file.',
      context: {
        'bucket': request.bucket.key,
        'path': request.path,
        'bytes': request.bytes.length,
      },
    );

    return _executor.run<UploadedFile>(
      operation: 'storage.upload',
      fallbackErrorType: BackendErrorType.storage,
      cancellationToken: cancellationToken,
      action: () async => unwrap(
        await _backend.upload(
          bucket: request.bucket,
          path: request.path,
          bytes: Uint8List.fromList(request.bytes),
          contentType: request.contentType,
          upsert: request.upsert,
        ),
      ),
    );
  }

  /// Downloads the object at `bucket/path` as bytes.
  Future<BackendResult<Uint8List>> download({
    required StorageBucket bucket,
    required String path,
    CancellationToken? cancellationToken,
  }) async {
    final invalid =
        StoragePathValidator.validatePath(path, operation: 'download');
    if (invalid != null) {
      return failureOf(invalid);
    }

    return _executor.run<Uint8List>(
      operation: 'storage.download',
      fallbackErrorType: BackendErrorType.storage,
      cancellationToken: cancellationToken,
      action: () async => unwrap(
        await _backend.download(bucket: bucket, path: path),
      ),
    );
  }

  /// The stable public URL of an object.
  ///
  /// Only meaningful for public buckets. For private content use
  /// [createSignedUrl] instead - a public URL for a private bucket leaks the
  /// object's existence and will fail at read time.
  Future<BackendResult<String>> getPublicUrl({
    required StorageBucket bucket,
    required String path,
    CancellationToken? cancellationToken,
  }) async {
    final invalid =
        StoragePathValidator.validatePath(path, operation: 'publicUrl');
    if (invalid != null) {
      return failureOf(invalid);
    }

    return _executor.run<String>(
      operation: 'storage.publicUrl',
      fallbackErrorType: BackendErrorType.storage,
      cancellationToken: cancellationToken,
      action: () async =>
          unwrap(await _backend.publicUrl(bucket: bucket, path: path)),
    );
  }

  /// Creates a time-limited signed URL for a private object.
  ///
  /// [expiresIn] defaults to five minutes and is capped at seven days. The
  /// returned URL embeds a signature, so treat it as a credential: the SDK
  /// never logs it, and `SignedFileUrl.toString` omits it.
  Future<BackendResult<SignedFileUrl>> createSignedUrl({
    required StorageBucket bucket,
    required String path,
    int expiresIn = StoragePathValidator.defaultSignedUrlSeconds,
    CancellationToken? cancellationToken,
  }) async {
    final invalid =
        StoragePathValidator.validatePath(path, operation: 'signedUrl') ??
            StoragePathValidator.validateExpirySeconds(expiresIn);
    if (invalid != null) {
      return failureOf(invalid);
    }

    return _executor.run<SignedFileUrl>(
      operation: 'storage.createSignedUrl',
      fallbackErrorType: BackendErrorType.storage,
      cancellationToken: cancellationToken,
      action: () async => unwrap(
        await _backend.createSignedUrl(
          bucket: bucket,
          path: path,
          expiresInSeconds: expiresIn,
        ),
      ),
    );
  }

  /// Deletes the object at `bucket/path`.
  ///
  /// Deleting a missing object is reported as a `notFound` failure rather than
  /// silently succeeding, so a typo in a path cannot look like a successful
  /// cleanup.
  Future<BackendResult<void>> deleteFile({
    required StorageBucket bucket,
    required String path,
    CancellationToken? cancellationToken,
  }) async {
    final invalid =
        StoragePathValidator.validatePath(path, operation: 'delete');
    if (invalid != null) {
      return failureOf(invalid);
    }

    return _executor.run<void>(
      operation: 'storage.delete',
      fallbackErrorType: BackendErrorType.storage,
      cancellationToken: cancellationToken,
      action: () async =>
          unwrap(await _backend.deleteFile(bucket: bucket, path: path)),
    );
  }

  /// Moves an object to a new key and/or bucket.
  Future<BackendResult<UploadedFile>> moveFile({
    required MoveFileRequest request,
    CancellationToken? cancellationToken,
  }) async {
    final invalid = StoragePathValidator.validatePath(
          request.fromPath,
          operation: 'move.from',
        ) ??
        StoragePathValidator.validatePath(
          request.toPath,
          operation: 'move.to',
        );
    if (invalid != null) {
      return failureOf(invalid);
    }
    if (request.fromPath == request.toPath &&
        (request.toBucket ?? request.fromBucket) == request.fromBucket) {
      return failureOf(
        BackendErrorClassifier.build(
          type: BackendErrorType.validation,
          message: 'The source and destination of a move must differ.',
        ),
      );
    }

    return _executor.run<UploadedFile>(
      operation: 'storage.move',
      fallbackErrorType: BackendErrorType.storage,
      cancellationToken: cancellationToken,
      action: () async => unwrap(await _backend.moveFile(request)),
    );
  }

  /// Copies an object to a new key and/or bucket.
  Future<BackendResult<UploadedFile>> copyFile({
    required CopyFileRequest request,
    CancellationToken? cancellationToken,
  }) async {
    final invalid = StoragePathValidator.validatePath(
          request.fromPath,
          operation: 'copy.from',
        ) ??
        StoragePathValidator.validatePath(
          request.toPath,
          operation: 'copy.to',
        );
    if (invalid != null) {
      return failureOf(invalid);
    }
    if (request.fromPath == request.toPath &&
        (request.toBucket ?? request.fromBucket) == request.fromBucket) {
      return failureOf(
        BackendErrorClassifier.build(
          type: BackendErrorType.validation,
          message: 'The source and destination of a copy must differ.',
        ),
      );
    }

    return _executor.run<UploadedFile>(
      operation: 'storage.copy',
      fallbackErrorType: BackendErrorType.storage,
      cancellationToken: cancellationToken,
      action: () async => unwrap(await _backend.copyFile(request)),
    );
  }

  /// Lists objects under a prefix in [ListFilesRequest.bucket].
  ///
  /// The result is bounded by `ListFilesRequest.limit`, which the repository
  /// validates, so a listing can never become an unbounded download.
  Future<BackendResult<List<StorageFileEntry>>> listFiles({
    required ListFilesRequest request,
    CancellationToken? cancellationToken,
  }) async {
    final invalid = StoragePathValidator.validateListRequest(request);
    if (invalid != null) {
      return failureOf(invalid);
    }

    final result = await _executor.run<List<StorageFileEntry>>(
      operation: 'storage.list',
      fallbackErrorType: BackendErrorType.storage,
      cancellationToken: cancellationToken,
      action: () async => unwrap(await _backend.listFiles(request)),
    );

    return result.map(
      (entries) =>
          List<StorageFileEntry>.unmodifiable(entries.take(request.limit)),
    );
  }

  /// Releases provider resources held for storage.
  Future<void> dispose() => _backend.dispose();
}
