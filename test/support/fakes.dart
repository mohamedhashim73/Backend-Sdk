import 'dart:async';
import 'dart:typed_data';

import 'package:backend_sdk/src/auth/auth_session.dart';
import 'package:backend_sdk/src/auth/auth_state.dart';
import 'package:backend_sdk/src/auth/auth_user.dart';
import 'package:backend_sdk/src/contracts/auth_backend.dart';
import 'package:backend_sdk/src/contracts/data_backend.dart';
import 'package:backend_sdk/src/contracts/realtime_backend.dart';
import 'package:backend_sdk/src/contracts/storage_backend.dart';
import 'package:backend_sdk/src/core/backend_resource.dart';
import 'package:backend_sdk/src/errors/backend_error_mapper.dart';
import 'package:backend_sdk/src/errors/backend_error_type.dart';
import 'package:backend_sdk/src/errors/backend_failure.dart';
import 'package:backend_sdk/src/realtime/realtime_event.dart';
import 'package:backend_sdk/src/result/backend_result.dart';
import 'package:backend_sdk/src/storage/storage_bucket.dart';
import 'package:backend_sdk/src/storage/storage_requests.dart';
import 'package:backend_sdk/src/storage/uploaded_file.dart';

/// A throwable carrier for a value that is not an `Exception`.
///
/// Fakes arm themselves with a failure to raise; wrapping it keeps the
/// `only_throw_errors` lint satisfied without changing what is raised.
class ArmedFailure implements Exception {
  /// Creates a carrier.
  const ArmedFailure(this.value);

  /// The armed value.
  final Object value;

  @override
  String toString() => 'ArmedFailure($value)';
}

/// Wraps [value] in a successful result.
BackendResult<T> success<T>(T value) => BackendSuccess<T>(value);

/// Wraps [failure] in a failed result.
BackendResult<T> fail<T>(BackendFailure failure) {
  return BackendFailureResult<T>(error: failure);
}

/// A scripted [AuthBackend] for auth tests.
class FakeAuthBackend implements AuthBackend {
  /// The session returned by [login] and [signUp].
  BackendSession session = const BackendSession(
    accessToken: 'fake-access-token',
    user: BackendUser(id: 'user-1', email: 'user@example.com'),
  );

  /// A failure returned instead of a session, when set.
  BackendFailure? failure;

  /// A failure for the next call only.
  BackendFailure? nextFailure;

  /// The number of times [login] was called.
  int loginCalls = 0;

  /// The number of times [logout] was called.
  int logoutCalls = 0;

  /// The number of times [refreshSession] was called.
  int refreshCalls = 0;

  /// The number of times [dispose] was called.
  int disposeCalls = 0;

  /// Artificial latency, used to exercise timeouts.
  Duration latency = Duration.zero;

  final StreamController<AuthStateChange> _states =
      StreamController<AuthStateChange>.broadcast();

  /// Emits a state change to [authStateChanges] listeners.
  void emit(AuthStateChange change) => _states.add(change);

  /// Emits a stream error, exercising the repository's error handling.
  void emitError(Object error) => _states.addError(error);

  @override
  Future<BackendResult<BackendSession>> signUp({
    required String email,
    required String password,
    Map<String, dynamic> metadata = const {},
    String? emailRedirectTo,
  }) async {
    await _delay();
    return _resolve(session);
  }

  @override
  Future<BackendResult<BackendSession>> login({
    required String email,
    required String password,
  }) async {
    loginCalls++;
    await _delay();
    return _resolve(session);
  }

  @override
  Future<BackendResult<void>> logout() async {
    logoutCalls++;
    await _delay();
    return _resolve(null);
  }

  @override
  Future<BackendResult<BackendSession?>> currentSession() async {
    await _delay();
    return _resolve(session);
  }

  @override
  Future<BackendResult<BackendUser?>> currentUser() async {
    await _delay();
    return _resolve(session.user);
  }

  @override
  Future<BackendResult<BackendSession>> refreshSession() async {
    refreshCalls++;
    await _delay();
    return _resolve(session);
  }

  @override
  Future<BackendResult<void>> requestPasswordReset({
    required String email,
    String? redirectTo,
  }) async {
    await _delay();
    return _resolve(null);
  }

  @override
  Future<BackendResult<BackendUser>> updatePassword({
    required String newPassword,
  }) async {
    await _delay();
    return _resolve(session.user);
  }

