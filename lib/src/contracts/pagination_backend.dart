import '../core/backend_resource.dart';
import 'data_backend.dart';

/// The offset- and cursor-pagination slice of the [DataBackend] contract.
///
/// Kept as a separate contract so a provider can implement pagination once and
/// inherit it, and so pagination policy is reviewable in isolation from CRUD.
abstract interface class PaginationBackend implements DataBackend {
  /// The inclusive range for an offset page.
  ///
  /// Exposed on the contract so pagination arithmetic has a single
  /// implementation and a single set of tests.
  ///
  /// ```dart
  /// final range = pageRange(page: 2, pageSize: 20); // 20..39 inclusive
  /// ```
  static ({int from, int to}) pageRange({
    required int page,
    required int pageSize,
  }) {
    final from = (page - 1) * pageSize;
    return (from: from, to: from + pageSize - 1);
  }
}

/// The provider-facing resource descriptor.
///
/// A provider maps each [BackendResource] to its own physical location - a
/// table, a collection, an endpoint path - and declares which columns are
/// searchable. Repositories and applications work exclusively with the enum.
typedef ResourceLocator = String Function(BackendResource resource);

/// The searchable columns declared by a repository for a resource.
///
/// A free-text `search` term is expanded to a case-insensitive OR over these
/// columns, so the application never writes a vendor-specific `ilike` chain.
typedef SearchableColumns = List<String> Function(BackendResource resource);
