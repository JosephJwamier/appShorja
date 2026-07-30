/// وثيقة قانونية (سياسة خصوصية أو شروط استخدام) قادمة من الخادم.
class LegalDocument {
  final int id;
  final String docType; // 'privacy' | 'terms'
  final String docTypeDisplay;
  final String language; // 'ar' | 'en'
  final int version;
  final String title;
  final String? summary;
  final String? content; // HTML (يُطلب فقط في النسخة الكاملة)
  final String? publicUrl;

  const LegalDocument({
    required this.id,
    required this.docType,
    required this.docTypeDisplay,
    required this.language,
    required this.version,
    required this.title,
    this.summary,
    this.content,
    this.publicUrl,
  });

  factory LegalDocument.fromJson(Map<String, dynamic> j) {
    return LegalDocument(
      id: j['id'] as int,
      docType: (j['doc_type'] ?? '') as String,
      docTypeDisplay: (j['doc_type_display'] ?? '') as String,
      language: (j['language'] ?? 'ar') as String,
      version: (j['version'] ?? 1) as int,
      title: (j['title'] ?? '') as String,
      summary: j['summary'] as String?,
      content: j['content'] as String?,
      publicUrl: j['public_url'] as String?,
    );
  }
}