  @override
  Future<BackendResult<BackendUser>> updateUserMetadata(
    Map<String, dynamic> metadata,
  ) async {
    await _delay();
    return _resolve(session.user);
  }

  @override
  Future<BackendResult<void>> resendVerificationEmail({
    required String email,
    String? redirectTo,
  }) async {
    await _delay();
    return _resolve(null);
  }

  @override
  Stream<AuthStateChange> get authStateChanges => _states.stream;

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await _states.close();
  }

  BackendResult<T> _resolve<T>(T value) {
    final error = nextFailure ?? failure;
    nextFailure = null;
    if (error != null) return BackendFailureResult<T>(error: error);
    return BackendSuccess<T>(value);
  }

  Future<void> _delay() => latency == Duration.zero
      ? Future<void>.value()
      : Future<void>.delayed(latency);
}

/// An in-memory [StorageBackend] for storage tests.
class FakeStorageBackend implements StorageBackend {
  /// The stored bytes, keyed by `bucket/path`.
  final Map<String, Uint8List> files = <String, Uint8List>{};

  /// The number of times [upload] was called.
  int uploadCalls = 0;

  /// A failure for the next call only.
  BackendFailure? nextFailure;

  /// Artificial latency, used to exercise timeouts.
  Duration latency = Duration.zero;

  String _key(StorageBucket bucket, String path) => '${bucket.key}/$path';

  @override
  Future<BackendResult<UploadedFile>> upload({
    required StorageBucket bucket,
    required String path,
    required Uint8List bytes,
    required String contentType,
    required bool upsert,
  }) async {
    uploadCalls++;
    await _delay();
    final armed = nextFailure;
    nextFailure = null;
    if (armed != null) return BackendFailureResult<UploadedFile>(error: armed);

    final key = _key(bucket, path);
    if (files.containsKey(key) && !upsert) {
      return fail(
        BackendErrorClassifier.build(
          type: BackendErrorType.conflict,
          message: 'An object already exists at $key.',
        ),
      );
    }
    files[key] = bytes;
    return success(
      UploadedFile(
        bucket: bucket,
        path: path,
        contentType: contentType,
        sizeInBytes: bytes.length,
      ),
    );
  }

  @override
  Future<BackendResult<Uint8List>> download({
    required StorageBucket bucket,
    required String path,
  }) async {
    await _delay();
    _throwArmed();
    final bytes = files[_key(bucket, path)];
    if (bytes == null) {
      return fail(
        BackendErrorClassifier.build(
          type: BackendErrorType.notFound,
          message: 'No object at ${bucket.key}/$path.',
        ),
      );
    }
    return success(bytes);
  }

  @override
  Future<BackendResult<String>> publicUrl({
    required StorageBucket bucket,
    required String path,
  }) async {
    await _delay();
    _throwArmed();
    return success('https://cdn.example.com/${bucket.key}/$path');
  }

  @override
  Future<BackendResult<SignedFileUrl>> createSignedUrl({
    required StorageBucket bucket,
    required String path,
    required int expiresInSeconds,
  }) async {
    await _delay();
    _throwArmed();
    return success(
      SignedFileUrl(
        bucket: bucket,
        path: path,
        url: 'https://cdn.example.com/${bucket.key}/$path?token=signed',
        expiresAt: DateTime.now().add(Duration(seconds: expiresInSeconds)),
      ),
    );
  }

  @override
  Future<BackendResult<void>> deleteFile({
    required StorageBucket bucket,
    required String path,
  }) async {
    await _delay();
    _throwArmed();
    if (files.remove(_key(bucket, path)) == null) {
      return fail(
        BackendErrorClassifier.build(
          type: BackendErrorType.notFound,
          message: 'No object at ${bucket.key}/$path.',
        ),
      );
    }
    return success(null);
  }

  @override
  Future<BackendResult<UploadedFile>> moveFile(MoveFileRequest request) async {
    await _delay();
    final bytes = files.remove(
      _key(request.fromBucket, request.fromPath),
    );
    if (bytes == null) {
      return fail(
        BackendErrorClassifier.build(
          type: BackendErrorType.notFound,
          message: 'The source object does not exist.',
        ),
      );
    }
    final bucket = request.toBucket ?? request.fromBucket;
    files[_key(bucket, request.toPath)] = bytes;
    return success(
      UploadedFile(
        bucket: bucket,
        path: request.toPath,
        contentType: 'application/octet-stream',
        sizeInBytes: bytes.length,
      ),
    );
  }

