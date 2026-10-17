import '../pagination/page_result.dart';

/// Provider-neutral metadata describing an offset-paginated result.
///
/// This is deliberately separate from [PageResult]: applications may map a
/// page into their own response model while retaining the pagination contract.
class PaginationModel {
  final int total;
  final int count;
  final int perPage;
  final int currentPage;
  final int totalPages;

  const PaginationModel({
    required this.total,
    required this.count,
    required this.perPage,
    required this.currentPage,
    required this.totalPages,
  });

  static PaginationModel fromPageResult<T>(PageResult<T> page) {
    final total = page.totalCount ?? page.items.length;
    return PaginationModel(
      total: total,
      count: page.items.length,
      perPage: page.pageSize,
      currentPage: page.page,
      totalPages: page.pageSize == 0 ? 0 : (total / page.pageSize).ceil(),
    );
  }

  factory PaginationModel.fromJson(Map<String, dynamic> json) {
    return PaginationModel(
      total: _asInt(json['total']),
      count: _asInt(json['count'] ?? json['size']),
      perPage: _asInt(json['per_page'] ?? json['size']),
      currentPage: _asInt(json['current_page'] ?? json['currentPage']),
      totalPages: _asInt(json['total_pages'] ?? json['totalPages']),
    );
  }

  Map<String, dynamic> toJson() => {
        'total': total,
        'count': count,
        'per_page': perPage,
        'current_page': currentPage,
        'total_pages': totalPages,
      };

  PaginationModel copyWith({
    int? total,
    int? count,
    int? perPage,
    int? currentPage,
    int? totalPages,
  }) {
    return PaginationModel(
      total: total ?? this.total,
      count: count ?? this.count,
      perPage: perPage ?? this.perPage,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
    );
  }

  bool get hasNext => currentPage < totalPages;

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
