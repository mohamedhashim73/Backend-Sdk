import '../errors/backend_error_mapper.dart';
import '../errors/backend_error_type.dart';
import '../errors/backend_failure.dart';

/// Local, provider-independent validation of credential input.
///
/// Validating before the request leaves the device keeps obviously invalid
/// input off the network and produces precise failures. Messages are
/// intentionally identical for "no such user" and "wrong password" so a UI
/// cannot be used to discover which emails are registered.
abstract final class AuthValidator {
  /// The minimum accepted password length.
  static const int minPasswordLength = 8;

  /// The maximum accepted password length.
  ///
  /// Bounded to keep hashing cost predictable and to reject abusive payloads.
  static const int maxPasswordLength = 128;

  /// Matches a deliberately pragmatic email shape.
  ///
  /// The backend remains the authority on deliverability; this only rejects
  /// obviously malformed input.
  static final RegExp emailPattern = RegExp(
    r'^[^@\s]+@[^@\s.]+(\.[^@\s.]+)+$',
  );

  /// The maximum number of keys in a single metadata update.
  static const int maxMetadataFields = 25;

  /// The maximum length of a metadata key.
  static const int maxMetadataKeyLength = 64;

  /// Returns a validation failure for a malformed [email], or `null`.
  static BackendFailure? validateEmail(String email) {
    final trimmed = email.trim();
    if (trimmed.isEmpty) {
      return _failure('An email address is required.');
    }
    if (trimmed.length > 254 || !emailPattern.hasMatch(trimmed)) {
      return _failure('The email address is not a valid email address.');
    }
    return null;
  }

  /// Returns a validation failure for a weak [password], or `null`.
  static BackendFailure? validatePassword(String password) {
    if (password.isEmpty) {
      return _failure('A password is required.');
    }
    if (password.length < minPasswordLength) {
      return _failure(
        'The password must be at least $minPasswordLength characters long.',
      );
    }
    if (password.length > maxPasswordLength) {
      return _failure(
        'The password must not exceed $maxPasswordLength characters.',
      );
    }
    return null;
  }

  /// Validates an email/password pair.
  ///
  /// Returns a failure when either value is invalid, or `null` when the pair is
  /// acceptable.
  static BackendFailure? validateCredentials({
    required String email,
    required String password,
  }) {
    return validateEmail(email) ?? validatePassword(password);
  }

  /// Returns a validation failure for an invalid [redirectTo] URL, or `null`.
  ///
  /// Redirect targets end up inside an email link, so only absolute `http(s)`
  /// URLs are accepted. This blocks `javascript:` and custom-scheme injection
  /// into the recovery flow.
  static BackendFailure? validateRedirectTo(String? redirectTo) {
    if (redirectTo == null || redirectTo.isEmpty) return null;
    final uri = Uri.tryParse(redirectTo);
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      return _failure('The redirect URL must be an absolute http(s) URL.');
    }
    return null;
  }

  /// Returns a validation failure for a metadata payload, or `null`.
  ///
  /// Keys are bounded and values are limited to JSON-compatible shapes, which
  /// keeps a user-controlled blob from becoming a storage or logging problem.
  static BackendFailure? validateMetadata(Map<String, dynamic> metadata) {
    if (metadata.isEmpty) {
      return _failure('At least one metadata field is required.');
    }
    if (metadata.length > maxMetadataFields) {
      return _failure(
        'At most $maxMetadataFields metadata fields can be updated at once.',
      );
    }
    for (final entry in metadata.entries) {
      if (entry.key.isEmpty || entry.key.length > maxMetadataKeyLength) {
        return _failure(
          'Metadata field names must be 1 to $maxMetadataKeyLength '
          'characters long.',
        );
      }
      final value = entry.value;
      if (value != null &&
          value is! String &&
          value is! num &&
          value is! bool &&
          value is! List &&
          value is! Map) {
        return _failure(
          'The metadata field "${entry.key}" has an unsupported value type.',
        );
      }
    }
    return null;
  }

  static BackendFailure _failure(String message) {
    return BackendErrorClassifier.build(
      type: BackendErrorType.validation,
      message: message,
    );
  }
}