  @override
  Future<BackendResult<UploadedFile>> copyFile(CopyFileRequest request) async {
    await _delay();
    final bytes = files[_key(request.fromBucket, request.fromPath)];
    if (bytes == null) {
      return fail(
        BackendErrorClassifier.build(
          type: BackendErrorType.notFound,
          message: 'The source object does not exist.',
        ),
      );
    }
    final bucket = request.toBucket ?? request.fromBucket;
    files[_key(bucket, request.toPath)] = bytes;
    return success(
      UploadedFile(
        bucket: bucket,
        path: request.toPath,
        contentType: 'application/octet-stream',
        sizeInBytes: bytes.length,
      ),
    );
  }

  @override
  Future<BackendResult<List<StorageFileEntry>>> listFiles(
    ListFilesRequest request,
  ) async {
    await _delay();
    _throwArmed();
    final prefix = request.prefix;
    final entries = files.keys
        .where((key) => key.startsWith('${request.bucket.key}/$prefix'))
        .skip(request.offset)
        .take(request.limit)
        .map(
          (key) => StorageFileEntry(
            bucket: request.bucket,
            path: key.substring('${request.bucket.key}/'.length),
            sizeInBytes: files[key]?.length,
          ),
        )
        .toList();
    return success(entries);
  }

  @override
  Future<void> dispose() async {}

  Future<void> _delay() => latency == Duration.zero
      ? Future<void>.value()
      : Future<void>.delayed(latency);

  /// Throws the armed failure, if any, for the current call only.
  void _throwArmed() {
    final armed = nextFailure;
    nextFailure = null;
    if (armed != null) throw armed;
  }
}

/// An in-memory [RealtimeBackend] that lets a test push events by hand.
class FakeRealtimeBackend implements RealtimeBackend {
  final Map<String, void Function(RealtimeEvent<BackendRecord>)> _listeners =
      <String, void Function(RealtimeEvent<BackendRecord>)>{};

  /// The number of times [subscribe] was invoked.
  int subscribeCalls = 0;

  /// The number of times [unsubscribe] was invoked.
  int unsubscribeCalls = 0;

  /// The number of times [dispose] was invoked.
  int disposeCalls = 0;

  /// A failure to throw from [subscribe], when set.
  BackendFailure? subscribeFailure;

  @override
  BackendFailure? lastFailure;

  @override
  Future<void> subscribe({
    required BackendResource resource,
    required Map<String, Object?> filters,
    required void Function(RealtimeEvent<BackendRecord> event) onEvent,
  }) async {
    subscribeCalls++;
    if (subscribeFailure != null) {
      final failure = subscribeFailure!;
      subscribeFailure = null;
      lastFailure = failure;
      throw failure;
    }
    _listeners[realtimeKey(resource, filters)] = onEvent;
  }

  @override
  Future<void> unsubscribe({
    required BackendResource resource,
    required Map<String, Object?> filters,
  }) async {
    unsubscribeCalls++;
    _listeners.remove(realtimeKey(resource, filters));
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    _listeners.clear();
  }

  /// The number of open channels.
  int get openChannels => _listeners.length;

  /// Pushes a raw provider payload to the matching listener.
  void emit(
    BackendResource resource, {
    required Map<String, dynamic> record,
    Map<String, Object?> filters = const {},
    RealtimeEventType type = RealtimeEventType.inserted,
    BackendRecord? oldRecord,
  }) {
    final listener = _listeners[realtimeKey(resource, filters)];
    final callback = listener;
    if (callback == null) {
      throw StateError('No open channel for ${resource.name}.');
    }
    callback(
      RealtimeEvent<BackendRecord>(
        type: type,
        newData: type == RealtimeEventType.deleted ? null : record,
        oldData: oldRecord,
        committedAt: DateTime(2026, 1, 1),
      ),
    );
  }

  static String realtimeKey(
    BackendResource resource,
    Map<String, Object?> filters,
  ) {
    final keys = filters.keys.toList()..sort();
    return [
      resource.name,
      for (final key in keys) '$key=${filters[key]}',
    ].join('|');
  }
}
