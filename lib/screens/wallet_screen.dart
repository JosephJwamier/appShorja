import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/wallet.dart';
import '../providers/auth_provider.dart';
import '../providers/wallet_provider.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final _amountController = TextEditingController();
  final _cardController = TextEditingController();
  bool _depositing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _amountController.dispose();
    _cardController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    await Provider.of<WalletProvider>(context, listen: false)
        .loadAll(accessToken: auth.accessToken!);
  }

  Future<void> _deposit() async {
    final amount = _amountController.text.trim();
    final card = _cardController.text.trim();
    if (amount.isEmpty || card.isEmpty) return;

    setState(() => _depositing = true);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final error = await Provider.of<WalletProvider>(context, listen: false)
        .deposit(accessToken: auth.accessToken!, amount: amount, cardLast4: card);
    if (!mounted) return;
    setState(() => _depositing = false);

    if (error == null) {
      _amountController.clear();
      _cardController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم الإيداع بنجاح'),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('محفظتي', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Consumer<WalletProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading && provider.wallet == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (provider.errorMessage != null && provider.wallet == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline,
                      size: 48, color: AppColors.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Text(provider.errorMessage!,
                      style: const TextStyle(color: AppColors.onSurfaceVariant)),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (provider.wallet != null)
                  _BalanceCard(wallet: provider.wallet!),
                const SizedBox(height: 16),
                _DepositCard(
                  amountController: _amountController,
                  cardController: _cardController,
                  depositing: _depositing,
                  onDeposit: _deposit,
                ),
                const SizedBox(height: 24),
                const Text(
                  'سجل الإيداعات',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (provider.deposits.isEmpty)
                  _EmptyDeposits()
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: provider.deposits.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) =>
                        _DepositCard2(deposit: provider.deposits[i]),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── بطاقة الرصيد ──────────────────────────────────────────────────────────────
class _BalanceCard extends StatelessWidget {
  final Wallet wallet;
  const _BalanceCard({required this.wallet});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryContainer],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined,
                  color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              const Text('الرصيد المتاح',
                  style: TextStyle(color: Colors.white70, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            formatIqd(wallet.availableBalance),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              _BalanceStat(
                label: 'إجمالي الرصيد',
                value: formatIqd(wallet.balance),
              ),
              const SizedBox(width: 24),
              _BalanceStat(
                label: 'الرصيد المحجوز',
                value: formatIqd(wallet.heldBalance),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BalanceStat extends StatelessWidget {
  final String label;
  final String value;
  const _BalanceStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ── نموذج الإيداع ─────────────────────────────────────────────────────────────
class _DepositCard extends StatelessWidget {
  final TextEditingController amountController;
  final TextEditingController cardController;
  final bool depositing;
  final VoidCallback onDeposit;

  const _DepositCard({
    required this.amountController,
    required this.cardController,
    required this.depositing,
    required this.onDeposit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceContainer),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.add_card_outlined, color: AppColors.primary, size: 20),
              SizedBox(width: 8),
              Text('إيداع رصيد',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              hintText: 'المبلغ',
              prefixIcon: const Icon(Icons.attach_money,
                  color: AppColors.onSurfaceVariant),
              filled: true,
              fillColor: AppColors.surfaceContainerLow,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: cardController,
            keyboardType: TextInputType.number,
            maxLength: 4,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              hintText: 'آخر 4 أرقام من البطاقة',
              prefixIcon: const Icon(Icons.credit_card_outlined,
                  color: AppColors.onSurfaceVariant),
              counterText: '',
              filled: true,
              fillColor: AppColors.surfaceContainerLow,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: depositing ? null : onDeposit,
              icon: depositing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.arrow_downward, size: 18),
              label: Text(depositing ? 'جارٍ الإيداع...' : 'إيداع'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── بطاقة إيداع واحدة في السجل ───────────────────────────────────────────────
class _DepositCard2 extends StatelessWidget {
  final Deposit deposit;
  const _DepositCard2({required this.deposit});

  @override
  Widget build(BuildContext context) {
    final date = deposit.createdAt.toLocal();
    final dateStr =
        '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';

    final isCompleted = deposit.status == 'completed';
    final statusColor = isCompleted ? AppColors.success : AppColors.tertiaryContainer;
    final statusLabel = isCompleted ? 'مكتمل' : deposit.status;
    final statusIcon =
        isCompleted ? Icons.check_circle_outline : Icons.hourglass_top_rounded;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceContainer),
      ),
      child: Row(
        children: [
          // أيقونة الإيداع
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_downward,
                color: AppColors.success, size: 20),
          ),
          const SizedBox(width: 12),
          // التفاصيل
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '+${formatIqd(deposit.amount)}',
                      style: const TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, size: 11, color: statusColor),
                          const SizedBox(width: 3),
                          Text(
                            statusLabel,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: statusColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.credit_card_outlined,
                        size: 13, color: AppColors.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text('**** ${deposit.cardLast4}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.onSurfaceVariant)),
                    const SizedBox(width: 12),
                    const Icon(Icons.calendar_today_outlined,
                        size: 13, color: AppColors.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(dateStr,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  deposit.reference,
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.onSurfaceVariant,
                      fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── حالة فارغة ────────────────────────────────────────────────────────────────
class _EmptyDeposits extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            Icon(Icons.inbox_outlined,
                size: 56,
                color: AppColors.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text(
              'لا توجد إيداعات بعد',
              style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
