import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/wallet.dart';
import '../../providers/auth_provider.dart';
import '../../services/wallet_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/amount_input.dart';
import '../../utils/formatters.dart';

/// طلب سحب من المحفظة. يعيد true إن أُرسل الطلب.
///
/// المبلغ يُحجز فور الطلب وتحوّله الإدارة بعد المراجعة. رقم الحساب يُرسل
/// ولا يُحفظ في الهاتف.
Future<bool?> showWithdrawSheet(
  BuildContext context, {
  required double available,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (_) => WithdrawSheet(available: available),
  );
}

class WithdrawSheet extends StatefulWidget {
  final double available;
  final WalletService? service;
  const WithdrawSheet({super.key, required this.available, this.service});

  @override
  State<WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends State<WithdrawSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _account = TextEditingController();
  final _holder = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _account.dispose();
    _holder.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await (widget.service ?? WalletService()).withdraw(
        amount: parseAmount(_amount.text)!,
        accountNumber: _account.text.trim(),
        holderName: _holder.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    );
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('سحب رصيد',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  'المتاح للسحب ${formatIqd(widget.available)}',
                  style: const TextStyle(color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [AmountInputFormatter()],
                  decoration: const InputDecoration(
                      labelText: 'المبلغ (IQD)', border: border),
                  validator: (v) {
                    final n = parseAmount(v);
                    if (n == null || n <= 0) return 'أدخل مبلغاً صحيحاً';
                    if (n > widget.available) return 'أكبر من رصيدك المتاح';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _account,
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                  autocorrect: false,
                  enableSuggestions: false,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(20),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'رقم الحساب أو البطاقة',
                    helperText: 'يُستعمل لتحويل هذا المبلغ فقط، ويُحذف بعده',
                    border: border,
                  ),
                  validator: (v) => (v ?? '').trim().length < 10
                      ? 'رقم الحساب 10 أرقام على الأقل'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _holder,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [LengthLimitingTextInputFormatter(120)],
                  decoration: const InputDecoration(
                      labelText: 'اسم صاحب الحساب', border: border),
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? 'اكتب الاسم كما في الحساب'
                      : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _sending ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(_sending ? 'جارٍ الإرسال...' : 'إرسال الطلب'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// زرّ السحب وآخر طلباته. مستقلّ عن مزوّد المحفظة: فشل جلب الطلبات لا
/// يُسقط شاشة الرصيد.
class WithdrawCard extends StatefulWidget {
  final double available;
  final VoidCallback onChanged;
  const WithdrawCard({
    super.key,
    required this.available,
    required this.onChanged,
  });

  @override
  State<WithdrawCard> createState() => _WithdrawCardState();
}

class _WithdrawCardState extends State<WithdrawCard> {
  List<Withdrawal> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (context.read<AuthProvider>().accessToken == null) return;
    try {
      final items = await WalletService().fetchWithdrawals();
      if (mounted) setState(() => _items = items);
    } catch (_) {
      // القائمة للعلم؛ غيابها لا يمنع السحب.
    }
  }

  Future<void> _open() async {
    final messenger = ScaffoldMessenger.of(context);
    final sent = await showWithdrawSheet(context, available: widget.available);
    if (sent != true || !mounted) return;
    messenger.showSnackBar(const SnackBar(
      content: Text('أُرسل طلب السحب، وسيُحوَّل المبلغ بعد المراجعة'),
      backgroundColor: AppColors.success,
    ));
    widget.onChanged();
    _load();
  }

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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: widget.available > 0 ? _open : null,
            icon: const Icon(Icons.arrow_upward, size: 18),
            label: const Text('سحب رصيد'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          for (final w in _items.take(5)) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${formatIqd(w.amount)}  ••••${w.accountLast4}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  w.statusLabel,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: switch (w.status) {
                      'approved' => AppColors.success,
                      'rejected' => AppColors.error,
                      _ => AppColors.onSurfaceVariant,
                    },
                  ),
                ),
              ],
            ),
            if (w.status == 'rejected' && w.notes.isNotEmpty)
              Text(w.notes,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}
