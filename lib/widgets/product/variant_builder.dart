import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/product.dart';
import '../../theme/app_colors.dart';

/// What the seller defines: the axes, and stock/price per combination.
///
/// Held as plain data so the add-item screen can serialise it straight into
/// the multipart form (`options` and `variants` as JSON strings — the server
/// decodes them).
class VariantDraft {
  /// [{'name': 'اللون', 'values': ['أحمر', 'أزرق']}]
  final List<OptionDraft> options;

  /// Keyed by the combination's attribute map, encoded as a stable string.
  final Map<String, VariantRow> rows;

  VariantDraft({List<OptionDraft>? options, Map<String, VariantRow>? rows})
    : options = options ?? [],
      rows = rows ?? {};

  /// Pre-fills the edit screen from what the server holds. Retired
  /// (inactive) combinations are left out of the grid: resending the table
  /// without them keeps them retired, and re-adding the value brings them
  /// back — both handled server-side by attribute match.
  factory VariantDraft.fromProduct(Product product) {
    final draft = VariantDraft(
      options: [
        for (final o in product.options)
          OptionDraft(name: o.name, values: List.of(o.values)),
      ],
    );
    for (final v in product.variants) {
      if (!v.isActive) continue;
      draft.rows[keyFor(v.attributes)] = VariantRow(
        quantity: v.quantity,
        price: v.price,
        costPrice: v.costPrice,
      );
    }
    return draft;
  }

  bool get hasOptions => options.any((o) => o.values.isNotEmpty);

  /// Cartesian product of every option's values, in declaration order.
  List<Map<String, String>> get combinations {
    final axes = options
        .where((o) => o.name.trim().isNotEmpty && o.values.isNotEmpty)
        .toList();
    if (axes.isEmpty) return const [];
    var acc = <Map<String, String>>[{}];
    for (final axis in axes) {
      acc = [
        for (final partial in acc)
          for (final value in axis.values)
            {...partial, axis.name.trim(): value},
      ];
    }
    return acc;
  }

  static String keyFor(Map<String, String> attrs) {
    final entries = attrs.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries.map((e) => '${e.key}=${e.value}').join('|');
  }

  VariantRow rowFor(Map<String, String> attrs) =>
      rows.putIfAbsent(keyFor(attrs), VariantRow.new);

  int get totalQuantity =>
      combinations.fold(0, (sum, c) => sum + (rowFor(c).quantity ?? 0));

  /// Same rules the server applies, checked here so the seller sees the
  /// problem next to the form instead of after the image upload.
  String? validate() {
    if (options.isEmpty) return 'أضف خياراً واحداً على الأقل أو أطفئ الخيارات';
    final names = <String>{};
    for (final o in options) {
      final name = o.name.trim();
      if (name.isEmpty) return 'كل خيار يحتاج اسماً';
      if (o.values.isEmpty) return 'الخيار "$name" بلا قيم';
      if (!names.add(name)) return 'اسم الخيار "$name" مكرّر';
    }
    if (totalQuantity < 1) return 'أدخل كمية لمجموعة واحدة على الأقل';
    return null;
  }

  List<Map<String, dynamic>> optionsJson() => [
    for (final o in options)
      if (o.name.trim().isNotEmpty && o.values.isNotEmpty)
        {'name': o.name.trim(), 'values': o.values},
  ];

  List<Map<String, dynamic>> variantsJson() => [
    for (final c in combinations)
      {
        'attributes': c,
        'quantity': rowFor(c).quantity ?? 0,
        if (rowFor(c).price != null) 'price': rowFor(c).price,
        if (rowFor(c).costPrice != null) 'cost_price': rowFor(c).costPrice,
      },
  ];
}

class OptionDraft {
  String name;
  List<String> values;
  OptionDraft({this.name = '', List<String>? values}) : values = values ?? [];
}

class VariantRow {
  int? quantity;
  double? price;

  /// Seller's cost per unit — feeds the dashboard's profit figure.
  double? costPrice;
  VariantRow({this.quantity, this.price, this.costPrice});
}

/// Seller UI: declare options (name + values), then fill stock and optional
/// price for every generated combination.
///
/// The table is derived from the options rather than hand-built: a seller
/// with three colours and four sizes gets twelve rows without typing twelve
/// combinations, and cannot produce a combination the options don't allow —
/// which is the same rule the server validates.
class VariantBuilder extends StatefulWidget {
  final VariantDraft draft;
  final VoidCallback onChanged;

  const VariantBuilder({
    super.key,
    required this.draft,
    required this.onChanged,
  });

  @override
  State<VariantBuilder> createState() => _VariantBuilderState();
}

