import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/ledger.dart';
import '../../providers/ledger_provider.dart';
import '../../theme/app_colors.dart';
import '../../utils/formatters.dart';
import '../../widgets/ledger/sales_bar_chart.dart';
import 'contact_statement_screen.dart';
import 'contacts_screen.dart';
import 'ledger_entries_screen.dart';
import 'quick_entry_sheet.dart';

/// «لوحة» — first tab of متجري. Money from the book, operations from the
/// app, and the three big buttons the merchant reaches for all day.
class StoreDashboardTab extends StatefulWidget {
  const StoreDashboardTab({super.key});

  @override
  State<StoreDashboardTab> createState() => _StoreDashboardTabState();
}

class _StoreDashboardTabState extends State<StoreDashboardTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ledger = context.read<LedgerProvider>();
      if (ledger.dashboard == null) ledger.loadDashboard();
      if (ledger.contacts.isEmpty) ledger.loadContacts();
    });
  }

  Future<void> _quick(LedgerKind kind) async {
    final entry = await showQuickEntrySheet(context, initialKind: kind);
    if (entry != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('سُجّل: ${entry.kind.label} ${formatNum(entry.amount)} IQD'),
        backgroundColor: AppColors.success,
      ));
    }
  }

  Future<void> _pickCustomRange(LedgerProvider ledger) async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: ledger.customStart != null && ledger.customEnd != null
          ? DateTimeRange(start: ledger.customStart!, end: ledger.customEnd!)
          : null,
    );
    if (range != null) {
      ledger.loadDashboard(period: 'custom', start: range.start, end: range.end);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LedgerProvider>(
      builder: (context, ledger, _) {
        final d = ledger.dashboard;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: [
            _QuickButtons(onTap: _quick),
            const SizedBox(height: 18),
            _PeriodChips(
              selected: ledger.period,
              onSelect: (p) => p == 'custom' ? _pickCustomRange(ledger) : ledger.loadDashboard(period: p),
            ),
            const SizedBox(height: 12),
            if (ledger.dashboardError != null)
              _ErrorBox(message: ledger.dashboardError!, onRetry: () => ledger.loadDashboard())
            else if (d == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _MoneyTiles(d: d),
              const SizedBox(height: 12),
              _Breakdown(d: d),
              const SizedBox(height: 16),
              _Card(
                title: 'المبيعات يومياً',
                child: SalesBarChart(points: d.summary.daily, start: d.summary.start, end: d.summary.end),
              ),
              const SizedBox(height: 12),
              _NeedsAction(d: d),
              const SizedBox(height: 12),
              _Debtors(d: d),
              const SizedBox(height: 12),
              if (d.topItems.isNotEmpty) _TopItems(d: d),
              const SizedBox(height: 12),
              _Links(),
            ],
          ],
        );
      },
    );
  }
}

// ── quick buttons ────────────────────────────────────────────────────────

class _QuickButtons extends StatelessWidget {
  final ValueChanged<LedgerKind> onTap;
  const _QuickButtons({required this.onTap});

