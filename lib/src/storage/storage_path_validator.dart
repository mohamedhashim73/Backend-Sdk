import '../errors/backend_error_mapper.dart';
import '../errors/backend_error_type.dart';
import '../errors/backend_failure.dart';
import 'storage_requests.dart';

/// Local validation of object keys, content types and payload sizes.
///
/// Everything here runs on the device before a request is made, which is what
/// keeps a malformed key, a traversal attempt, or an oversized upload from ever
/// reaching the backend.
abstract final class StoragePathValidator {
  /// The largest upload accepted by default, in bytes (10 MiB).
  static const int maxFileSizeInBytes = 10 * 1024 * 1024;

  /// The largest object key length accepted.
  static const int maxPathLength = 512;

  /// The largest number of path segments accepted.
  static const int maxSegments = 12;

  /// The minimum length of a file name (excluding extension).
  static const int minSegmentLength = 1;

  /// Characters allowed in a path segment, excluding `/`.
  ///
  /// Deliberately narrow: letters, digits, `_`, `-`, `.` and spaces. Anything
  /// that could be interpreted as path syntax or a header delimiter is
  /// rejected, so a key can never escape its prefix.
  static final RegExp segmentPattern = RegExp(r'^[A-Za-z0-9._\- ]+$');

  /// Returns a validation failure for an unsafe or malformed [path], or `null`.
  ///
  /// Rejects absolute paths, `..` traversal, empty segments, backslashes,
  /// control characters, query/fragment markers, and over-long keys.
  static BackendFailure? validatePath(String path,
      {required String operation}) {
    if (path.isEmpty) {
      return _failure('The file path must not be empty.');
    }
    if (path.length > maxPathLength) {
      return _failure(
        'The file path must not exceed $maxPathLength characters.',
      );
    }
    if (path.startsWith('/') || path.startsWith('\\')) {
      return _failure('The file path must be relative to the bucket root.');
    }
    if (path.contains('\\')) {
      return _failure('The file path must use "/" as its separator.');
    }
    if (path.contains('//')) {
      return _failure('The file path must not contain empty segments.');
    }
    if (path.contains('?') || path.contains('#')) {
      return _failure(
        'The file path must not contain "?" or "#" characters.',
      );
    }
    if (RegExp(r'[\u0000-\u001F\u007F]').hasMatch(path)) {
      return _failure(
        'The file path must not contain control characters.',
      );
    }
    final segments = path.split('/');
    if (segments.length > maxSegments) {
      return _failure(
        'The file path must not contain more than $maxSegments segments.',
      );
    }
    for (final segment in segments) {
      if (segment.length < minSegmentLength) {
        return _failure('The file path must not contain empty segments.');
      }
      if (segment == '.' || segment == '..') {
        return _failure(
          'The file path must not contain "." or ".." segments.',
        );
      }
      if (!segmentPattern.hasMatch(segment)) {
        return _failure(
          'The path segment "$segment" contains unsupported characters. Use '
          'letters, digits, ".", "_", "-" and spaces only.',
        );
      }
    }
    return null;
  }

  /// Returns a validation failure for an invalid [contentType], or `null`.
  ///
  /// The content type is sent as a header value, so it must match a strict
  /// `type/subtype` shape. This is what prevents header injection through a
  /// user-controlled MIME string.
  static BackendFailure? validateContentType(String contentType) {
    if (contentType.isEmpty) {
      return _failure('A content type is required.');
    }
    if (contentType.length > 128) {
      return _failure('The content type is too long.');
    }
    final match = RegExp(
      r'^([A-Za-z0-9][A-Za-z0-9!#$&^_.+-]{0,62})/'
      r'([A-Za-z0-9][A-Za-z0-9!#$&^_.+-]{0,62})$',
    ).firstMatch(contentType);
    if (match == null) {
      return _failure(
        'The content type "$contentType" is not a valid MIME type.',
      );
    }
    return null;
  }

  /// Returns a validation failure for an empty or oversized payload, or `null`.
  static BackendFailure? validateSize(
    List<int> bytes, {
    int maxBytes = maxFileSizeInBytes,
  }) {
    if (bytes.isEmpty) {
      return _failure('The file must not be empty.');
    }
    if (bytes.length > maxBytes) {
      return _failure(
        'The file is ${bytes.length} bytes, which exceeds the $maxBytes byte '
        'limit.',
      );
    }
    return null;
  }

  /// Returns a validation failure for an out-of-range signed-URL lifetime, or
  /// `null`.
  ///
  /// The lifetime is bounded at both ends: a very short value causes constant
  /// re-signing, and an unbounded value turns a temporary link into a permanent
  /// public URL for a private file.
  static BackendFailure? validateExpirySeconds(int expiresIn) {
    if (expiresIn < minSignedUrlSeconds) {
      return _failure(
        'A signed URL must remain valid for at least $minSignedUrlSeconds '
        'seconds.',
      );
    }
    if (expiresIn > maxSignedUrlSeconds) {
      return _failure(
        'A signed URL must not remain valid for more than $maxSignedUrlSeconds '
        'seconds.',
      );
    }
    return null;
  }

  /// The default signed-URL lifetime used when none is supplied.
  static const int defaultSignedUrlSeconds = 300;

  /// The shortest accepted signed-URL lifetime.
  static const int minSignedUrlSeconds = 10;

  /// The longest accepted signed-URL lifetime (7 days).
  static const int maxSignedUrlSeconds = 604800;

  /// The largest number of entries a listing may return.
  static const int maxListLimit = 1000;

  /// Returns a validation failure for a listing [request], or `null`.
  static BackendFailure? validateListRequest(ListFilesRequest request) {
    if (request.limit < 1 || request.limit > maxListLimit) {
      return _failure(
        'The list limit must be between 1 and $maxListLimit.',
      );
    }
    if (request.offset < 0) {
      return _failure('The list offset must not be negative.');
    }
    // An empty prefix legitimately means "the whole bucket", so it is the one
    // case where validatePath would be too strict.
    if (request.prefix.isEmpty) return null;
    return validatePath(request.prefix, operation: 'list');
  }

  static BackendFailure _failure(String message) {
    return BackendErrorClassifier.build(
      type: BackendErrorType.validation,
      message: message,
    );
  }
}
