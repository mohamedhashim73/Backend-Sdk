import 'storage_bucket.dart';

/// A file that has been stored in a bucket.
class UploadedFile {
  /// The bucket the file lives in.
  final StorageBucket bucket;

  /// The object key inside the bucket.
  final String path;

  /// The MIME content type recorded for the file.
  final String contentType;

  /// The size of the stored file in bytes.
  final int sizeInBytes;

  /// When the file was created or last replaced.
  final DateTime? updatedAt;

  /// Creates an uploaded file descriptor.
  const UploadedFile({
    required this.bucket,
    required this.path,
    required this.contentType,
    required this.sizeInBytes,
    this.updatedAt,
  });

  @override
  String toString() => 'UploadedFile(bucket: ${bucket.key}, path: $path, '
      'sizeInBytes: $sizeInBytes)';
}
