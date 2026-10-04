import 'package:supabase/supabase.dart'
    show
        AuthChangeEvent,
        AuthState,
        PostgresChangeEvent,
        PostgresChangePayload,
        Session,
        User;

import '../../auth/auth_session.dart';
import '../../auth/auth_state.dart';
import '../../auth/auth_user.dart';
import '../../contracts/data_backend.dart';
import '../../core/backend_resource.dart';
import '../../realtime/realtime_event.dart';

/// The table a `BackendResource` lives in.
///
/// This is the only place in the package where a table name appears. It is
/// deliberately private to the Supabase provider: application code and even the
/// generic repository layer address resources only through the
/// `BackendResource` enum.
class SupabaseResourceRegistry {
  const SupabaseResourceRegistry._();

  /// The PostgREST schema holding application tables.
  static const String schema = 'public';

  /// The table backing [resource].
  ///
  /// Throws a [StateError] for a resource this provider does not serve, which
  /// can only happen if the enum and this registry drift apart.
  static String tableOf(BackendResource resource) => resource.name;
}

/// Converts Supabase auth and realtime types into the SDK's own types.
abstract final class SupabaseMappers {
  const SupabaseMappers._();

  /// Converts a Supabase `User` into a `BackendUser`.
  ///
  /// Only the user-writable `user_metadata` is exposed. `app_metadata` is
  /// intentionally dropped because it can contain provider-managed and
  /// role-like claims that the application should never read as authoritative -
  /// authorization belongs to the database, not to a client-side claim.
  static BackendUser toUser(User user) {
    return BackendUser(
      id: user.id,
      email: user.email,
      metadata: Map<String, dynamic>.unmodifiable(
        user.userMetadata ?? const <String, dynamic>{},
      ),
      createdAt: parseTimestamp(user.createdAt),
      lastSignInAt: parseTimestamp(user.lastSignInAt),
    );
  }

  /// Converts a Supabase `Session` into a `BackendSession`.
  ///
  /// Supabase reports a relative `expiresIn` rather than an absolute expiry, so
  /// the absolute timestamp is derived here. A missing `expiresIn` yields a
  /// `null` expiry, which callers must treat as "unknown", not "never expires".
  static BackendSession toSession(Session session) {
    final expiresIn = session.expiresIn;
    return BackendSession(
      accessToken: session.accessToken,
      expiresAt: expiresIn == null
          ? null
          : DateTime.now().add(Duration(seconds: expiresIn)),
      user: toUser(session.user),
    );
  }

  /// Converts a Supabase `AuthState` into an `AuthStateChange`.
  ///
  /// Events that do not change the effective session (currently the MFA
  /// challenge confirmation) are reported with the status the current session
  /// implies, so a listener always receives a coherent state.
  static AuthStateChange toAuthStateChange(AuthState state) {
    final session = state.session;
    final authenticated = session == null
        ? const AuthStateChange(status: AuthStatus.unauthenticated)
        : AuthStateChange(
            status: AuthStatus.authenticated,
            session: toSession(session),
          );
    return switch (state.event) {
      AuthChangeEvent.signedIn ||
      AuthChangeEvent.tokenRefreshed ||
      AuthChangeEvent.userUpdated ||
      AuthChangeEvent.initialSession =>
        authenticated,
      AuthChangeEvent.signedOut =>
        const AuthStateChange(status: AuthStatus.unauthenticated),
      AuthChangeEvent.passwordRecovery =>
        const AuthStateChange(status: AuthStatus.recoveryRequired),
      _ => authenticated,
    };
  }

  /// Converts a Supabase `PostgresChangePayload` into a `RealtimeEvent`.
  ///
  /// The `table` is checked against the expected resource so a payload for a
  /// different table is never mapped into the wrong model. `newRecord` and
  /// `oldRecord` are returned as raw SDK-internal records; mapping to a model
  /// happens in the repository through the module's decoder.
  /// Returns `null` when [payload] is not a concrete row event.
  static RealtimeEvent<BackendRecord>? toRealtimeEvent(
    PostgresChangePayload payload, {
    required BackendResource resource,
  }) {
    if (payload.table != SupabaseResourceRegistry.tableOf(resource)) {
      return null;
    }

    final type = switch (payload.eventType) {
      PostgresChangeEvent.insert => RealtimeEventType.inserted,
      PostgresChangeEvent.update => RealtimeEventType.updated,
      PostgresChangeEvent.delete => RealtimeEventType.deleted,
      // `PostgresChangeEvent.all` is a subscribe-time wildcard, never an event
      // type, so the analyzer treats this clause as unreachable. If a future
      // client version does deliver it, the guard below still returns `null`
      // rather than guessing.
      _ => null,
    };
    if (type == null) return null;

    return RealtimeEvent<BackendRecord>(
      type: type,
      newData: payload.newRecord.isEmpty ? null : payload.newRecord,
      oldData: payload.oldRecord.isEmpty ? null : payload.oldRecord,
      committedAt: payload.commitTimestamp,
    );
  }

  /// Parses a Postgres timestamp, tolerating the several formats Supabase may
  /// return, and returns `null` rather than throwing on an unparseable value.
  static DateTime? parseTimestamp(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value).toLocal();
    }
    if (value is String) {
      if (value.isEmpty) return null;
      return DateTime.tryParse(value)?.toLocal();
    }
    return null;
  }
}
