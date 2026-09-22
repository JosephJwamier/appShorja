import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/ledger.dart';
import '../../providers/ledger_provider.dart';
import '../../services/ledger_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/formatters.dart';
import 'quick_entry_sheet.dart';

/// «الدفتر» — every entry, newest first, with the filters a merchant
/// actually uses (what came in, what went out, what the app sold).
class LedgerEntriesScreen extends StatefulWidget {
  /// Narrow the book to one contact (opened from their statement).
  final LedgerContact? contact;
  const LedgerEntriesScreen({super.key, this.contact});

  @override
  State<LedgerEntriesScreen> createState() => _LedgerEntriesScreenState();
}

enum _Filter { all, sales, expenses, debts, app, voided }

class _LedgerEntriesScreenState extends State<LedgerEntriesScreen> {
  final _service = LedgerService();
  final _scroll = ScrollController();
  final List<LedgerEntry> _entries = [];
  _Filter _filter = _Filter.all;
  int _page = 1;
  bool _hasMore = true;
  bool _loading = false;
  String? _error;
  int _seenRevision = -1;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _loadMore();
    });
    _reload();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<LedgerKind>? get _kinds => switch (_filter) {
        _Filter.sales => [LedgerKind.saleCash, LedgerKind.saleCredit, LedgerKind.saleApp],
        _Filter.expenses => [LedgerKind.expense, LedgerKind.purchase, LedgerKind.paymentOut],
        _Filter.debts => [LedgerKind.saleCredit, LedgerKind.paymentIn],
        _ => null,
      };

  Future<void> _reload() async {
    setState(() {
      _entries.clear();
      _page = 1;
      _hasMore = true;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final r = await _service.fetchEntries(
        page: _page,
        kinds: _kinds,
        contactId: widget.contact?.id,
        fromApp: _filter == _Filter.app ? true : null,
        includeVoid: _filter == _Filter.voided,
      );
      var list = r.entries;
      if (_filter == _Filter.voided) list = list.where((e) => e.isVoid).toList();
      setState(() {
        _entries.addAll(list);
        _hasMore = r.hasMore;
        _page++;
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _void(LedgerEntry e) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إلغاء القيد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${e.kind.label} — ${formatNum(e.amount)} IQD\nيبقى في السجل مؤشَّراً كملغى'
                  '${e.quantity != null && e.quantity! > 0 ? '، وتعود الكمية للمخزون' : ''}.'),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: 'السبب (اختياري)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('رجوع')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إلغاء القيد'),
            ),
          ],
        ),
      ),
    );
    final reason = controller.text.trim();
    controller.dispose();
    if (ok != true) return;
    try {
      await _service.voidEntry(e.id, reason: reason);
      if (!mounted) return;
      context.read<LedgerProvider>().refreshAfterWrite();
      await _reload();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err.toString().replaceFirst('Exception: ', '')),
        backgroundColor: AppColors.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Someone wrote an entry elsewhere (dashboard buttons): refetch.
    final rev = context.watch<LedgerProvider>().revision;
    if (rev != _seenRevision) {
      _seenRevision = rev;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _seenRevision == rev && _entries.isNotEmpty) _reload();
      });
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.contact == null ? 'الدفتر' : 'دفتر ${widget.contact!.name}'),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            final entry = await showQuickEntrySheet(context, contact: widget.contact);
            if (entry != null) _reload();
          },
          icon: const Icon(Icons.add),
          label: const Text('قيد جديد'),
        ),
        body: Column(
          children: [
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  for (final f in _Filter.values) ...[
                    ChoiceChip(
                      label: Text(_label(f)),
                      selected: _filter == f,
                      onSelected: (_) {
                        setState(() => _filter = f);
                        _reload();
                      },
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _reload,
                child: _error != null
                    ? ListView(children: [
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!, textAlign: TextAlign.center,
                              style: const TextStyle(color: AppColors.error)),
                        ),
                      ])
                    : _entries.isEmpty && !_loading
                        ? ListView(children: const [
                            SizedBox(height: 80),
                            Icon(Icons.menu_book_outlined, size: 56, color: AppColors.outline),
                            SizedBox(height: 12),
                            Center(child: Text('الدفتر فارغ هنا', style: TextStyle(color: AppColors.onSurfaceVariant))),
                          ])
                        : ListView.separated(
                            controller: _scroll,
                            padding: const EdgeInsets.only(bottom: 90),
                            itemCount: _entries.length + (_hasMore ? 1 : 0),
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              if (i >= _entries.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(child: CircularProgressIndicator()),
                                );
                              }
                              final e = _entries[i];
                              final showDate = i == 0 || !_sameDay(_entries[i - 1].occurredAt, e.occurredAt);
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (showDate)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                                      child: Text(_dayLabel(e.occurredAt),
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.onSurfaceVariant)),
                                    ),
                                  LedgerEntryTile(
                                    entry: e,
                                    onVoid: e.isVoid || e.fromApp ? null : () => _void(e),
                                  ),
                                ],
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

  static String _label(_Filter f) => switch (f) {
        _Filter.all => 'الكل',
        _Filter.sales => 'المبيعات',
        _Filter.expenses => 'المصاريف',
        _Filter.debts => 'الديون',
        _Filter.app => 'التطبيق',
        _Filter.voided => 'الملغاة',
      };

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  static String _dayLabel(DateTime d) {
    final now = DateTime.now();
    if (_sameDay(d, now)) return 'اليوم';
    if (_sameDay(d, now.subtract(const Duration(days: 1)))) return 'أمس';
    return '${d.day}/${d.month}/${d.year}';
  }
}

