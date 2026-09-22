import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../config/api_config.dart';
import '../models/ledger.dart';
import 'api_client.dart';

/// دفتر الحساب — talks to `/api/ledger/`.
class LedgerService {
  final _client = ApiClient.instance;

  static String get _base => ApiConfig.baseUrl;

  /// DRF returns `{field: [msg]}` or `{detail: msg}`; pull the first
  /// human line out so the sheet can show it under the form.
  Exception _error(http.Response r, String fallback) {
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is Map) {
        final first = j['detail'] ?? j['non_field_errors'] ?? j.values.first;
        final msg = first is List ? first.first : first;
        return Exception(msg.toString());
      }
    } catch (_) {}
    return Exception('$fallback [${r.statusCode}]');
  }

  Map<String, dynamic> _json(http.Response r) =>
      jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;

  // ── dashboard / summary ──────────────────────────────────────────────

  String _periodQuery(String period, {DateTime? start, DateTime? end}) {
    var q = 'period=$period';
    if (period == 'custom' && start != null && end != null) {
      q += '&start=${_date(start)}&end=${_date(end)}';
    }
    return q;
  }

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<StoreDashboard> fetchDashboard({
    String period = 'month',
    DateTime? start,
    DateTime? end,
  }) async {
    final r = await _client.get('/ledger/dashboard/?${_periodQuery(period, start: start, end: end)}');
    if (r.statusCode == 200) return StoreDashboard.fromJson(_json(r));
    throw _error(r, 'تعذّر تحميل لوحة المتجر');
  }

  // ── contacts ─────────────────────────────────────────────────────────

  Future<List<LedgerContact>> fetchContacts({
    ContactKind? kind,
    String? query,
    bool byBalance = true,
    bool archived = false,
  }) async {
    final params = <String>[
      if (kind != null) 'kind=${kind.value}',
      if (query != null && query.isNotEmpty) 'q=${Uri.encodeQueryComponent(query)}',
      if (byBalance) 'ordering=balance',
      if (archived) 'archived=1',
    ];
    final r = await _client.get('/ledger/contacts/${params.isEmpty ? '' : '?${params.join('&')}'}');
    if (r.statusCode == 200) {
      final list = jsonDecode(utf8.decode(r.bodyBytes)) as List<dynamic>;
      return list.map((e) => LedgerContact.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw _error(r, 'تعذّر تحميل الأطراف');
  }

  Future<LedgerContact> createContact({
    required String name,
    required ContactKind kind,
    String phone = '',
    String notes = '',
  }) async {
    final r = await _client.post('/ledger/contacts/', body: {
      'name': name,
      'kind': kind.value,
      'phone': phone,
      'notes': notes,
    });
    if (r.statusCode == 201) return LedgerContact.fromJson(_json(r));
    throw _error(r, 'تعذّر حفظ الطرف');
  }

  Future<LedgerContact> updateContact(
    int id, {
    String? name,
    String? phone,
    String? notes,
  }) async {
    final r = await _client.patch('/ledger/contacts/$id/', body: {
      'name': ?name,
      'phone': ?phone,
      'notes': ?notes,
    });
    if (r.statusCode == 200) return LedgerContact.fromJson(_json(r));
    throw _error(r, 'تعذّر حفظ الطرف');
  }

  /// Archives when the contact has history, deletes otherwise.
  Future<void> removeContact(int id) async {
    final r = await _client.delete('/ledger/contacts/$id/');
    if (r.statusCode == 200 || r.statusCode == 204) return;
    throw _error(r, 'تعذّر حذف الطرف');
  }

  Future<ContactStatement> fetchStatement(int contactId) async {
    final r = await _client.get('/ledger/contacts/$contactId/statement/');
    if (r.statusCode == 200) return ContactStatement.fromJson(_json(r));
    throw _error(r, 'تعذّر تحميل كشف الحساب');
  }

  // ── entries ──────────────────────────────────────────────────────────

  Future<({List<LedgerEntry> entries, bool hasMore})> fetchEntries({
    int page = 1,
    List<LedgerKind>? kinds,
    int? contactId,
    bool? fromApp,
    bool includeVoid = false,
    DateTime? start,
    DateTime? end,
  }) async {
    final params = <String>[
      'page=$page',
      if (kinds != null && kinds.isNotEmpty) 'kind=${kinds.map((k) => k.value).join(',')}',
      if (contactId != null) 'contact=$contactId',
      if (fromApp != null) 'source=${fromApp ? 'app' : 'manual'}',
      if (includeVoid) 'include_void=1',
      if (start != null) 'start=${_date(start)}',
      if (end != null) 'end=${_date(end)}',
    ];
    final r = await _client.get('/ledger/entries/?${params.join('&')}');
    if (r.statusCode == 200) {
      final j = _json(r);
      final list = (j['results'] as List<dynamic>? ?? const [])
          .map((e) => LedgerEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      return (entries: list, hasMore: j['next'] != null);
    }
    throw _error(r, 'تعذّر تحميل الدفتر');
  }

  /// Writes one entry. Goes multipart when there's a receipt photo, JSON
  /// otherwise — the server accepts both on the same endpoint.
  Future<LedgerEntry> createEntry({
    required String accessToken,
    required LedgerKind kind,
    required double amount,
    int? contactId,
    String note = '',
    DateTime? occurredAt,
    String? expenseCategory,
    int? itemId,
    int? variantId,
    int? quantity,
    XFile? receipt,
  }) async {
    final fields = <String, String>{
      'kind': kind.value,
      'amount': amount.toStringAsFixed(2),
      'note': note,
      if (contactId != null) 'contact': '$contactId',
      if (occurredAt != null) 'occurred_at': occurredAt.toUtc().toIso8601String(),
      if (expenseCategory != null && expenseCategory.isNotEmpty) 'expense_category': expenseCategory,
      if (itemId != null) 'item': '$itemId',
      if (variantId != null) 'variant': '$variantId',
      if (quantity != null) 'quantity': '$quantity',
    };

    http.Response r;
    if (receipt == null) {
      r = await _client.post('/ledger/entries/', body: fields);
    } else {
      final request = http.MultipartRequest('POST', Uri.parse('$_base/ledger/entries/'))
        ..headers['Authorization'] = 'Bearer $accessToken'
        ..fields.addAll(fields)
        ..files.add(http.MultipartFile.fromBytes(
          'receipt', await receipt.readAsBytes(), filename: receipt.name));
      r = await http.Response.fromStream(await request.send());
    }
    if (r.statusCode == 201) return LedgerEntry.fromJson(_json(r));
    throw _error(r, 'تعذّر تسجيل القيد');
  }

  Future<LedgerEntry> voidEntry(int id, {String reason = ''}) async {
    final r = await _client.post('/ledger/entries/$id/void/', body: {'reason': reason});
    if (r.statusCode == 200) return LedgerEntry.fromJson(_json(r));
    throw _error(r, 'تعذّر إلغاء القيد');
  }
}