class _VariantBuilderState extends State<VariantBuilder> {
  VariantDraft get draft => widget.draft;

  void _notify() {
    setState(() {});
    widget.onChanged();
  }

  void _addOption() {
    draft.options.add(OptionDraft());
    _notify();
  }

  void _removeOption(int index) {
    draft.options.removeAt(index);
    _notify();
  }

  Future<void> _addValue(OptionDraft option) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _NewValueDialog(optionName: option.name.trim()),
    );
    if (!mounted) return;
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty || option.values.contains(trimmed)) return;
    option.values.add(trimmed);
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < draft.options.length; i++) _buildOption(i),
        OutlinedButton.icon(
          onPressed: draft.options.length >= 3 ? null : _addOption,
          icon: const Icon(Icons.add),
          label: Text(
            draft.options.isEmpty ? 'إضافة خيار (لون، مقاس…)' : 'خيار آخر',
          ),
        ),
        if (draft.options.length >= 3)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'ثلاثة خيارات كحدّ أقصى',
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
        if (draft.combinations.isNotEmpty) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              const Text(
                'المخزون لكل مجموعة',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                'الإجمالي: ${draft.totalQuantity}',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'السعر اختياري — فارغ = سعر المنتج الأساسي. الكلفة لك وحدك: تُحسب منها أرباحك في لوحة المتجر.',
            style: TextStyle(fontSize: 11.5, color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          for (final combo in draft.combinations) _buildRow(combo),
        ],
      ],
    );
  }

  Widget _buildOption(int index) {
    final option = draft.options[index];
    // Keyed by identity: deleting option 0 must not leave option 1's field
    // showing option 0's text.
    return Container(
      key: ObjectKey(option),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceContainer),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: option.name,
                  decoration: const InputDecoration(
                    labelText: 'اسم الخيار',
                    hintText: 'اللون / المقاس / السعة',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    option.name = v;
                    _notify();
                  },
                ),
              ),
              IconButton(
                tooltip: 'حذف الخيار',
                icon: const Icon(Icons.delete_outline, color: AppColors.error),
                onPressed: () => _removeOption(index),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in option.values)
                InputChip(
                  label: Text(value),
                  onDeleted: () {
                    option.values.remove(value);
                    _notify();
                  },
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: const Text('قيمة'),
                onPressed: () => _addValue(option),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRow(Map<String, String> combo) {
    return _VariantRowFields(
      key: ValueKey(VariantDraft.keyFor(combo)),
      combo: combo,
      row: draft.rowFor(combo),
      onChanged: _notify,
    );
  }
}

/// Owns its text controller so it outlives the dialog's exit animation —
/// disposing it from the caller the moment `showDialog` returns tears the
/// controller out from under a TextField that is still on screen.
class _NewValueDialog extends StatefulWidget {
  final String optionName;
  const _NewValueDialog({required this.optionName});

  @override
  State<_NewValueDialog> createState() => _NewValueDialogState();
}

class _NewValueDialogState extends State<_NewValueDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(
          'قيمة جديدة${widget.optionName.isEmpty ? '' : ' لـ${widget.optionName}'}',
        ),
        content: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'مثال: أحمر، L، 128GB'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _controller.text),
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }
}

/// One grid row. Kept stateful with its own controllers so a rebuild of the
/// whole table (every keystroke triggers one) never resets what the seller
/// is typing — `initialValue` fields would.
class _VariantRowFields extends StatefulWidget {
  final Map<String, String> combo;
  final VariantRow row;
  final VoidCallback onChanged;

  const _VariantRowFields({
    super.key,
    required this.combo,
    required this.row,
    required this.onChanged,
  });

  @override
  State<_VariantRowFields> createState() => _VariantRowFieldsState();
}

class _VariantRowFieldsState extends State<_VariantRowFields> {
  late final _quantity = TextEditingController(
    text: widget.row.quantity?.toString() ?? '',
  );
  late final _price = TextEditingController(
    text: widget.row.price?.toStringAsFixed(0) ?? '',
  );
  late final _cost = TextEditingController(
    text: widget.row.costPrice?.toStringAsFixed(0) ?? '',
  );

  @override
  void dispose() {
    _quantity.dispose();
    _price.dispose();
    _cost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final combo = widget.combo;
    final row = widget.row;
    // Label on its own line: three fields already fill a phone's width.
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            combo.values.join(' / '),
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _quantity,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    labelText: 'الكمية',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    row.quantity = int.tryParse(v);
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: TextFormField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    labelText: 'السعر',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    row.price = double.tryParse(v);
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: TextFormField(
                  controller: _cost,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    labelText: 'الكلفة',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    row.costPrice = double.tryParse(v);
                    widget.onChanged();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
