import 'dart:async';

import '../contracts/data_backend.dart';
import '../contracts/realtime_backend.dart';
import '../core/backend_logger.dart';
import '../core/backend_resource.dart';
import '../errors/backend_error_mapper.dart';
import '../errors/backend_error_type.dart';
import '../errors/backend_failure.dart';
import 'realtime_event.dart';
import 'realtime_resource.dart';

/// The signature used to turn a provider record into an application model.
///
/// Returning `null` means the record could not be mapped. The repository logs
/// that and skips the event instead of emitting a broken value or tearing down
/// the live subscription.
typedef RealtimeDecoder<T> = T? Function(Map<String, dynamic> record);

/// The provider-agnostic realtime API.
///
/// `watch` returns a [RealtimeSubscription] that yields typed [RealtimeEvent]s.
/// Duplicate subscriptions are prevented: two watchers with the same resource
/// and filters share one provider channel, and the channel is torn down when the
/// last of them disposes.
///
/// ```dart
/// final watcher = BackendSdk.instance.realtime.watch<Product>(
///   resource: BackendResource.products,
/// );
///
/// final subscription = await watcher.ready;
/// await for (final event in watcher.events) {
///   switch (event.type) {
///     case RealtimeEventType.inserted:
///     case RealtimeEventType.updated:
///       apply(event.newData!);
///     case RealtimeEventType.deleted:
///       remove(event.oldData!.id);
///   }
/// }
/// ```
class RealtimeRepository {
  final RealtimeBackend _backend;
  final BackendLogger _logger;

  final Map<String, _Channel> _channels = {};
  final Map<BackendResource, RealtimeDecoder<Object?>> _decoders = {};
  bool _disposed = false;

  /// Creates a realtime repository over [backend].
  RealtimeRepository({
    required RealtimeBackend backend,
    BackendLogger logger = const NoopBackendLogger(),
  })  : _backend = backend,
        _logger = logger;

  /// Registers how a provider record becomes an application model for
  /// [resource].
  ///
  /// A typed repository such as `ProductsRepository` registers itself when it
  /// is constructed, which is why `realtime.watch` for
  /// [BackendResource.products] yields typed products without the application
  /// supplying a mapper.
  void registerDecoder(
    BackendResource resource,
    RealtimeDecoder<Object?> decoder,
  ) {
    _decoders[resource] = decoder;
  }

  /// Watches [resource] for insert, update and delete events.
  ///
  /// The returned [RealtimeSubscription] is a broadcast stream, so several
  /// listeners may attach to one watcher. Call [RealtimeSubscription.dispose]
  /// when the watcher is no longer needed - for example in a Flutter
  /// `State.dispose` override.
  RealtimeSubscription<T> watch<T extends Object>({
    required BackendResource resource,
    Map<String, Object?> filters = const {},
  }) {
    final invalid = RealtimeResource.validate(filters);
    if (invalid != null) {
      return _RejectedSubscription<T>(resource, invalid);
    }

    final decoder = _decoders[resource];
    if (decoder == null) {
      return _RejectedSubscription<T>(resource, _noDecoderFailure(resource));
    }

    final descriptor = RealtimeResource(resource: resource, filters: filters);
    final key = descriptor.channelName;

    final existing = _channels[key];
    if (existing != null && !existing.isClosed) {
      _logger.debug(
        'Reusing an existing realtime channel.',
        context: {'resource': resource.name, 'channel': key},
      );
      return existing.typedView<T>();
    }

    final channel = _Channel(
      resource: resource,
      descriptor: descriptor,
      decoder: decoder,
      backend: _backend,
      logger: _logger,
      onClosed: () => _channels.remove(key),
    );
    _channels[key] = channel;
    unawaited(channel.connect());
    return channel.typedView<T>();
  }

  /// Whether a channel is currently open for [resource] with [filters].
  ///
  /// Exposed for diagnostics, and used by tests to assert that duplicate
  /// subscriptions are prevented.
  bool hasActiveSubscription({
    required BackendResource resource,
    Map<String, Object?> filters = const {},
  }) {
    final key =
        RealtimeResource(resource: resource, filters: filters).channelName;
    final entry = _channels[key];
    return entry != null && !entry.isClosed;
  }

  /// The number of provider channels currently open.
  int get activeSubscriptionCount =>
      _channels.values.where((channel) => !channel.isClosed).length;

  /// The most recent realtime failure, or `null`.
  BackendFailure? get lastFailure => _backend.lastFailure;

  BackendFailure _noDecoderFailure(BackendResource resource) {
    return BackendErrorClassifier.build(
      type: BackendErrorType.realtime,
      message:
          'No realtime decoder is registered for ${resource.name}. Use the '
          'typed repository for this resource before watching it.',
    );
  }

  /// Closes every channel and releases provider resources.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final open = _channels.values.toList(growable: false);
    _channels.clear();
    for (final channel in open) {
      await channel.close();
    }
    _decoders.clear();
    await _backend.dispose();
  }
}

/// One shared provider channel plus the listeners attached to it.
class _Channel {
  _Channel({
    required this.resource,
    required this.descriptor,
    required this.decoder,
    required this.backend,
    required this.logger,
    required this.onClosed,
  });

  final BackendResource resource;
  final RealtimeResource descriptor;
  final RealtimeDecoder<Object?> decoder;
  final RealtimeBackend backend;
  final BackendLogger logger;
  final void Function() onClosed;

  final StreamController<RealtimeEvent<Object?>> _controller =
      StreamController<RealtimeEvent<Object?>>.broadcast(sync: true);

  final Completer<void> _ready = Completer<void>();

