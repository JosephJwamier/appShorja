import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/ledger.dart';
import '../../models/product.dart';
import '../../providers/auth_provider.dart';
import '../../providers/ledger_provider.dart';
import '../../providers/my_items_provider.dart';
import '../../services/ledger_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/formatters.dart';

/// The "write it in the book" sheet. Opened with a preset kind from the
/// dashboard's big buttons, or blank from the ledger screen. Returns the
/// created entry, or null if dismissed.
Future<LedgerEntry?> showQuickEntrySheet(
  BuildContext context, {
  LedgerKind? initialKind,
  LedgerContact? contact,
}) {
  return showModalBottomSheet<LedgerEntry>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _QuickEntrySheet(initialKind: initialKind, presetContact: contact),
  );
}

class _QuickEntrySheet extends StatefulWidget {
  final LedgerKind? initialKind;
  final LedgerContact? presetContact;
  const _QuickEntrySheet({this.initialKind, this.presetContact});

  @override
  State<_QuickEntrySheet> createState() => _QuickEntrySheetState();
}

class _QuickEntrySheetState extends State<_QuickEntrySheet> {
  late LedgerKind _kind = widget.initialKind ?? LedgerKind.saleCash;
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _qty = TextEditingController(text: '1');
  LedgerContact? _contact;
  String _expenseCategory = 'other';
  DateTime _occurredAt = DateTime.now();
  bool _fromStock = false;
  Product? _item;
  Map<String, String> _variantPick = {};
  XFile? _receipt;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _contact = widget.presetContact;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ledger = context.read<LedgerProvider>();
      if (ledger.contacts.isEmpty) ledger.loadContacts();
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _qty.dispose();
    super.dispose();
  }

  double get _amountValue => double.tryParse(_amount.text.replaceAll(',', '')) ?? 0;

  void _bump(int by) {
    final next = _amountValue + by;
    _amount.text = next.toStringAsFixed(0);
    _amount.selection = TextSelection.collapsed(offset: _amount.text.length);
    setState(() {});
  }

  ProductVariant? get _variant {
    final item = _item;
    if (item == null) return null;
    if (!item.hasOptions) return item.variants.isEmpty ? null : item.variants.first;
    return item.findVariant(_variantPick);
  }

  /// Picking a product pre-fills the price so a shop sale is two taps.
  void _onPickItem(Product? item) {
    setState(() {
      _item = item;
      _variantPick = {};
      _suggestPrice();
    });
  }

  void _suggestPrice() {
    final v = _variant;
    final unit = v?.effectivePrice ?? _item?.price;
    final qty = int.tryParse(_qty.text) ?? 1;
    if (unit != null && unit > 0) {
      _amount.text = (unit * qty).toStringAsFixed(0);
    }
  }

  Future<void> _pickReceipt() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 70);
    if (picked != null) setState(() => _receipt = picked);
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 3)),
      lastDate: DateTime.now(),
    );
    if (d != null) {
      setState(() => _occurredAt = DateTime(d.year, d.month, d.day, _occurredAt.hour, _occurredAt.minute));
    }
  }

  Future<void> _addContactInline() async {
    final wanted = _kind.contactKind ?? ContactKind.customer;
    final created = await showNewContactDialog(context, kind: wanted);
    if (created != null && mounted) setState(() => _contact = created);
  }

  Future<void> _submit() async {
    final amount = _amountValue;
    if (amount <= 0) {
      setState(() => _error = 'أدخل المبلغ');
      return;
    }
    final wanted = _kind.contactKind;
    if (wanted != null && (_contact == null || _contact!.kind != wanted)) {
      setState(() => _error = wanted == ContactKind.customer ? 'اختر الزبون' : 'اختر المورّد');
      return;
    }
    int? qty;
    if (_fromStock) {
      if (_item == null) {
        setState(() => _error = 'اختر المنتج');
        return;
      }
      if (_variant == null) {
        setState(() => _error = 'اختر مواصفات المنتج');
        return;
      }
      qty = int.tryParse(_qty.text) ?? 0;
      if (qty < 1) {
        setState(() => _error = 'أدخل الكمية');
        return;
      }
      if (qty > _variant!.quantity) {
        setState(() => _error = 'المتوفّر ${_variant!.quantity} فقط');
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthProvider>();
      final entry = await LedgerService().createEntry(
        accessToken: auth.accessToken!,
        kind: _kind,
        amount: amount,
        contactId: wanted != null || _kind == LedgerKind.saleCash ? _contact?.id : null,
        note: _note.text.trim(),
        occurredAt: _occurredAt,
        expenseCategory: _kind == LedgerKind.expense ? _expenseCategory : null,
        itemId: _fromStock ? _item!.id : null,
        variantId: _fromStock ? _variant!.id : null,
        quantity: _fromStock ? qty : null,
        receipt: _receipt,
      );
      if (!mounted) return;
      // Refresh in the background; the caller shouldn't wait on it.
      context.read<LedgerProvider>().refreshAfterWrite();
      if (_fromStock) {
        // The shelf changed: my-items list should show the new count.
        context.read<MyItemsProvider>().loadMyItems(
          accessToken: auth.accessToken!, ownerId: auth.user!.id);
      }
      Navigator.pop(context, entry);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final wantedContact = _kind.contactKind;
    final showsContact = wantedContact != null || _kind == LedgerKind.saleCash;
    final canLinkStock = _kind == LedgerKind.saleCash || _kind == LedgerKind.saleCredit;
    if (!canLinkStock && _fromStock) _fromStock = false;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.86,
          maxChildSize: 0.96,
          minChildSize: 0.5,
          builder: (context, scroll) => Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 42, height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh, borderRadius: BorderRadius.circular(999)),
                ),
                Expanded(
                  child: ListView(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                    children: [
                      const Text('قيد جديد',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 12),
                      // ── kind ──
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final k in LedgerKind.manual)
                            ChoiceChip(
                              label: Text(k.label),
                              selected: _kind == k,
                              selectedColor: k.isIn ? const Color(0xFFE3F4E5) : AppColors.errorContainer,
                              labelStyle: TextStyle(
                                fontWeight: _kind == k ? FontWeight.bold : FontWeight.w500,
                                color: _kind == k
                                    ? (k.isIn ? AppColors.success : AppColors.onErrorContainer)
                                    : AppColors.onSurface,
                              ),
                              onSelected: (_) => setState(() {
                                _kind = k;
                                // A contact of the wrong kind can't stay picked.
                                final want = k.contactKind;
                                if (want != null && _contact?.kind != want) _contact = null;
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      // ── amount ──
                      TextField(
                        controller: _amount,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        autofocus: widget.initialKind != null,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                        decoration: InputDecoration(
                          labelText: 'المبلغ (IQD)',
                          border: const OutlineInputBorder(),
                          suffixIcon: _amount.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () => setState(() => _amount.clear())),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final v in const [1000, 5000, 25000, 50000, 100000])
                            ActionChip(
                              label: Text('+${formatNum(v.toDouble())}'),
                              onPressed: () => _bump(v),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                      // ── contact ──
                      if (showsContact) ...[
                        const SizedBox(height: 18),
                        _ContactField(
                          kind: wantedContact ?? ContactKind.customer,
                          required: wantedContact != null,
                          selected: _contact,
                          onChanged: (c) => setState(() => _contact = c),
                          onAddNew: _addContactInline,
                        ),
                      ],
                      // ── expense category ──
                      if (_kind == LedgerKind.expense) ...[
                        const SizedBox(height: 18),
                        const Text('التصنيف', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final e in expenseCategories.entries)
                              ChoiceChip(
                                label: Text(e.value),
                                selected: _expenseCategory == e.key,
                                onSelected: (_) => setState(() => _expenseCategory = e.key),
                              ),
                          ],
                        ),
                      ],
                      // ── stock link ──
                      if (canLinkStock) ...[
                        const SizedBox(height: 10),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('من المخزون؟', style: TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: const Text('يُنقص الكمية من المنتج نفسه الذي يراه مشتري التطبيق',
                              style: TextStyle(fontSize: 12)),
                          value: _fromStock,
                          onChanged: (v) => setState(() => _fromStock = v),
                        ),
                        if (_fromStock) _StockPicker(
                          item: _item,
                          pick: _variantPick,
                          variant: _variant,
                          qtyController: _qty,
                          onItem: _onPickItem,
                          onPick: (p) => setState(() {
                            _variantPick = p;
                            _suggestPrice();
                          }),
                          onQtyChanged: () => setState(_suggestPrice),
                        ),
                      ],
                      // ── note / date / receipt ──
                      const SizedBox(height: 14),
                      TextField(
                        controller: _note,
                        decoration: const InputDecoration(
                          labelText: 'ملاحظة (اختياري)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _pickDate,
                              icon: const Icon(Icons.event, size: 18),
                              label: Text(_dateLabel(_occurredAt)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _pickReceipt,
                              icon: Icon(_receipt == null ? Icons.photo_camera_outlined : Icons.check_circle, size: 18),
                              label: Text(_receipt == null ? 'صورة وصل' : 'أُرفق الوصل'),
                            ),
                          ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          onPressed: _saving ? null : _submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: _kind.isIn ? AppColors.success : AppColors.primary,
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 22, height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Text(
                                  _amountValue > 0
                                      ? 'تسجيل ${_kind.label} — ${formatNum(_amountValue)}'
                                      : 'تسجيل ${_kind.label}',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _dateLabel(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) return 'اليوم';
    return '${d.day}/${d.month}/${d.year}';
  }
}

// ── contact picker ──────────────────────────────────────────────────────

class _ContactField extends StatelessWidget {
  final ContactKind kind;
  final bool required;
  final LedgerContact? selected;
  final ValueChanged<LedgerContact?> onChanged;
  final VoidCallback onAddNew;

  const _ContactField({
    required this.kind,
    required this.required,
    required this.selected,
    required this.onChanged,
    required this.onAddNew,
  });

  @override
  Widget build(BuildContext context) {
    final label = kind == ContactKind.customer ? 'الزبون' : 'المورّد';
    return Consumer<LedgerProvider>(
      builder: (context, ledger, _) {
        final options = ledger.contacts.where((c) => c.kind == kind).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(required ? label : '$label (اختياري)',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton.icon(
                  onPressed: onAddNew,
                  icon: const Icon(Icons.person_add_alt_1, size: 18),
                  label: const Text('جديد'),
                ),
              ],
            ),
            if (options.isEmpty)
              Text(
                kind == ContactKind.customer ? 'لا زبائن بعد — أضف الأول' : 'لا مورّدين بعد — أضف الأول',
                style: const TextStyle(fontSize: 12.5, color: AppColors.onSurfaceVariant),
              )
            else
              Autocomplete<LedgerContact>(
                key: ValueKey(selected?.id),
                initialValue: TextEditingValue(text: selected?.name ?? ''),
                displayStringForOption: (c) => c.name,
                optionsBuilder: (v) {
                  final q = v.text.trim();
                  if (q.isEmpty) return options;
                  return options.where((c) => c.name.contains(q) || c.phone.contains(q));
                },
                onSelected: onChanged,
                fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
                  controller: controller,
                  focusNode: focus,
                  decoration: InputDecoration(
                    hintText: 'ابحث بالاسم أو الهاتف',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: selected == null
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              controller.clear();
                              onChanged(null);
                            }),
                  ),
                  onChanged: (v) {
                    if (selected != null && v != selected!.name) onChanged(null);
                  },
                ),
                optionsViewBuilder: (context, onSelect, opts) => Align(
                  alignment: Alignment.topRight,
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(10),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220, maxWidth: 360),
                      child: ListView(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        children: [
                          for (final c in opts)
                            ListTile(
                              dense: true,
                              title: Text(c.name),
                              subtitle: c.phone.isEmpty ? null : Text(c.phone),
                              trailing: c.balance == 0
                                  ? null
                                  : Text(formatNum(c.balance),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold, color: AppColors.primaryContainer)),
                              onTap: () => onSelect(c),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (selected != null && selected!.balance != 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  kind == ContactKind.customer
                      ? 'عليه حالياً ${formatNum(selected!.balance)} IQD'
                      : 'له عليك حالياً ${formatNum(selected!.balance)} IQD',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.onSurfaceVariant),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Small dialog to add a customer/supplier without leaving the sheet.
Future<LedgerContact?> showNewContactDialog(BuildContext context, {required ContactKind kind}) {
  return showDialog<LedgerContact>(
    context: context,
    builder: (_) => _NewContactDialog(kind: kind),
  );
}

class _NewContactDialog extends StatefulWidget {
  final ContactKind kind;
  const _NewContactDialog({required this.kind});
  @override
  State<_NewContactDialog> createState() => _NewContactDialogState();
}

class _NewContactDialogState extends State<_NewContactDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'الاسم مطلوب');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final c = await LedgerService().createContact(
        name: _name.text.trim(), kind: widget.kind, phone: _phone.text.trim());
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
        title: Text(widget.kind == ContactKind.customer ? 'زبون جديد' : 'مورّد جديد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'الاسم'),
            ),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'الهاتف (اختياري)'),
            ),
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

// ── stock picker ────────────────────────────────────────────────────────

class _StockPicker extends StatelessWidget {
  final Product? item;
  final Map<String, String> pick;
  final ProductVariant? variant;
  final TextEditingController qtyController;
  final ValueChanged<Product?> onItem;
  final ValueChanged<Map<String, String>> onPick;
  final VoidCallback onQtyChanged;

  const _StockPicker({
    required this.item,
    required this.pick,
    required this.variant,
    required this.qtyController,
    required this.onItem,
    required this.onPick,
    required this.onQtyChanged,
  });

  @override
  Widget build(BuildContext context) {
    final items = context.watch<MyItemsProvider>().items
        .where((p) => p.status == 'active' || p.status == 'sold')
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<int>(
          key: ValueKey(item?.id),
          initialValue: item?.id,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'المنتج', border: OutlineInputBorder(), isDense: true),
          items: [
            for (final p in items)
              DropdownMenuItem(
                value: p.id,
                child: Text('${p.title}  (${p.quantity})', overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (id) => onItem(id == null ? null : items.firstWhere((p) => p.id == id)),
        ),
        if (item != null && item!.hasOptions) ...[
          const SizedBox(height: 10),
          for (final o in item!.options) ...[
            Text(o.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                for (final v in o.values)
                  ChoiceChip(
                    label: Text(v),
                    selected: pick[o.name] == v,
                    onSelected: (_) {
                      final next = Map<String, String>.from(pick);
                      next[o.name] = v;
                      onPick(next);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 6),
          ],
        ],
        if (item != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              SizedBox(
                width: 110,
                child: TextField(
                  controller: qtyController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    labelText: 'الكمية', border: OutlineInputBorder(), isDense: true),
                  onChanged: (_) => onQtyChanged(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  variant == null
                      ? 'اختر المواصفات'
                      : 'المتوفّر: ${variant!.quantity}'
                          '${variant!.effectivePrice != null ? ' · السعر ${formatNum(variant!.effectivePrice!)}' : ''}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: variant != null && variant!.quantity == 0 ? AppColors.error : AppColors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
