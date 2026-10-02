import 'dart:typed_data';

import '../result/backend_result.dart';
import '../storage/storage_bucket.dart';
import '../storage/storage_requests.dart';
import '../storage/uploaded_file.dart';

/// The provider-facing file storage contract.
///
/// A provider maps [StorageBucket] values onto its own bucket identifiers and
/// performs the transfers. It never returns a vendor file object: results are
/// always typed SDK types.
abstract interface class StorageBackend {
  /// Uploads [bytes] to `bucket/path`.
  Future<BackendResult<UploadedFile>> upload({
    required StorageBucket bucket,
    required String path,
    required Uint8List bytes,
    required String contentType,
    required bool upsert,
  });

  /// Downloads the object at `bucket/path`.
  Future<BackendResult<Uint8List>> download({
    required StorageBucket bucket,
    required String path,
  });

  /// The stable public URL of an object in a public bucket.
  Future<BackendResult<String>> publicUrl({
    required StorageBucket bucket,
    required String path,
  });

  /// Creates a time-limited signed URL for a private object.
  Future<BackendResult<SignedFileUrl>> createSignedUrl({
    required StorageBucket bucket,
    required String path,
    required int expiresInSeconds,
  });

  /// Deletes the object at `bucket/path`.
  Future<BackendResult<void>> deleteFile({
    required StorageBucket bucket,
    required String path,
  });

  /// Moves an object.
  Future<BackendResult<UploadedFile>> moveFile(MoveFileRequest request);

  /// Copies an object.
  Future<BackendResult<UploadedFile>> copyFile(CopyFileRequest request);

  /// Lists objects under a prefix.
  Future<BackendResult<List<StorageFileEntry>>> listFiles(
    ListFilesRequest request,
  );

  /// Releases provider resources held for storage.
  Future<void> dispose();
}