  /// How many typed views currently hold this channel open.
  int _refCount = 0;

  BackendFailure? _lastFailure;
  bool _closed = false;
  bool _connecting = false;

  /// Completes when the channel is established or has definitively failed.
  Future<void> get ready => _ready.future;

  bool get isClosed => _closed;

  BackendFailure? get lastFailure => _lastFailure ?? backend.lastFailure;

  /// Opens the provider channel. Safe to call more than once.
  Future<void> connect() async {
    if (_closed || _connecting) return;
    _connecting = true;
    try {
      await backend.subscribe(
        resource: resource,
        filters: descriptor.filters,
        onEvent: _handleEvent,
      );
    } on BackendFailure catch (failure) {
      _lastFailure = failure;
    } on Object catch (error, stackTrace) {
      _lastFailure = BackendErrorClassifier.fromException(
        error,
        stackTrace,
        fallbackType: BackendErrorType.realtime,
      );
    } finally {
      _connecting = false;
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  void _handleEvent(RealtimeEvent<BackendRecord> raw) {
    if (_closed) return;
    final mapped = _mapEvent(raw);
    if (mapped == null) return;
    _controller.add(mapped);
  }

  RealtimeEvent<Object?>? _mapEvent(RealtimeEvent<BackendRecord> raw) {
    Object? newData;
    Object? oldData;

    if (raw.newData != null) {
      newData = decoder(raw.newData!);
      if (newData == null) {
        _logMappingFailure('new', raw);
        return null;
      }
    }
    if (raw.oldData != null) {
      oldData = decoder(raw.oldData!);
      if (oldData == null) {
        _logMappingFailure('old', raw);
        return null;
      }
    }
    if (newData == null && oldData == null) {
      return null;
    }

    return RealtimeEvent<Object?>(
      type: raw.type,
      oldData: oldData,
      newData: newData,
      committedAt: raw.committedAt,
    );
  }

  void _logMappingFailure(String side, RealtimeEvent<BackendRecord> raw) {
    final failure = BackendErrorClassifier.build(
      type: BackendErrorType.realtime,
      message: 'A realtime payload for ${resource.name} could not be mapped '
          'to a model ($side record).',
    );
    _lastFailure = failure;
    logger.warn(failure.message, context: {
      'resource': resource.name,
      'eventType': raw.type.name,
    });
  }

  /// Creates a typed view onto this channel and takes a reference on it.
  ///
  /// The returned view filters out any payload that is not a `T`, so a
  /// mistakenly requested type yields an empty stream rather than a
  /// `TypeError` inside a `await for`.
  _TypedSubscription<T> typedView<T extends Object>() {
    _refCount++;
    final events = _controller.stream
        .map<RealtimeEvent<T>?>(_retype<T>)
        .where((event) => event != null)
        .cast<RealtimeEvent<T>>();

    return _TypedSubscription<T>(
      resource: resource,
      events: events,
      ready: ready,
      failureReader: () => lastFailure,
      isActiveReader: () => !_closed,
      onDispose: () {
        _refCount--;
        if (_refCount <= 0) {
          onClosed();
          unawaited(close());
        }
      },
    );
  }

  /// Closes the channel and its provider resources. Idempotent.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    onClosed();
    try {
      await backend.unsubscribe(
        resource: resource,
        filters: descriptor.filters,
      );
    } on Object catch (error, stackTrace) {
      logger.error(
        'Closing a realtime channel failed.',
        cause: error,
        stackTrace: stackTrace,
        context: {'resource': resource.name},
      );
    }
    if (!_ready.isCompleted) _ready.complete();
    await _controller.close();
  }
}

/// A typed, broadcast view onto a shared channel.
class _TypedSubscription<T extends Object> implements RealtimeSubscription<T> {
  _TypedSubscription({
    required this.resource,
    required this.events,
    required this.ready,
    required this.failureReader,
    required this.isActiveReader,
    required this.onDispose,
  });

  @override
  final BackendResource resource;

  @override
  final Stream<RealtimeEvent<T>> events;

  /// Completes when the underlying channel is established or has failed.
  @override
  final Future<void> ready;

  final BackendFailure? Function() failureReader;
  final bool Function() isActiveReader;
  final void Function() onDispose;

  bool _disposed = false;

  @override
  bool get isActive => isActiveReader() && !_disposed;

  @override
  BackendFailure? get lastFailure => failureReader();

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    onDispose();
  }
}

/// A subscription that failed validation and is inert from the start.
class _RejectedSubscription<T extends Object>
    implements RealtimeSubscription<T> {
  _RejectedSubscription(this.resource, this._failure);

  @override
  final BackendResource resource;

  final BackendFailure _failure;

  @override
  bool get isActive => false;

  @override
  Stream<RealtimeEvent<T>> get events => Stream<RealtimeEvent<T>>.empty();

  @override
  Future<void> get ready => Future<void>.value();

  @override
  BackendFailure? get lastFailure => _failure;

  @override
  Future<void> dispose() async {}
}

/// Re-types a shared-channel event for a specific model type.
///
/// Returns `null` when neither payload is a `T`, which drops the event instead
/// of letting a wrong `await for` type produce a `TypeError` at runtime.
RealtimeEvent<T>? _retype<T>(RealtimeEvent<Object?> event) {
  final newData = event.newData;
  final oldData = event.oldData;
  if (newData is! T && oldData is! T) return null;
  return RealtimeEvent<T>(
    type: event.type,
    oldData: oldData is T ? oldData : null,
    newData: newData is T ? newData : null,
    committedAt: event.committedAt,
  );
}
