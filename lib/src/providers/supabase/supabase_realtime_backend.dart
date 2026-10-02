import 'dart:async';

import 'package:supabase/supabase.dart'
    show
        PostgresChangeEvent,
        PostgresChangeFilter,
        PostgresChangeFilterType,
        RealtimeChannel,
        RealtimeSubscribeStatus,
        SupabaseClient;

import '../../contracts/data_backend.dart';
import '../../contracts/realtime_backend.dart';
import '../../core/backend_resource.dart';
import '../../errors/backend_error_type.dart';
import '../../errors/backend_failure.dart';
import '../../realtime/realtime_event.dart';
import '../../realtime/realtime_resource.dart';
import 'supabase_error_mapper.dart';
import 'supabase_mappers.dart';

/// Adapts Supabase Realtime to the `RealtimeBackend` contract.
///
/// Channel names, filters, and the payload shape are all handled here. The
/// `RealtimeChannel` never leaves this class.
///
/// Two behaviours matter for stability:
///
/// * **Reconnect** is the provider's job. The channel rejoins automatically
///   when the socket reconnects and the stream keeps emitting, so the
///   application does not re-subscribe.
/// * **Errors are values, not exceptions.** A subscribe failure, a channel
///   error or a mapping failure is recorded in [lastFailure] and the stream
///   stays open, because a background socket must never crash the app.
class SupabaseRealtimeBackend implements RealtimeBackend {
  final SupabaseClient _client;
  final SupabaseErrorMapper _errorMapper;

  final Map<String, _ActiveChannel> _channels = {};

  BackendFailure? _lastFailure;

  /// Creates the adapter over [client].
  SupabaseRealtimeBackend({
    required SupabaseClient client,
    SupabaseErrorMapper errorMapper = const SupabaseErrorMapper(),
  })  : _client = client,
        _errorMapper = errorMapper;

  @override
  BackendFailure? get lastFailure => _lastFailure;

  @override
  Future<void> subscribe({
    required BackendResource resource,
    required Map<String, Object?> filters,
    required void Function(RealtimeEvent<BackendRecord> event) onEvent,
  }) async {
    final invalid = RealtimeResource.validate(filters);
    if (invalid != null) {
      _lastFailure = invalid;
      throw invalid;
    }

    final descriptor = RealtimeResource(resource: resource, filters: filters);
    final key = descriptor.channelName;

    // Duplicate subscription prevention: an identical descriptor reuses the
    // open channel rather than creating a second one.
    final existing = _channels[key];
    if (existing != null) {
      existing.addListener(onEvent);
      return;
    }

    final active = _ActiveChannel();
    _channels[key] = active;
    active.addListener(onEvent);

    final completer = Completer<void>();
    var settled = false;

    void settle([BackendFailure? failure]) {
      if (settled) return;
      settled = true;
      if (failure != null) {
        _lastFailure = failure;
      } else {
        _lastFailure = null;
      }
      if (!completer.isCompleted) completer.complete();
    }

    final RealtimeChannel channel;
    try {
      channel = _client.channel(key).onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: SupabaseResourceRegistry.schema,
            table: SupabaseResourceRegistry.tableOf(resource),
            filter: _toRealtimeFilter(filters),
            callback: (payload) {
              final event = SupabaseMappers.toRealtimeEvent(
                payload,
                resource: resource,
              );
              if (event == null) return;
              for (final listener in active.listeners) {
                listener(event);
              }
            },
          );
    } on Object catch (error, stackTrace) {
      _channels.remove(key);
      final failure = _errorMapper.map(
        error,
        stackTrace,
        fallbackType: BackendErrorType.realtime,
        context: {'operation': 'realtime.subscribe'},
      );
      settle(failure);
      throw failure;
    }

    channel.subscribe(
      (status, Object? error) {
        switch (status) {
          case RealtimeSubscribeStatus.subscribed:
            settle();
          case RealtimeSubscribeStatus.closed:
            settle();
          case RealtimeSubscribeStatus.timedOut:
            settle(
              _errorMapper.map(
                StateError('Subscribing to $key timed out.'),
                StackTrace.current,
                fallbackType: BackendErrorType.realtime,
              ),
            );
          case RealtimeSubscribeStatus.channelError:
            settle(
              _errorMapper.map(
                error ?? StateError('Realtime channel $key errored.'),
                StackTrace.current,
                fallbackType: BackendErrorType.realtime,
                context: {'operation': 'realtime.subscribe'},
              ),
            );
        }
      },
    );

    active.channel = channel;
    await completer.future;
  }

  @override
  Future<void> unsubscribe({
    required BackendResource resource,
    required Map<String, Object?> filters,
  }) async {
    final key =
        RealtimeResource(resource: resource, filters: filters).channelName;
    final active = _channels.remove(key);
    if (active == null) return;

    final channel = active.channel;
    active.listeners.clear();
    if (channel == null) return;

    try {
      await channel.unsubscribe();
      await _client.removeChannel(channel);
    } on Object catch (error, stackTrace) {
      // Cleanup must be best-effort: a channel that cannot be removed is
      // reported, but never throws into a `dispose()` call.
      _lastFailure = _errorMapper.map(
        error,
        stackTrace,
        fallbackType: BackendErrorType.realtime,
        context: {'operation': 'realtime.unsubscribe'},
      );
    }
  }

  @override
  Future<void> dispose() async {
    final open = _channels.values.toList(growable: false);
    _channels.clear();
    for (final active in open) {
      final channel = active.channel;
      active.listeners.clear();
      if (channel == null) continue;
      try {
        await channel.unsubscribe();
      } on Object catch (error, stackTrace) {
        _lastFailure = _errorMapper.map(
          error,
          stackTrace,
          fallbackType: BackendErrorType.realtime,
          context: {'operation': 'realtime.dispose'},
        );
      }
    }
  }

  /// The number of open channels, exposed for tests and diagnostics.
  int get openChannelCount => _channels.length;

  /// Converts a watch filter map into a PostgREST realtime filter.
  ///
  /// Only equality is expressible as a realtime filter, so a non-equality
  /// filter is rejected rather than silently dropped - a watcher that looks
  /// filtered but is not would deliver rows the caller must not see.
  static PostgresChangeFilter? _toRealtimeFilter(Map<String, Object?> filters) {
    if (filters.isEmpty) return null;
    final entries = filters.entries.toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));
    final first = entries.first;
    return PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: first.key,
      value: first.value,
    );
  }
}

/// The mutable state of one open channel.
class _ActiveChannel {
  final List<void Function(RealtimeEvent<BackendRecord> event)> listeners =
      <void Function(RealtimeEvent<BackendRecord> event)>[];

  RealtimeChannel? channel;

  void addListener(void Function(RealtimeEvent<BackendRecord> event) listener) {
    listeners.add(listener);
  }
}
