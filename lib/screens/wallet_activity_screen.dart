import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/wallet.dart';
import '../providers/auth_provider.dart';
import '../providers/wallet_provider.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import '../widgets/wallet/sync_refresh_button.dart';

/// «حركة الأموال»: every movement of the user's money with where it came
/// from and where it went, and what is parked in between (held for a
/// withdrawal, paid into escrow, earned but not yet released).
///
/// The refresh arrow does the only writing on this screen — it asks the
/// server to re-check unfinished card top-ups, then reloads. That is manual
/// by design: the user decides when to spend a gateway round-trip.
class WalletActivityScreen extends StatefulWidget {
  const WalletActivityScreen({super.key});

  @override
  State<WalletActivityScreen> createState() => _WalletActivityScreenState();
}

enum _Filter { all, inward, outward, held }

class _WalletActivityScreenState extends State<WalletActivityScreen> {
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String? get _token => context.read<AuthProvider>().accessToken;

  Future<void> _load() async {
    final token = _token;
    if (token == null) return;
    await context.read<WalletProvider>().loadActivity(accessToken: token);
  }

  Future<void> _refreshAll() async {
    final token = _token;
    if (token == null) return;
    final result = await context.read<WalletProvider>().refreshAll(accessToken: token);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result?.message ?? 'تم التحديث — تعذّر الوصول إلى بوابة الدفع'),
      backgroundColor: result == null ? AppColors.onSurfaceVariant : AppColors.success,
    ));
  }

  bool _matches(MoneyFlowEntry e) {
    switch (_filter) {
      case _Filter.all:
        return true;
      case _Filter.inward:
        return e.direction == FlowDirection.inward || e.direction == FlowDirection.pending;
      case _Filter.outward:
        return e.direction == FlowDirection.outward;
      case _Filter.held:
        return e.direction == FlowDirection.hold || e.direction == FlowDirection.release;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: const Text('حركة الأموال', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.onSurface,
          elevation: 0,
          actions: [
            Consumer<WalletProvider>(
              builder: (_, p, _) => SyncRefreshButton(busy: p.isSyncing, onPressed: _refreshAll),
            ),
          ],
        ),
        body: Consumer<WalletProvider>(
          builder: (context, provider, _) {
            final activity = provider.activity;
            if (activity == null && provider.activityError == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (activity == null) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: AppColors.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Text(provider.activityError!,
                        style: const TextStyle(color: AppColors.onSurfaceVariant)),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                  ],
                ),
              );
            }

            final entries = activity.entries.where(_matches).toList();
            return RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _FlowSummary(activity: activity),
                  const SizedBox(height: 16),
                  _FilterRow(
                    value: _filter,
                    onChanged: (f) => setState(() => _filter = f),
                  ),
                  const SizedBox(height: 12),
                  if (entries.isEmpty)
                    const _Empty()
                  else
                    for (var i = 0; i < entries.length; i++) ...[
                      if (i == 0 ||
                          dayLabelAr(entries[i].occurredAt) !=
                              dayLabelAr(entries[i - 1].occurredAt))
                        Padding(
                          padding: EdgeInsets.only(top: i == 0 ? 0 : 14, bottom: 6),
                          child: Text(
                            dayLabelAr(entries[i].occurredAt),
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      MoneyFlowTile(entry: entries[i]),
                    ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── الملخّص: متاح / محجوز / في الضمان / بانتظار التحرير ─────────────────────
class _FlowSummary extends StatelessWidget {
  final WalletActivity activity;
  const _FlowSummary({required this.activity});

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      _SummaryTile(
        label: 'متاح للصرف',
        amount: activity.availableBalance,
        color: AppColors.success,
        icon: Icons.account_balance_wallet_outlined,
      ),
      if (activity.heldBalance > 0)
        _SummaryTile(
          label: 'محجوز لطلب سحب',
          amount: activity.heldBalance,
          color: AppColors.tertiary,
          icon: Icons.lock_outline,
        ),
      if (activity.paidWaiting > 0)
        _SummaryTile(
          label: 'مدفوع في الضمان',
          amount: activity.paidWaiting,
          color: AppColors.tertiary,
          icon: Icons.shield_outlined,
          hint: 'يُسلَّم للبائع بعد استلامك',
        ),
      if (activity.earningsWaiting > 0)
        _SummaryTile(
          label: 'أرباح بانتظار التحرير',
          amount: activity.earningsWaiting,
          color: AppColors.primary,
          icon: Icons.hourglass_bottom_rounded,
        ),
      if (activity.commissionsWaiting > 0)
        _SummaryTile(
          label: 'عمولات بانتظار التحرير',
          amount: activity.commissionsWaiting,
          color: AppColors.primary,
          icon: Icons.handshake_outlined,
        ),
      if (activity.pendingTopups > 0)
        _SummaryTile(
          label: 'شحن لم يكتمل',
          amount: null,
          count: activity.pendingTopups,
          color: AppColors.onSurfaceVariant,
          icon: Icons.sync_problem_outlined,
          hint: 'اضغط زر التحديث أعلاه',
        ),
    ];
    return Wrap(spacing: 10, runSpacing: 10, children: tiles);
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final double? amount;
  final int? count;
  final Color color;
  final IconData icon;
  final String? hint;

  const _SummaryTile({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
    this.count,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.of(context).size.width - 32 - 10) / 2;
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
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
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            amount != null ? '${formatNum(amount!)} IQD' : '$count عملية',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color),
          ),
          if (hint != null)
            Text(hint!, style: const TextStyle(fontSize: 10.5, color: AppColors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

// ── الفلاتر ───────────────────────────────────────────────────────────────────
class _FilterRow extends StatelessWidget {
  final _Filter value;
  final ValueChanged<_Filter> onChanged;
  const _FilterRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const labels = {
      _Filter.all: 'الكل',
      _Filter.inward: 'داخلة',
      _Filter.outward: 'خارجة',
      _Filter.held: 'محجوزة',
    };
    return Wrap(
      spacing: 8,
      children: [
        for (final f in _Filter.values)
          ChoiceChip(
            label: Text(labels[f]!),
            selected: value == f,
            onSelected: (_) => onChanged(f),
            selectedColor: AppColors.primary,
            labelStyle: TextStyle(
              color: value == f ? Colors.white : AppColors.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

// ── قيد واحد: من ← إلى ─────────────────────────────────────────────────────
class MoneyFlowTile extends StatelessWidget {
  final MoneyFlowEntry entry;
  const MoneyFlowTile({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(entry.direction);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceContainer),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: style.background, shape: BoxShape.circle),
            child: Icon(style.icon, size: 20, color: style.foreground),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(entry.title,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                    Text(
                      '${style.sign}${formatNum(entry.amount)}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: style.foreground,
                        decoration: entry.direction == FlowDirection.failed
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // The from → to line is the point of the screen.
                Row(
                  children: [
                    Flexible(
                      child: Text(entry.from,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.arrow_back_rounded, size: 14, color: AppColors.outline),
                    ),
                    Flexible(
                      child: Text(entry.to,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: style.background,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(style.label,
                          style: TextStyle(
                              fontSize: 10.5, fontWeight: FontWeight.w700, color: style.foreground)),
                    ),
                    const SizedBox(width: 8),
                    Text(shortTime(entry.occurredAt),
                        style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant)),
                  ],
                ),
                if (entry.note.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(entry.note,
                      style: const TextStyle(fontSize: 11.5, color: AppColors.onSurfaceVariant)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FlowStyle {
  final IconData icon;
  final Color foreground;
  final Color background;
  final String sign;
  final String label;
  const _FlowStyle(this.icon, this.foreground, this.background, this.sign, this.label);
}

_FlowStyle _styleFor(FlowDirection d) {
  switch (d) {
    case FlowDirection.inward:
      return const _FlowStyle(Icons.south_west_rounded, AppColors.success,
          Color(0xFFE3F4E5), '+', 'داخل');
    case FlowDirection.outward:
      return const _FlowStyle(Icons.north_east_rounded, AppColors.error,
          AppColors.errorContainer, '−', 'خارج');
    case FlowDirection.hold:
      return const _FlowStyle(Icons.lock_clock_outlined, AppColors.tertiary,
          Color(0xFFFFF3D6), '', 'محجوز');
    case FlowDirection.release:
      return const _FlowStyle(Icons.lock_open_rounded, AppColors.secondary,
          AppColors.secondaryContainer, '', 'أُفرج عنه');
    case FlowDirection.pending:
      return const _FlowStyle(Icons.hourglass_top_rounded, AppColors.onSurfaceVariant,
          AppColors.surfaceContainer, '', 'قيد الانتظار');
    case FlowDirection.failed:
      return const _FlowStyle(Icons.close_rounded, AppColors.onSurfaceVariant,
          AppColors.surfaceContainer, '', 'لم يكتمل');
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 44, color: AppColors.onSurfaceVariant),
          SizedBox(height: 10),
          Text('لا حركة بعد', style: TextStyle(color: AppColors.onSurfaceVariant)),
        ],
      ),
    );
  }
}
