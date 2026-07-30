class FilterParams {
  static const double minBound = 0;
  static const double maxBound = 10000000;
  static const double minDepositBound = 0;
  static const double maxDepositBound = 100;

  static const List<(String, String)> conditions = [
    ('new', 'جديد'),
    ('like_new', 'شبه جديد'),
    ('good', 'جيد'),
    ('fair', 'مقبول'),
    ('poor', 'ضعيف'),
  ];

  // Ordering options for /listings/fixed/
  static const List<(String, String)> sortOptions = [
    ('-created_at', 'الأحدث'),
    ('-item__sold_count', 'الأكثر مبيعاً'),
    ('-item__rating', 'الأعلى تقييماً'),
    ('price', 'السعر: من الأقل'),
    ('-price', 'السعر: من الأعلى'),
  ];

  // Ordering options for /auctions/
  static const List<(String, String)> auctionSortOptions = [
    ('-created_at', 'الأحدث'),
    ('end_time', 'ينتهي قريباً'),
    ('-current_price', 'السعر: من الأعلى'),
    ('current_price', 'السعر: من الأقل'),
    ('-item__sold_count', 'الأكثر مبيعاً'),
  ];

  final int? categoryId;
  final String? condition;
  final double minPrice;
  final double maxPrice;
  final double minDeposit;
  final double maxDeposit;
  final String? city;
  final bool isDailyDeal;
  final bool hasDiscount;
  final String ordering;

  const FilterParams({
    this.categoryId,
    this.condition,
    this.minPrice = minBound,
    this.maxPrice = maxBound,
    this.minDeposit = minDepositBound,
    this.maxDeposit = maxDepositBound,
    this.city,
    this.isDailyDeal = false,
    this.hasDiscount = false,
    this.ordering = '-created_at',
  });

  Map<String, String> toQueryParams() {
    final p = <String, String>{};
    if (categoryId != null) p['category'] = '$categoryId';
    if (condition != null) p['condition'] = condition!;
    if (minPrice > minBound) p['min_price'] = minPrice.toStringAsFixed(0);
    if (maxPrice < maxBound) p['max_price'] = maxPrice.toStringAsFixed(0);
    if (minDeposit > minDepositBound) p['min_deposit'] = minDeposit.toStringAsFixed(0);
    if (maxDeposit < maxDepositBound) p['max_deposit'] = maxDeposit.toStringAsFixed(0);
    if (city != null && city!.trim().isNotEmpty) p['city'] = city!.trim();
    if (isDailyDeal) p['is_daily_deal'] = 'true';
    if (hasDiscount) p['has_discount'] = 'true';
    p['ordering'] = ordering;
    return p;
  }

  Map<String, String> toAuctionQueryParams() {
    final p = <String, String>{};
    if (categoryId != null) p['category'] = '$categoryId';
    if (condition != null) p['condition'] = condition!;
    if (minPrice > minBound) p['min_price'] = minPrice.toStringAsFixed(0);
    if (maxPrice < maxBound) p['max_price'] = maxPrice.toStringAsFixed(0);
    if (city != null && city!.trim().isNotEmpty) p['city'] = city!.trim();
    p['ordering'] = ordering;
    return p;
  }

  // Sort order (`ordering`) is deliberately excluded here — changing how
  // results are sorted doesn't narrow them, so it shouldn't light up a
  // "filters active" badge.
  bool get hasActiveFilters =>
      categoryId != null ||
      condition != null ||
      minPrice > minBound ||
      maxPrice < maxBound ||
      minDeposit > minDepositBound ||
      maxDeposit < maxDepositBound ||
      (city?.trim().isNotEmpty ?? false) ||
      isDailyDeal ||
      hasDiscount;

  bool get hasActiveAuctionFilters =>
      categoryId != null ||
      condition != null ||
      minPrice > minBound ||
      maxPrice < maxBound ||
      (city?.trim().isNotEmpty ?? false);

  FilterParams copyWith({
    Object? categoryId = _sentinel,
    Object? condition = _sentinel,
    double? minPrice,
    double? maxPrice,
    double? minDeposit,
    double? maxDeposit,
    Object? city = _sentinel,
    bool? isDailyDeal,
    bool? hasDiscount,
    String? ordering,
  }) {
    return FilterParams(
      categoryId: categoryId == _sentinel ? this.categoryId : categoryId as int?,
      condition: condition == _sentinel ? this.condition : condition as String?,
      minPrice: minPrice ?? this.minPrice,
      maxPrice: maxPrice ?? this.maxPrice,
      minDeposit: minDeposit ?? this.minDeposit,
      maxDeposit: maxDeposit ?? this.maxDeposit,
      city: city == _sentinel ? this.city : city as String?,
      isDailyDeal: isDailyDeal ?? this.isDailyDeal,
      hasDiscount: hasDiscount ?? this.hasDiscount,
      ordering: ordering ?? this.ordering,
    );
  }

  static const FilterParams empty = FilterParams();
}

// Sentinel for copyWith nullable fields
const _sentinel = Object();
