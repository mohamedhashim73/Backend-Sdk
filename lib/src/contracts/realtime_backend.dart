import '../contracts/data_backend.dart';
import '../core/backend_resource.dart';
import '../errors/backend_failure.dart';
import '../realtime/realtime_event.dart';

/// The provider-facing realtime contract.
///
/// A provider owns its channel lifecycle - subscribe, rejoin after a dropped
/// socket, and cleanup - and pushes typed [RealtimeEvent] values into a stream.
/// The provider must not surface transport errors as stream errors; it reports
/// them through [RealtimeBackend.lastFailure] and keeps the stream open, because
/// an app-wide crash from a background socket is unacceptable.
abstract interface class RealtimeBackend {
  /// Opens a change stream for [resource] matching [filters].
  ///
  /// `onEvent` is invoked for every change.
  ///
  /// The returned future completes once the channel is established or has
  /// definitively failed.
  Future<void> subscribe({
    required BackendResource resource,
    required Map<String, Object?> filters,
    required void Function(RealtimeEvent<BackendRecord> event) onEvent,
  });

  /// The most recent transport or mapping failure, or `null`.
  BackendFailure? get lastFailure;

  /// Closes the channel for [resource] and [filters].
  ///
  /// Must be idempotent: closing an unknown or already-closed channel is a
  /// no-op rather than an error.
  Future<void> unsubscribe({
    required BackendResource resource,
    required Map<String, Object?> filters,
  });

  /// Closes every channel this backend holds.
  Future<void> dispose();
}
