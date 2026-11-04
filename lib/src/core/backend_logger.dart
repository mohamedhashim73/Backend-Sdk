import 'dart:collection';

/// A pluggable logging sink for the SDK.
///
/// The SDK redacts credentials, access tokens, refresh tokens, API keys and
/// file contents by default. Redaction can be explicitly disabled for local
/// diagnostics, so applications must keep that option off outside testing.
abstract interface class BackendLogger {
  /// Records a verbose diagnostic message.
  void debug(String message, {Map<String, Object?> context = const {}});

  /// Records an informational message.
  void info(String message, {Map<String, Object?> context = const {}});

  /// Records a recoverable problem.
  void warn(String message, {Map<String, Object?> context = const {}});

  /// Records a failure together with its cause and stack trace.
  void error(
    String message, {
    Object? cause,
    StackTrace? stackTrace,
    Map<String, Object?> context = const {},
  });
}

/// A logger that discards everything.
///
/// This is the default so that a misconfigured logging pipeline can never
/// become a data leak, and so release builds stay silent.
class NoopBackendLogger implements BackendLogger {
  /// Creates a discarding logger.
  const NoopBackendLogger();

  @override
  void debug(String message, {Map<String, Object?> context = const {}}) {}

  @override
  void info(String message, {Map<String, Object?> context = const {}}) {}

  @override
  void warn(String message, {Map<String, Object?> context = const {}}) {}

  @override
  void error(
    String message, {
    Object? cause,
    StackTrace? stackTrace,
    Map<String, Object?> context = const {},
  }) {}
}

/// Signature of the sink that receives sanitized log lines.
///
/// A plain function signature keeps the SDK free of any `print`/`debugPrint`
/// dependency, so an application can route entries into `logging`,
/// `dart:developer`, or a crash reporter.
typedef BackendLogSink = void Function(LogEntry entry);

/// The default [BackendLogger] implementation, which writes to an injected
/// sink.
class CallbackBackendLogger implements BackendLogger {
  /// The default context key substitution value.
  static const String redactedValue = '[redacted]';

  static final RegExp _sensitiveKeyPattern = RegExp(
    r'(pass|pwd|secret|token|key|auth|credential|cookie|signature|bearer)',
    caseSensitive: false,
  );

  /// Maximum number of characters kept from any single context value.
  static const int maxValueLength = 200;

  final BackendLogSink _sink;
  final bool _isDebug;
  final bool _redactSensitiveData;

  /// Creates a logger that forwards sanitized entries to [_sink].
  ///
  /// [redactSensitiveData] defaults to `true`. Set it to `false` only for
  /// short-lived local diagnostics when request values must be inspected.
  const CallbackBackendLogger({
    required BackendLogSink sink,
    bool isDebug = true,
    bool redactSensitiveData = true,
  })  : _sink = sink,
        _isDebug = isDebug,
        _redactSensitiveData = redactSensitiveData;

  @override
  void debug(String message, {Map<String, Object?> context = const {}}) {
    if (!_isDebug) return;
    _sink(
      LogEntry(
        level: LogLevel.debug,
        message: message,
        context: context,
        redactSensitiveData: _redactSensitiveData,
      ),
    );
  }

  @override
  void info(String message, {Map<String, Object?> context = const {}}) {
    _sink(
      LogEntry(
        level: LogLevel.info,
        message: message,
        context: context,
        redactSensitiveData: _redactSensitiveData,
      ),
    );
  }

  @override
  void warn(String message, {Map<String, Object?> context = const {}}) {
    _sink(
      LogEntry(
        level: LogLevel.warning,
        message: message,
        context: context,
        redactSensitiveData: _redactSensitiveData,
      ),
    );
  }

  @override
  void error(
    String message, {
    Object? cause,
    StackTrace? stackTrace,
    Map<String, Object?> context = const {},
  }) {
    _sink(
      LogEntry(
        level: LogLevel.error,
        message: message,
        context: context,
        cause: cause,
        stackTrace: stackTrace,
        redactSensitiveData: _redactSensitiveData,
      ),
    );
  }

  /// Returns a sanitized copy of [context].
  ///
  /// Keys that look like credentials are replaced entirely and every remaining
  /// value is truncated, because a full provider error payload can contain an
  /// echoed request body.
  static Map<String, Object?> redact(Map<String, Object?> context) {
    return sanitize(context);
  }

  /// Returns a sanitized copy of [context], optionally preserving sensitive
  /// values for explicitly enabled local diagnostics. When redaction is
  /// disabled, values are kept in full so request payloads can be inspected.
  static Map<String, Object?> sanitize(
    Map<String, Object?> context, {
    bool redactSensitiveData = true,
  }) {
    if (context.isEmpty) return const {};
    final result = <String, Object?>{};
    for (final entry in context.entries) {
      if (redactSensitiveData && _sensitiveKeyPattern.hasMatch(entry.key)) {
        result[entry.key] = redactedValue;
        continue;
      }
      result[entry.key] = _sanitize(
        entry.value,
        redactSensitiveData: redactSensitiveData,
      );
    }
    return result;
  }

  static Object? _sanitize(
    Object? value, {
    required bool redactSensitiveData,
  }) {
    if (value == null) return null;
    if (value is String) {
      if (!redactSensitiveData) return value;
      return value.length <= maxValueLength
          ? value
          : '${value.substring(0, maxValueLength)}…';
    }
    if (value is num || value is bool) return value;
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): redactSensitiveData &&
                  _sensitiveKeyPattern.hasMatch(entry.key.toString())
              ? redactedValue
              : _sanitize(
                  entry.value,
                  redactSensitiveData: redactSensitiveData,
                ),
      };
    }
    if (value is Iterable) {
      return value
          .map(
            (item) => _sanitize(
              item,
              redactSensitiveData: redactSensitiveData,
            ),
          )
          .toList(growable: false);
    }
    return _sanitize(value.toString(),
        redactSensitiveData: redactSensitiveData);
  }
}

/// The severity of a [LogEntry].
enum LogLevel {
  /// Verbose diagnostics, emitted only in debug builds.
  debug,

  /// Normal lifecycle information.
  info,

  /// A recoverable problem.
  warning,

  /// A failure, always accompanied by a cause.
  error,
}

/// A single sanitized log record.
class LogEntry {
  /// The severity of this entry.
  final LogLevel level;

  /// The log message.
  final String message;

  /// Additional structured context, sanitized according to the logger
  /// configuration.
  final Map<String, Object?> context;

  /// The error that triggered this entry, if any.
  final Object? cause;

  /// The stack trace associated with [cause].
  final StackTrace? stackTrace;

  /// Creates a log entry.
  LogEntry({
    required this.level,
    required this.message,
    Map<String, Object?> context = const {},
    this.cause,
    this.stackTrace,
    bool redactSensitiveData = true,
  }) : context = UnmodifiableMapView(
          CallbackBackendLogger.sanitize(
            context,
            redactSensitiveData: redactSensitiveData,
          ),
        );

  @override
  String toString() {
    final buffer = StringBuffer('[${level.name.toUpperCase()}] $message');
    if (context.isNotEmpty) {
      buffer.write(' $context');
    }
    if (cause != null) {
      buffer.write(' | cause: $cause');
    }
    return buffer.toString();
  }
}
