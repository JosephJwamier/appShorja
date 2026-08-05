/// Reasons a user can report an item, a store, or another user for —
/// mirrors Report.REASON_CHOICES on the backend (core/models.py). Value is
/// what's sent to the backend; label is what the user sees.
const reportReasons = <({String value, String label})>[
  (value: 'counterfeit', label: 'منتج مقلد أو مخالف'),
  (value: 'prohibited', label: 'منتج ممنوع أو غير قانوني'),
  (value: 'misleading', label: 'وصف مضلل للمنتج'),
  (value: 'scam', label: 'احتيال أو نصب'),
  (value: 'harassment', label: 'مضايقة أو إساءة'),
  (value: 'spam', label: 'محتوى مزعج أو متكرر'),
  (value: 'inappropriate', label: 'محتوى غير لائق'),
  (value: 'fake_account', label: 'حساب أو متجر وهمي'),
  (value: 'other', label: 'أخرى'),
];

String reportReasonLabel(String value) {
  for (final r in reportReasons) {
    if (r.value == value) return r.label;
  }
  return value;
}

/// Only the reasons relevant to each target are offered, so the picker
/// doesn't show e.g. "منتج مقلد" when reporting a store.
const _reasonsByTarget = <String, List<String>>{
  'item': ['counterfeit', 'prohibited', 'misleading', 'scam', 'spam', 'inappropriate', 'other'],
  'store': ['scam', 'fake_account', 'prohibited', 'misleading', 'spam', 'inappropriate', 'other'],
  'user': ['harassment', 'scam', 'fake_account', 'spam', 'inappropriate', 'other'],
};

List<({String value, String label})> reportReasonsFor(String targetType) {
  final allowed = _reasonsByTarget[targetType];
  if (allowed == null) return reportReasons;
  return reportReasons.where((r) => allowed.contains(r.value)).toList();
}
