import 'cursor_page_result.dart';
import 'page_result.dart';

/// Canonical provider-neutral offset page type.
///
/// [PageResult] remains the concrete class for source compatibility.
typedef BackendPage<T> = PageResult<T>;

/// Canonical provider-neutral cursor page type.
///
/// [CursorPageResult] remains the concrete class for source compatibility.
typedef BackendCursorPage<T> = CursorPageResult<T>;