  @override
  Widget build(BuildContext context) {
    Widget button(LedgerKind kind, IconData icon, Color color) => Expanded(
          child: Material(
            color: color,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => onTap(kind),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    Icon(icon, color: Colors.white, size: 26),
                    const SizedBox(height: 6),
                    Text(kind.label,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
        );
    return Row(
      children: [
        button(LedgerKind.saleCash, Icons.point_of_sale, AppColors.success),
        const SizedBox(width: 10),
        button(LedgerKind.saleCredit, Icons.receipt_long, AppColors.tertiary),
        const SizedBox(width: 10),
        button(LedgerKind.expense, Icons.payments_outlined, AppColors.primary),
      ],
    );
  }
}

// ── period ───────────────────────────────────────────────────────────────

class _PeriodChips extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const _PeriodChips({required this.selected, required this.onSelect});

  static const _periods = [
    ('today', 'اليوم'),
    ('week', 'الأسبوع'),
    ('month', 'الشهر'),
    ('year', 'السنة'),
    ('custom', 'مخصّص'),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final p in _periods) ...[
            ChoiceChip(
              label: Text(p.$2),
              selected: selected == p.$1,
              onSelected: (_) => onSelect(p.$1),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

// ── money tiles ──────────────────────────────────────────────────────────

class _MoneyTiles extends StatelessWidget {
  final StoreDashboard d;
  const _MoneyTiles({required this.d});

  @override
  Widget build(BuildContext context) {
    final s = d.summary;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _Tile(
                label: 'المبيعات',
                value: s.revenue,
                sub: '${s.salesCount} بيعة',
                delta: _delta(s.revenue, d.previousRevenue),
                color: AppColors.success,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Tile(
                label: 'المصاريف',
                value: s.expenses + s.purchases,
                sub: s.purchases > 0 ? 'منها بضاعة ${formatNum(s.purchases)}' : null,
                delta: _delta(s.expenses, d.previousExpenses, lowerIsBetter: true),
                color: AppColors.error,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _Tile(
                label: 'الصافي',
                value: s.net,
                sub: s.grossProfit != null
                    ? 'ربح إجمالي ${formatNum(s.grossProfit!)}'
                    : 'أضف كلفة المنتجات لحساب الربح',
                delta: _delta(s.net, d.previousNet),
                color: s.net >= 0 ? AppColors.onSurface : AppColors.error,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Tile(
                label: 'ديون لك',
                value: d.receivables,
                sub: d.debtorsCount == 0 ? 'لا ديون مفتوحة' : '${d.debtorsCount} زبون',
                color: AppColors.primaryContainer,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ContactsScreen(initialKind: ContactKind.customer)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static double? _delta(double now, double before, {bool lowerIsBetter = false}) {
    if (before == 0) return null;
    final pct = (now - before) / before * 100;
    return lowerIsBetter ? -pct : pct;
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final double value;
  final String? sub;
  final double? delta;
  final Color color;
  final VoidCallback? onTap;
  const _Tile({
    required this.label,
    required this.value,
    this.sub,
    this.delta,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.surfaceContainer),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.onSurfaceVariant)),
                  const Spacer(),
                  if (delta != null)
                    Text(
                      '${delta! >= 0 ? '▲' : '▼'} ${delta!.abs().toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: delta! >= 0 ? AppColors.success : AppColors.error,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  formatNum(value),
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color),
                ),
              ),
              if (sub != null)
                Text(sub!, style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

class _Breakdown extends StatelessWidget {
  final StoreDashboard d;
  const _Breakdown({required this.d});

  @override
  Widget build(BuildContext context) {
    final s = d.summary;
    Widget part(String label, double v, Color c) => Expanded(
          child: Column(
            children: [
              Text(formatNum(v), style: TextStyle(fontWeight: FontWeight.bold, color: c)),
              Text(label, style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
            ],
          ),
        );
    return _Card(
      title: 'من أين جاءت المبيعات',
      child: Row(
        children: [
          part('نقداً', s.salesCash, AppColors.success),
          part('بالدين', s.salesCredit, AppColors.tertiary),
          part('التطبيق', s.salesApp, AppColors.primaryContainer),
          part('تسديدات', s.paymentsIn, AppColors.secondary),
        ],
      ),
    );
  }
}

// ── needs action ─────────────────────────────────────────────────────────

class _NeedsAction extends StatelessWidget {
  final StoreDashboard d;
  const _NeedsAction({required this.d});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    if (d.pendingOrders > 0) {
      rows.add(_ActionRow(
        icon: Icons.hourglass_top, color: AppColors.tertiary,
        text: '${d.pendingOrders} حجز ينتظر دفع المشتري'));
    }
    if (d.awaitingHandover > 0) {
      rows.add(_ActionRow(
        icon: Icons.local_shipping_outlined, color: AppColors.primaryContainer,
        text: '${d.awaitingHandover} طلب مدفوع ينتظر التسليم'));
    }
    for (final v in d.lowStock) {
      rows.add(_ActionRow(
        icon: v.quantity == 0 ? Icons.remove_shopping_cart_outlined : Icons.inventory_2_outlined,
        color: v.quantity == 0 ? AppColors.error : AppColors.tertiary,
        text: v.quantity == 0
            ? 'نفد: ${v.itemTitle}${v.label.isEmpty ? '' : ' — ${v.label}'}'
            : 'بقي ${v.quantity}: ${v.itemTitle}${v.label.isEmpty ? '' : ' — ${v.label}'}',
      ));
    }
    if (rows.isEmpty) {
      rows.add(const _ActionRow(
        icon: Icons.check_circle_outline, color: AppColors.success, text: 'لا شيء ينتظرك الآن'));
    }
    return _Card(
      title: 'يحتاج إجراءك',
      trailing: Text('${d.activeItems} منتج نشط', style: const TextStyle(fontSize: 11.5, color: AppColors.onSurfaceVariant)),
      child: Column(children: rows),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _ActionRow({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

// ── debtors ──────────────────────────────────────────────────────────────

class _Debtors extends StatelessWidget {
  final StoreDashboard d;
  const _Debtors({required this.d});

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'أكبر الديون',
      trailing: TextButton(
        onPressed: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const ContactsScreen(initialKind: ContactKind.customer))),
        child: const Text('الكل'),
      ),
      child: d.topDebtors.isEmpty
          ? const Text('لا ديون مفتوحة على أحد', style: TextStyle(fontSize: 12.5, color: AppColors.onSurfaceVariant))
          : Column(
              children: [
                for (final c in d.topDebtors)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.primaryFixed,
                      child: Text(c.name.characters.first, style: const TextStyle(color: AppColors.onPrimaryFixed, fontWeight: FontWeight.bold)),
                    ),
                    title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: c.phone.isEmpty ? null : Text(c.phone),
                    trailing: Text('${formatNum(c.balance)} IQD',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryContainer)),
                    onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => ContactStatementScreen(contact: c))),
                  ),
                if (d.payables > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.store_outlined, size: 16, color: AppColors.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text('عليك للمورّدين ${formatNum(d.payables)} IQD',
                              style: const TextStyle(fontSize: 12.5, color: AppColors.onSurfaceVariant)),
                        ),
                        TextButton(
                          onPressed: () => Navigator.push(
                            context, MaterialPageRoute(builder: (_) => const ContactsScreen(initialKind: ContactKind.supplier))),
                          child: const Text('المورّدون'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _TopItems extends StatelessWidget {
  final StoreDashboard d;
  const _TopItems({required this.d});

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'الأكثر مبيعاً',
      child: Column(
        children: [
          for (final t in d.topItems)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Text('${t.units} قطعة', style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
                  const SizedBox(width: 10),
                  Text(formatNum(t.total), style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Links extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget link(IconData icon, String label, Widget screen) => Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => screen)),
            icon: Icon(icon, size: 18),
            label: Text(label),
          ),
        );
    return Row(
      children: [
        link(Icons.menu_book_outlined, 'الدفتر', const LedgerEntriesScreen()),
        const SizedBox(width: 8),
        link(Icons.people_outline, 'الزبائن', const ContactsScreen(initialKind: ContactKind.customer)),
        const SizedBox(width: 8),
        link(Icons.local_shipping_outlined, 'المورّدون', const ContactsScreen(initialKind: ContactKind.supplier)),
      ],
    );
  }
}

// ── shared bits ──────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;
  const _Card({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceContainer),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const Spacer(),
              ?trailing,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBox({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.errorContainer, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          Text(message, style: const TextStyle(color: AppColors.onErrorContainer)),
          TextButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
        ],
      ),
    );
  }
}
