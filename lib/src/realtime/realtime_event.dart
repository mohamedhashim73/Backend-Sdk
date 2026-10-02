/// The kind of change that produced a `RealtimeEvent`.
enum RealtimeEventType {
  /// A new record was created.
  inserted,

  /// An existing record was changed.
  updated,

  /// A record was removed.
  deleted,
}

/// A typed realtime change for a single resource.
///
/// Both [oldData] and [newData] are the application's own model, never a raw
/// provider payload:
///
/// * [RealtimeEventType.inserted] - [newData] is set.
/// * [RealtimeEventType.updated] - [newData] is set; [oldData] is present only
///   when the provider reports the previous row.
/// * [RealtimeEventType.deleted] - [oldData] is set.
///
/// A payload that cannot be mapped is not emitted at all; the repository logs
/// the mapping error and keeps the stream open, because a single malformed row
/// must not tear down a live subscription.
class RealtimeEvent<T> {
  /// What happened.
  final RealtimeEventType type;

  /// The record before the change, when the provider reports it.
  final T? oldData;

  /// The record after the change.
  ///
  /// `null` for a delete, and `null` when an update payload could not be
  /// mapped.
  final T? newData;

  /// When the change was committed by the database.
  final DateTime? committedAt;

  /// Creates a realtime event.
  const RealtimeEvent({
    required this.type,
    this.oldData,
    this.newData,
    this.committedAt,
  });

  /// Whether this event carries [newData].
  bool get hasNewData => newData != null;

  /// Whether this event carries [oldData].
  bool get hasOldData => oldData != null;

  @override
  String toString() {
    return 'RealtimeEvent<$T>(type: ${type.name}, '
        'hasOld: $hasOldData, hasNew: $hasNewData)';
  }
}
