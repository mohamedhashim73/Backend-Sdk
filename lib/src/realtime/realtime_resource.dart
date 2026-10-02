import '../core/backend_resource.dart';
import '../errors/backend_error_mapper.dart';
import '../errors/backend_error_type.dart';
import '../errors/backend_failure.dart';
import '../filters/filter_condition.dart';
import 'realtime_event.dart';

/// A realtime change subscription.///
/// The subscription is a broadcast stream, so several widgets may listen to the
/// same underlying provider channel. Duplicate provider subscriptions are
/// prevented by `RealtimeRepository`, which multiplexes listeners per
/// (resource, filter) pair and tears the channel down when the last listener
/// leaves.
///
/// Every instance is disposable and should be disposed exactly once. Disposal
/// is idempotent, so a `dispose()` in a `State.dispose` override is safe even if
/// the stream was already closed.
abstract interface class RealtimeSubscription<T> {
  /// The resource being watched.
  BackendResource get resource;

  /// Whether this subscription is still active.
  bool get isActive;

  /// The typed change events for [resource].
  ///
  /// This is a broadcast stream, so several listeners may attach to one
  /// subscription. It never emits errors: a transport problem surfaces through
  /// [lastFailure] while the stream stays open, so a listener can never crash
  /// the app.
  Stream<RealtimeEvent<T>> get events;

  /// Completes when the underlying provider channel is established, or has
  /// definitively failed.
  ///
  /// Await this to drive a "connecting" indicator, and then read [lastFailure]
  /// to decide whether to show an error. Listening to [events] does not require
  /// awaiting it first; events that arrive in the meantime are buffered by the
  /// underlying controller.
  Future<void> get ready;

  /// The most recent failure, or `null` when the subscription is healthy.
  ///
  /// Transport problems never appear as stream errors; they surface here so the
  /// UI can show a "reconnecting" hint while the provider reconnects.
  BackendFailure? get lastFailure;

  /// Closes the subscription and releases the underlying provider channel.
  Future<void> dispose();
}

/// A description of what to watch.
class RealtimeResource {
  /// The resource to watch.
  final BackendResource resource;

  /// Additional typed equality filters applied to the change stream, for
  /// example "only rows whose categoryId equals X".
  ///
  /// Values are passed as query parameters, never interpolated into a query
  /// string.
  final Map<String, Object?> filters;

  /// The channel name used for this subscription.
  ///
  /// Derived deterministically from the resource and filters so two identical
  /// watchers share one channel instead of opening a second one.
  final String channelName;

  /// Creates a realtime resource descriptor.
  RealtimeResource({
    required this.resource,
    this.filters = const {},
  }) : channelName = _deriveName(resource, filters);

  static String _deriveName(BackendResource resource, Map<String, Object?> f) {
    final buffer = StringBuffer('backend_sdk:${resource.name}');
    final keys = f.keys.toList()..sort();
    for (final key in keys) {
      buffer.write(':$key=${f[key]}');
    }
    return buffer.toString();
  }

  /// Validates the filters of this descriptor.
  ///
  /// Returns `null` when the descriptor is safe to use, otherwise a
  /// developer-facing description of the problem. Field names go through the
  /// same strict identifier check used by data filters, so a watch filter can
  /// never inject query syntax.
  static BackendFailure? validate(Map<String, Object?> filters) {
    for (final entry in filters.entries) {
      final error = FilterFieldValidator.validateFieldName(entry.key);
      if (error != null) {
        return BackendErrorClassifier.build(
          type: BackendErrorType.validation,
          message: error,
        );
      }
      final value = entry.value;
      if (value != null &&
          value is! String &&
          value is! num &&
          value is! bool &&
          value is! DateTime) {
        return BackendErrorClassifier.build(
          type: BackendErrorType.validation,
          message: 'The realtime filter "${entry.key}" has an unsupported '
              'value type ${value.runtimeType}.',
        );
      }
    }
    return null;
  }

  @override
  String toString() => 'RealtimeResource($channelName)';
}