/// One line of the book. Shared with the statement screen.
class LedgerEntryTile extends StatelessWidget {
  final LedgerEntry entry;
  final VoidCallback? onVoid;
  /// Statement mode: show the running balance instead of the kind pill.
  final double? runningBalance;

  const LedgerEntryTile({super.key, required this.entry, this.onVoid, this.runningBalance});

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final color = e.isVoid
        ? AppColors.outline
        : e.kind.isIn
            ? AppColors.success
            : AppColors.error;
    final sign = e.kind.isIn ? '+' : '−';
    return ListTile(
      leading: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(_icon(e.kind), color: color, size: 22),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              e.kind.label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                decoration: e.isVoid ? TextDecoration.lineThrough : null,
                color: e.isVoid ? AppColors.outline : null,
              ),
            ),
          ),
          if (e.fromApp)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(Icons.phone_android, size: 14, color: AppColors.primaryContainer),
            ),
        ],
      ),
      subtitle: Text(
        e.isVoid ? 'ملغى${e.voidReason.isEmpty ? '' : ' — ${e.voidReason}'}' : e.subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '$sign${formatNum(e.amount)}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: color,
              decoration: e.isVoid ? TextDecoration.lineThrough : null,
            ),
          ),
          if (runningBalance != null)
            Text('الرصيد ${formatNum(runningBalance!)}',
                style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant))
          else
            Text(_time(e.occurredAt), style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
        ],
      ),
      onLongPress: onVoid,
      onTap: onVoid == null
          ? null
          : () => showModalBottomSheet(
                context: context,
                builder: (_) => Directionality(
                  textDirection: TextDirection.rtl,
                  child: SafeArea(
                    child: ListTile(
                      leading: const Icon(Icons.block, color: AppColors.error),
                      title: const Text('إلغاء هذا القيد'),
                      subtitle: const Text('يبقى في السجل مؤشَّراً كملغى'),
                      onTap: () {
                        Navigator.pop(context);
                        onVoid!();
                      },
                    ),
                  ),
                ),
              ),
    );
  }

  static IconData _icon(LedgerKind k) => switch (k) {
        LedgerKind.saleCash => Icons.point_of_sale,
        LedgerKind.saleCredit => Icons.receipt_long,
        LedgerKind.saleApp => Icons.phone_android,
        LedgerKind.paymentIn => Icons.call_received,
        LedgerKind.expense => Icons.payments_outlined,
        LedgerKind.purchase => Icons.inventory_2_outlined,
        LedgerKind.paymentOut => Icons.call_made,
      };

  static String _time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
