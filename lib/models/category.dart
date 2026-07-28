class Category {
  final int id;
  final String name;
  final String nameAr;
  final String? iconUrl;
  final int? iconCode;
  final int? parentId;

  const Category({
    required this.id,
    required this.name,
    required this.nameAr,
    this.iconUrl,
    this.iconCode,
    this.parentId,
  });

  String get displayName {
    if (nameAr.isNotEmpty) return nameAr;
    return name;
  }

  /// True when this is a top-level (root) category, i.e. has no parent.
  bool get isRoot => parentId == null;

  factory Category.fromJson(Map<String, dynamic> json) {
    final nameAr = json['name_ar'] as String? ?? '';
    final name = json['name'] as String? ?? '';

    // حقل "icon" مرن: يحمل إمّا رمز Material Icon رقمي (مثال: "57688") أو
    // رابط صورة مباشر (استخدام قديم قبل إضافة حقل الصورة المرفوعة).
    final rawIcon = json['icon'] ?? json['icon_code'];
    int? iconCode;
    String? legacyIconUrl;
    if (rawIcon != null) {
      final iconStr = rawIcon.toString();
      final asInt = int.tryParse(iconStr);
      if (asInt != null) {
        iconCode = asInt;
      } else if (iconStr.startsWith('http')) {
        legacyIconUrl = iconStr;
      }
    }

    // الصورة المرفوعة من لوحة التحكم لها الأولوية على الاستخدام القديم أعلاه.
    final imageUrl = json['image_url'] as String?;

    final rawParent = json['parent'];
    final parentId = rawParent is Map<String, dynamic>
        ? rawParent['id'] as int?
        : rawParent is int
            ? rawParent
            : null;

    return Category(
      id: json['id'] as int,
      name: name,
      nameAr: nameAr.isNotEmpty ? nameAr : name,
      iconUrl: imageUrl ?? legacyIconUrl,
      iconCode: iconCode,
      parentId: parentId,
    );
  }
}
