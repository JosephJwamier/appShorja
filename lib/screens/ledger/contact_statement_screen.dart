import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/ledger.dart';
import '../../providers/ledger_provider.dart';
import '../../providers/store_provider.dart';
import '../../services/ledger_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/formatters.dart';
import '../../utils/statement_pdf.dart';
import 'contacts_screen.dart';
import 'ledger_entries_screen.dart';
import 'quick_entry_sheet.dart';

/// كشف حساب — one contact's page of the book, with the two things the
/// merchant does from it: record a payment, and remind them (WhatsApp / PDF).
class ContactStatementScreen extends StatefulWidget {
  final LedgerContact contact;
  const ContactStatementScreen({super.key, required this.contact});

  @override
  State<ContactStatementScreen> createState() => _ContactStatementScreenState();
}

class _ContactStatementScreenState extends State<ContactStatementScreen> {
  final _service = LedgerService();
  late LedgerContact _contact = widget.contact;
  ContactStatement? _statement;
  String? _error;
  int _seenRevision = -1;

  bool get _isCustomer => _contact.kind == ContactKind.customer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await _service.fetchStatement(_contact.id);
      if (!mounted) return;
      setState(() {
        _statement = s;
        _contact = s.contact;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _record(LedgerKind kind) async {
    final entry = await showQuickEntrySheet(context, initialKind: kind, contact: _contact);
    if (entry != null) _load();
  }

  String _reminderText() {
    final store = context.read<StoreProvider>().myStore?.name ?? 'متجرنا';
    final bal = _statement?.balance ?? _contact.balance;
    return 'السلام عليكم ${_contact.name}،\n'
        'تذكير من $store: المبلغ المتبقّي عليكم ${formatNum(bal)} دينار.\n'
        'نرجو التسديد عند الإمكان، وشكراً لتعاملكم معنا.';
  }

  Future<void> _whatsapp() async {
    final phone = _contact.phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا رقم هاتف لهذا الطرف')));
      return;
    }
    // Iraqi numbers are written 07xx…; WhatsApp wants 9647xx…
    final intl = phone.startsWith('0') ? '964${phone.substring(1)}' : phone;
    final uri = Uri.parse('https://wa.me/$intl?text=${Uri.encodeComponent(_reminderText())}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر فتح واتساب')));
    }
  }

  Future<void> _sharePdf() async {
    final st = _statement;
    if (st == null) return;
    final storeName = context.read<StoreProvider>().myStore?.name ?? '';
    final bytes = await buildStatementPdf(storeName: storeName, statement: st);
    await Printing.sharePdf(bytes: bytes, filename: 'كشف-حساب-${_contact.name}.pdf');
  }

  Future<void> _edit() async {
    final updated = await showEditContactDialog(context, _contact);
    if (updated != null && mounted) setState(() => _contact = updated);
  }

  Future<void> _archive() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('أرشفة الطرف'),
          content: const Text('يختفي من القوائم ويبقى سجلّه محفوظاً. يمكن إرجاعه لاحقاً.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('رجوع')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('أرشفة')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _service.removeContact(_contact.id);
      if (!mounted) return;
      context.read<LedgerProvider>().refreshAfterWrite();
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: AppColors.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rev = context.watch<LedgerProvider>().revision;
    if (rev != _seenRevision) {
      _seenRevision = rev;
      if (_statement != null) WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    final st = _statement;
    final balance = st?.balance ?? _contact.balance;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_contact.name),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) => v == 'edit' ? _edit() : _archive(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('تعديل البيانات')),
                PopupMenuItem(value: 'archive', child: Text('أرشفة')),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
              decoration: BoxDecoration(
                color: balance > 0 ? AppColors.primaryFixed : AppColors.surfaceContainerLow,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    balance > 0
                        ? (_isCustomer ? 'المتبقّي عليه' : 'المتبقّي له عليك')
                        : balance < 0
                            ? (_isCustomer ? 'رصيد له عندك' : 'رصيد لك عنده')
                            : 'الحساب مسدَّد',
                    style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
                  ),
                  Text('${formatNum(balance.abs())} IQD',
                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
                  if (_contact.phone.isNotEmpty)
                    Text(_contact.phone, style: const TextStyle(color: AppColors.onSurfaceVariant)),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _record(_isCustomer ? LedgerKind.paymentIn : LedgerKind.paymentOut),
                          icon: const Icon(Icons.payments_outlined, size: 18),
                          label: Text(_isCustomer ? 'سدّد' : 'ادفع له'),
                          style: FilledButton.styleFrom(backgroundColor: AppColors.success),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _record(_isCustomer ? LedgerKind.saleCredit : LedgerKind.purchase),
                          icon: const Icon(Icons.add, size: 18),
                          label: Text(_isCustomer ? 'دين جديد' : 'شراء جديد'),
                        ),
                      ),
                    ],
                  ),
                  if (_isCustomer && balance > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _whatsapp,
                            icon: const Icon(Icons.chat, size: 18),
                            label: const Text('تذكير واتساب'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: st == null ? null : _sharePdf,
                            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                            label: const Text('كشف PDF'),
                          ),
                        ),
                      ],
                    ),
                  ] else if (st != null && st.rows.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _sharePdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: const Text('كشف حساب PDF'),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: _error != null
                  ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.error)))
                  : st == null
                      ? const Center(child: CircularProgressIndicator())
                      : st.rows.isEmpty
                          ? const Center(
                              child: Text('لا قيود بعد', style: TextStyle(color: AppColors.onSurfaceVariant)))
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.separated(
                                padding: const EdgeInsets.only(top: 8, bottom: 24),
                                // Newest on top for the screen; the PDF keeps ledger order.
                                itemCount: st.rows.length,
                                separatorBuilder: (_, _) => const Divider(height: 1),
                                itemBuilder: (context, i) {
                                  final row = st.rows[st.rows.length - 1 - i];
                                  return LedgerEntryTile(entry: row.entry, runningBalance: row.runningBalance);
                                },
                              ),
                            ),
            ),
            if (st != null && st.rows.isNotEmpty)
              SafeArea(
                top: false,
                child: TextButton.icon(
                  onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => LedgerEntriesScreen(contact: _contact))),
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: const Text('كل القيود بما فيها الملغاة'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
