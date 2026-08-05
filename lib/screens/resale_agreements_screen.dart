import 'package:flutter/material.dart';
import 'package:marketplace_app/widgets/app_network_image.dart';
import 'package:provider/provider.dart';
import '../models/resale_agreement.dart';
import '../providers/auth_provider.dart';
import '../providers/transfers_provider.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import 'create_listing_screen.dart';

class ResaleAgreementsScreen extends StatefulWidget {
  const ResaleAgreementsScreen({super.key});

  @override
  State<ResaleAgreementsScreen> createState() =>
      _ResaleAgreementsScreenState();
}

class _ResaleAgreementsScreenState extends State<ResaleAgreementsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const _tabs = [
    TransferTab.received,
    TransferTab.sent,
    TransferTab.active,
    TransferTab.history,
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final token = context.read<AuthProvider>().accessToken!;
      final provider = context.read<TransfersProvider>();
      for (final tab in _tabs) {
        provider.loadTab(tab, token: token);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // الشاشة مدفوعة فوق MainShell (الذي يُبنى بدون Directionality صريح، أي
    // LTR افتراضيًا) — لذا نغلّف الشاشة بالكامل بـ RTL هنا صراحةً ليتطابق
    // ترتيب العناصر مع تصميم عربي سليم.
    return Directionality(
      textDirection: TextDirection.rtl,
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('نقل ملكية بالجملة'),
        bottom: TabBar(
          controller: _tabController,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          tabs: const [
            Tab(icon: Icon(Icons.inbox_outlined, size: 18), text: 'الواردة'),
            Tab(icon: Icon(Icons.send_outlined, size: 18), text: 'المُرسلة'),
            Tab(icon: Icon(Icons.handshake_outlined, size: 18), text: 'النشطة'),
            Tab(icon: Icon(Icons.history, size: 18), text: 'السجل'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabs.map((tab) => _TabContent(tab: tab)).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab Content
// ─────────────────────────────────────────────────────────────────────────────

class _TabContent extends StatefulWidget {
  final TransferTab tab;
  const _TabContent({required this.tab});

  @override
  State<_TabContent> createState() => _TabContentState();
}

class _TabContentState extends State<_TabContent>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Future<void> _refresh() async {
    final token = context.read<AuthProvider>().accessToken!;
    await context.read<TransfersProvider>().loadTab(widget.tab, token: token);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer<TransfersProvider>(
      builder: (context, provider, _) {
        final state = provider.stateOf(widget.tab);

        if (state.isLoading && state.items.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state.error != null && state.items.isEmpty) {
          return _ErrorView(message: state.error!, onRetry: _refresh);
        }

        if (state.isEmpty) {
          return _EmptyView(tab: widget.tab, onRefresh: _refresh);
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 10, bottom: 32),
            itemCount: state.items.length,
            itemBuilder: (context, index) => _AgreementCard(
              key: ValueKey(state.items[index].id),
              agreement: state.items[index],
              onRefresh: _refresh,
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Agreement Card
// ─────────────────────────────────────────────────────────────────────────────

class _AgreementCard extends StatefulWidget {
  final ResaleAgreement agreement;
  final Future<void> Function() onRefresh;

  const _AgreementCard({
    super.key,
    required this.agreement,
    required this.onRefresh,
  });

  @override
  State<_AgreementCard> createState() => _AgreementCardState();
}

class _AgreementCardState extends State<_AgreementCard> {
  bool _isProcessing = false;

  ResaleAgreement get a => widget.agreement;

  static Color statusColor(String status) => switch (status) {
    'pending' => const Color(0xFFFFA000),
    'active' => AppColors.success,
    'rejected' => AppColors.error,
    'completed' => Colors.grey,
    'cancelled' => const Color(0xFFFF6D00),
    'expired' => const Color(0xFF7B1FA2),
    _ => Colors.grey,
  };

  static IconData statusIcon(String status) => switch (status) {
    'pending' => Icons.hourglass_top_rounded,
    'active' => Icons.check_circle_rounded,
    'rejected' => Icons.cancel_rounded,
    'completed' => Icons.task_alt_rounded,
    'cancelled' => Icons.block_rounded,
    'expired' => Icons.event_busy_rounded,
    _ => Icons.circle,
  };

  static String statusLabel(String status) => switch (status) {
    'pending' => 'في الانتظار',
    'active' => 'نشطة',
    'rejected' => 'مرفوضة',
    'completed' => 'مكتملة',
    'cancelled' => 'ملغاة',
    'expired' => 'منتهية الصلاحية',
    _ => status,
  };

  Future<void> _doAction(
    Future<({bool success, String message})> Function() action,
  ) async {
    setState(() => _isProcessing = true);
    final result = await action();
    if (!mounted) return;
    setState(() => _isProcessing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? AppColors.success : AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    if (result.success) await widget.onRefresh();
  }

  Future<void> _confirmAction({
    required String title,
    required String content,
    required String confirmLabel,
    required Color confirmColor,
    required Future<({bool success, String message})> Function() action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('لا'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: confirmColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _doAction(action);
  }

  Future<void> _showApproveDialog() async {
    final unitPrice = a.item.price ?? 0;
    final total = unitPrice * a.quantity;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.check_circle_outline, color: AppColors.success),
            SizedBox(width: 8),
            Text('قبول الطلب'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'سيتم فوراً عند القبول:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            _ApprovePreviewRow(
              icon: Icons.inventory_2_outlined,
              text: 'خصم ${a.quantity} من مخزون "${a.item.name}"',
            ),
            const SizedBox(height: 8),
            _ApprovePreviewRow(
              icon: Icons.account_balance_wallet_outlined,
              text: 'إيداع ${formatIqd(total)} في محفظتك',
            ),
            const SizedBox(height: 8),
            _ApprovePreviewRow(
              icon: Icons.add_business_outlined,
              text:
                  'إنشاء منتج جديد بملكية كاملة لـ "${a.reseller.username}" بكمية ${a.quantity}',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('لا'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.success),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('قبول'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final token = context.read<AuthProvider>().accessToken!;
    await _doAction(
      () => context.read<TransfersProvider>().approve(token: token, id: a.id),
    );
  }

  Future<void> _showRejectDialog() async {
    final ctrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('رفض الطلب'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'سبب الرفض (اختياري)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('رفض'),
          ),
        ],
      ),
    );

    final reason = ctrl.text.trim();
    ctrl.dispose();
    if (confirmed != true || !mounted) return;
    final token = context.read<AuthProvider>().accessToken!;
    await _doAction(() => context.read<TransfersProvider>().reject(
      token: token,
      id: a.id,
      reason: reason.isEmpty ? null : reason,
    ));
  }

  void _openResultingItemListing() {
    final item = a.resultingItem;
    if (item == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateListingScreen(
          itemId: item.id,
          itemTitle: item.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = statusColor(a.status);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: AppColors.secondary.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 68,
                  height: 68,
                  child: a.item.image != null
                      ? AppNetworkImage(
                          fixMediaUrl(a.item.image),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _placeholder(),
                        )
                      : _placeholder(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.item.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    _UserRow(
                      icon: Icons.person_outlined,
                      label: 'المالك',
                      username: a.owner.username,
                    ),
                    const SizedBox(height: 2),
                    _UserRow(
                      icon: Icons.storefront_outlined,
                      label: 'البائع',
                      username: a.reseller.username,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusBadge(status: a.status, color: color),
            ],
          ),

          // ── Days remaining ───────────────────────────
          if (a.status == 'active' &&
              !a.isExpired &&
              (a.daysRemaining ?? 0) > 0) ...[
            const SizedBox(height: 10),
            _InfoBanner(
              icon: Icons.timer_outlined,
              text: '${a.daysRemaining} يوم متبقٍّ على انتهاء الاستضافة',
              color: AppColors.secondary,
            ),
          ],

          // ── Storage fee warning ──────────────────────
          if (a.isStorageFeeDue) ...[
            const SizedBox(height: 8),
            _InfoBanner(
              icon: Icons.warning_amber_rounded,
              text: 'رسوم تخزين مستحقة: ${formatIqd(a.dueStorageFee)}',
              color: const Color(0xFFE65100),
              bgColor: const Color(0xFFFFF3E0),
              borderColor: const Color(0xFFFFCC02),
            ),
          ],

          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // ── Details ──────────────────────────────────
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(
                icon: Icons.numbers_rounded,
                label: '${a.quantity} قطعة',
              ),
              _Pill(
                icon: Icons.sell_outlined,
                label: '${formatIqd(a.wholesalePricePerUnit)} / قطعة',
              ),
              _Pill(
                icon: Icons.payments_outlined,
                label: formatIqd(a.totalWholesalePrice),
                color: AppColors.primaryContainer,
              ),
              if (a.durationDays != null)
                _Pill(
                  icon: Icons.calendar_month_outlined,
                  label: '${a.durationDays} يوم استضافة',
                ),
              if (a.storageFeeType != 'none' && a.storageFeeAmount != null)
                _Pill(
                  icon: Icons.warehouse_outlined,
                  label: a.storageFeeType == 'percentage'
                      ? 'تخزين ${a.storageFeeAmount}٪'
                      : 'تخزين ${formatIqd(a.storageFeeAmount!)}',
                ),
            ],
          ),

          // ── Resulting item (after approval) ─────────
          if (a.resultingItem != null) ...[
            const SizedBox(height: 12),
            _ResultingItemBanner(
              item: a.resultingItem!,
              onSetPrice: _openResultingItemListing,
            ),
          ],

          // ── Action buttons ───────────────────────────
          if (_hasActions) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (a.canApprove)
                  _ActionBtn(
                    label: 'قبول',
                    icon: Icons.check_circle_outline,
                    color: AppColors.success,
                    filled: true,
                    isLoading: _isProcessing,
                    onPressed: _showApproveDialog,
                  ),
                if (a.canReject)
                  _ActionBtn(
                    label: 'رفض',
                    icon: Icons.cancel_outlined,
                    color: AppColors.error,
                    isLoading: _isProcessing,
                    onPressed: _showRejectDialog,
                  ),
                if (a.status == 'active')
                  _ActionBtn(
                    label: 'إنهاء الاتفاقية',
                    icon: Icons.assignment_turned_in_outlined,
                    color: AppColors.primary,
                    isLoading: _isProcessing,
                    onPressed: () {
                      final token =
                          context.read<AuthProvider>().accessToken!;
                      _confirmAction(
                        title: 'إنهاء الاتفاقية',
                        content:
                            'هذا ينهي استضافة التخزين فقط، ولا يُرجع الملكية أو الأموال. هل تريد المتابعة؟',
                        confirmLabel: 'إنهاء',
                        confirmColor: AppColors.primary,
                        action: () => context
                            .read<TransfersProvider>()
                            .complete(token: token, id: a.id),
                      );
                    },
                  ),
                if (a.canCancel)
                  _ActionBtn(
                    label: 'إلغاء',
                    icon: Icons.block_outlined,
                    color: const Color(0xFFFF6D00),
                    isLoading: _isProcessing,
                    onPressed: () {
                      final token =
                          context.read<AuthProvider>().accessToken!;
                      _confirmAction(
                        title: 'إلغاء',
                        content: a.status == 'active'
                            ? 'هذا ينهي استضافة التخزين فقط، ولا يُرجع الملكية أو الأموال. هل تريد المتابعة؟'
                            : 'هل تريد إلغاء هذا الطلب؟',
                        confirmLabel: 'إلغاء',
                        confirmColor: const Color(0xFFFF6D00),
                        action: () => context
                            .read<TransfersProvider>()
                            .cancel(token: token, id: a.id),
                      );
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  bool get _hasActions =>
      a.canApprove || a.canReject || a.canCancel || a.status == 'active';

  Widget _placeholder() => Container(
    color: AppColors.surfaceContainer,
    child: const Icon(
      Icons.inventory_2_outlined,
      color: AppColors.outline,
      size: 28,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Small reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;
  final Color color;
  const _StatusBadge({required this.status, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.5)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_AgreementCardState.statusIcon(status), size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          _AgreementCardState.statusLabel(status),
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );
}

class _ResultingItemBanner extends StatelessWidget {
  final ResaleItem item;
  final VoidCallback onSetPrice;
  const _ResultingItemBanner({required this.item, required this.onSetPrice});

  @override
  Widget build(BuildContext context) {
    final priced = item.price != null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            AppColors.success.withValues(alpha: 0.12),
            AppColors.surfaceContainerLowest,
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              color: AppColors.success,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'منتجك الجديد: ${item.name}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  priced
                      ? formatIqd(item.price!)
                      : 'لم يُحدَّد سعره بعد',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: priced
                        ? AppColors.success
                        : AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (!priced)
            FilledButton.tonal(
              onPressed: onSetPrice,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: Size.zero,
              ),
              child: const Text('تحديد السعر', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class _ApprovePreviewRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ApprovePreviewRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 16, color: AppColors.primary),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
    ],
  );
}

class _UserRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String username;

  const _UserRow({
    required this.icon,
    required this.label,
    required this.username,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 12, color: AppColors.outline),
      const SizedBox(width: 4),
      Text(
        '$label: ',
        style: const TextStyle(fontSize: 12, color: AppColors.outline),
      ),
      Flexible(
        child: Text(
          username,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final Color? bgColor;
  final Color? borderColor;

  const _InfoBanner({
    required this.icon,
    required this.text,
    required this.color,
    this.bgColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: bgColor ?? color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: borderColor ?? color.withValues(alpha: 0.3),
      ),
    ),
    child: Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _Pill({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: c),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: c,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isLoading;
  final bool filled;
  final VoidCallback? onPressed;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.isLoading,
    this.filled = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final iconWidget = isLoading
        ? SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: filled ? Colors.white : color,
            ),
          )
        : Icon(icon, size: 15);
    final labelWidget = Text(label, style: const TextStyle(fontSize: 12));

    if (filled) {
      return FilledButton.icon(
        onPressed: isLoading ? null : onPressed,
        icon: iconWidget,
        label: labelWidget,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: isLoading ? null : onPressed,
      icon: iconWidget,
      label: labelWidget,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty & Error states
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  final TransferTab tab;
  final Future<void> Function() onRefresh;
  const _EmptyView({required this.tab, required this.onRefresh});

  String get _message => switch (tab) {
    TransferTab.received => 'لا توجد طلبات واردة',
    TransferTab.sent => 'لم تُرسل أي طلبات بعد',
    TransferTab.active => 'لا توجد اتفاقيات نشطة حالياً',
    TransferTab.history => 'لا يوجد سجل اتفاقيات',
  };

  IconData get _icon => switch (tab) {
    TransferTab.received => Icons.inbox_outlined,
    TransferTab.sent => Icons.send_outlined,
    TransferTab.active => Icons.handshake_outlined,
    TransferTab.history => Icons.history_outlined,
  };

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(_icon, size: 76, color: AppColors.surfaceContainerHigh),
        const SizedBox(height: 16),
        Text(
          _message,
          style: const TextStyle(fontSize: 16, color: AppColors.outline),
        ),
        const SizedBox(height: 20),
        TextButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
          label: const Text('تحديث'),
        ),
      ],
    ),
  );
}

class _ErrorView extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.wifi_off_rounded,
            size: 60,
            color: AppColors.outline,
          ),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    ),
  );
}
