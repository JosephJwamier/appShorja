import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/ledger.dart';
import '../../providers/ledger_provider.dart';
import '../../services/ledger_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/formatters.dart';
import 'contact_statement_screen.dart';
import 'quick_entry_sheet.dart';

/// «الزبائن» / «المورّدون» — who owes what, biggest first.
class ContactsScreen extends StatefulWidget {
  final ContactKind initialKind;
  const ContactsScreen({super.key, this.initialKind = ContactKind.customer});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  late ContactKind _kind = widget.initialKind;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<LedgerProvider>().loadContacts());
  }

  Future<void> _add() async {
    final created = await showNewContactDialog(context, kind: _kind);
    if (created != null && mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => ContactStatementScreen(contact: created)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ledger = context.watch<LedgerProvider>();
    final all = ledger.contacts.where((c) => c.kind == _kind).toList();
    final list = _query.isEmpty
        ? all
        : all.where((c) => c.name.contains(_query) || c.phone.contains(_query)).toList();
    final total = all.fold<double>(0, (s, c) => s + (c.balance > 0 ? c.balance : 0));
    final isCustomer = _kind == ContactKind.customer;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(isCustomer ? 'الزبائن' : 'المورّدون')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _add,
          icon: const Icon(Icons.person_add_alt_1),
          label: Text(isCustomer ? 'زبون جديد' : 'مورّد جديد'),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: SegmentedButton<ContactKind>(
                segments: const [
                  ButtonSegment(value: ContactKind.customer, label: Text('الزبائن'), icon: Icon(Icons.people_outline)),
                  ButtonSegment(value: ContactKind.supplier, label: Text('المورّدون'), icon: Icon(Icons.local_shipping_outlined)),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isCustomer ? AppColors.primaryFixed : AppColors.secondaryFixed,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        isCustomer ? 'مجموع الديون لك' : 'مجموع ما عليك',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text('${formatNum(total)} IQD',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'ابحث بالاسم أو الهاتف',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => ledger.loadContacts(),
                child: ledger.loadingContacts && all.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : list.isEmpty
                        ? ListView(children: [
                            const SizedBox(height: 60),
                            Icon(isCustomer ? Icons.people_outline : Icons.local_shipping_outlined,
                                size: 56, color: AppColors.outline),
                            const SizedBox(height: 12),
                            Center(
                              child: Text(
                                _query.isEmpty
                                    ? (isCustomer ? 'لا زبائن بعد' : 'لا مورّدين بعد')
                                    : 'لا نتائج',
                                style: const TextStyle(color: AppColors.onSurfaceVariant),
                              ),
                            ),
                          ])
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 90),
                            itemCount: list.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final c = list[i];
                              final open = c.balance > 0;
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: open ? AppColors.primaryFixed : AppColors.surfaceContainer,
                                  child: Text(c.name.characters.first,
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: open ? AppColors.onPrimaryFixed : AppColors.onSurfaceVariant)),
                                ),
                                title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: c.phone.isEmpty ? null : Text(c.phone),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      formatNum(c.balance),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                        color: open ? AppColors.primaryContainer : AppColors.onSurfaceVariant,
                                      ),
                                    ),
                                    Text(
                                      c.balance == 0
                                          ? 'مسدَّد'
                                          : c.balance < 0
                                              ? (isCustomer ? 'له رصيد' : 'لك رصيد')
                                              : (isCustomer ? 'عليه' : 'له عليك'),
                                      style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                                onTap: () => Navigator.push(
                                  context, MaterialPageRoute(builder: (_) => ContactStatementScreen(contact: c))),
                              );
                            },
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Edit name/phone/notes, or archive. Used from the statement screen.
Future<LedgerContact?> showEditContactDialog(BuildContext context, LedgerContact contact) {
  return showDialog<LedgerContact>(
    context: context,
    builder: (_) => _EditContactDialog(contact: contact),
  );
}

class _EditContactDialog extends StatefulWidget {
  final LedgerContact contact;
  const _EditContactDialog({required this.contact});
  @override
  State<_EditContactDialog> createState() => _EditContactDialogState();
}

class _EditContactDialogState extends State<_EditContactDialog> {
  late final _name = TextEditingController(text: widget.contact.name);
  late final _phone = TextEditingController(text: widget.contact.phone);
  late final _notes = TextEditingController(text: widget.contact.notes);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final c = await LedgerService().updateContact(
        widget.contact.id,
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        notes: _notes.text.trim(),
      );
      if (!mounted) return;
      context.read<LedgerProvider>().loadContacts();
      Navigator.pop(context, c);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('تعديل البيانات'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'الاسم')),
            TextField(controller: _phone, keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'الهاتف')),
            TextField(controller: _notes, maxLines: 2,
                decoration: const InputDecoration(labelText: 'ملاحظات')),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12.5)),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(onPressed: _saving ? null : _save, child: const Text('حفظ')),
        ],
      ),
    );
  }
}
