import 'storage_bucket.dart';

/// A request to move an object to a new key, optionally in a new bucket.
class MoveFileRequest {
  /// The bucket the object currently lives in.
  final StorageBucket fromBucket;

  /// The current object key.
  final String fromPath;

  /// The destination bucket. Defaults to [fromBucket].
  final StorageBucket? toBucket;

  /// The destination object key.
  final String toPath;

  /// Creates a move request.
  const MoveFileRequest({
    required this.fromBucket,
    required this.fromPath,
    required this.toPath,
    this.toBucket,
  });

  @override
  String toString() => 'MoveFileRequest(from: ${fromBucket.key}/$fromPath, '
      'to: ${toBucket?.key ?? fromBucket.key}/$toPath)';
}

/// A request to copy an object to a new key, optionally in a new bucket.
class CopyFileRequest {
  /// The bucket the object currently lives in.
  final StorageBucket fromBucket;

  /// The current object key.
  final String fromPath;

  /// The destination bucket. Defaults to [fromBucket].
  final StorageBucket? toBucket;

  /// The destination object key.
  final String toPath;

  /// Creates a copy request.
  const CopyFileRequest({
    required this.fromBucket,
    required this.fromPath,
    required this.toPath,
    this.toBucket,
  });

  @override
  String toString() => 'CopyFileRequest(from: ${fromBucket.key}/$fromPath, '
      'to: ${toBucket?.key ?? fromBucket.key}/$toPath)';
}

/// A request to list objects under a prefix.
class ListFilesRequest {
  /// The bucket to list.
  final StorageBucket bucket;

  /// The key prefix to list under. Use an empty string for the whole bucket.
  final String prefix;

  /// The maximum number of entries to return.
  final int limit;

  /// The number of entries to skip.
  final int offset;

  /// Creates a list request.
  const ListFilesRequest({
    required this.bucket,
    this.prefix = '',
    this.limit = 100,
    this.offset = 0,
  });

  @override
  String toString() =>
      'ListFilesRequest(bucket: ${bucket.key}, prefix: $prefix, '
      'limit: $limit, offset: $offset)';
}

/// A time-limited, signed reference to a private object.
///
/// The URL carries an embedded signature. Treat it as a credential: never log
/// it, never persist it, and request a short lifetime unless the file truly
/// needs to stay reachable.
class SignedFileUrl {
  /// The bucket the object lives in.
  final StorageBucket bucket;

  /// The object key the URL points at.
  final String path;

  /// The signed URL.
  final String url;

  /// When the signature stops being valid.
  final DateTime expiresAt;

  /// Creates a signed URL descriptor.
  const SignedFileUrl({
    required this.bucket,
    required this.path,
    required this.url,
    required this.expiresAt,
  });

  /// Whether the signature has expired relative to [now].
  bool isExpired({DateTime? now}) => expiresAt.isBefore(now ?? DateTime.now());

  @override
  String toString() {
    // The URL is intentionally omitted: it is a bearer credential.
    return 'SignedFileUrl(bucket: ${bucket.key}, path: $path, '
        'expiresAt: $expiresAt)';
  }
}
