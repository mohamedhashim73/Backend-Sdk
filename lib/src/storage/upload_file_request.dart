import 'storage_bucket.dart';

/// A request to upload in-memory bytes to a bucket.
class UploadFileRequest {
  /// The destination bucket.
  final StorageBucket bucket;

  /// The object key inside the bucket.
  ///
  /// Must be a validated relative path. See `StoragePathValidator` for the
  /// accepted shape.
  final String path;

  /// The file contents.
  final List<int> bytes;

  /// The MIME content type, for example `image/jpeg`.
  final String contentType;

  /// Whether an existing object at [path] may be overwritten.
  ///
  /// `false` makes an upload to an existing path fail with a `conflict`
  /// failure, which is the safer default.
  final bool upsert;

  /// Creates an upload request.
  const UploadFileRequest({
    required this.bucket,
    required this.path,
    required this.bytes,
    required this.contentType,
    this.upsert = false,
  });

  @override
  String toString() {
    // The byte contents are intentionally omitted.
    return 'UploadFileRequest(bucket: ${bucket.key}, path: $path, '
        'bytes: ${bytes.length}, contentType: $contentType, upsert: $upsert)';
  }
}
