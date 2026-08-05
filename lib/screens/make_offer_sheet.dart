import 'package:flutter/material.dart';
import 'package:marketplace_app/widgets/app_network_image.dart';
import 'package:provider/provider.dart';
import '../models/listing.dart';
import '../providers/auth_provider.dart';
import '../services/chat_service.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import 'store_chat_screen.dart';

/// Small sheet that lets a buyer propose a total price for a quantity of an
/// item, shown when they tap "قدّم عرضاً" on the product page. Sends the
/// offer as a chat message to the seller and (on success) offers to open
/// that chat.
Future<void> showMakeOfferSheet(
  BuildContext context, {
  required FixedListing listing,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MakeOfferSheet(listing: listing),
  );
}

class _MakeOfferSheet extends StatefulWidget {
  final FixedListing listing;
  const _MakeOfferSheet({required this.listing});

  @override
  State<_MakeOfferSheet> createState() => _MakeOfferSheetState();
}

class _MakeOfferSheetState extends State<_MakeOfferSheet> {
  final _amountController = TextEditingController();
  final _messageController = TextEditingController();
  int _quantity = 1;
  bool _sending = false;
  String? _error;

  int get _maxQty => widget.listing.item.quantity;
  double get _listingTotal => widget.listing.price * _quantity;

  @override
  void dispose() {
    _amountController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _inc() {
    if (_quantity < _maxQty) setState(() => _quantity++);
  }

  void _dec() {
    if (_quantity > 1) setState(() => _quantity--);
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'أدخل مبلغاً صحيحاً للعرض');
      return;
    }

    final auth = context.read<AuthProvider>();
    final token = auth.accessToken;
    if (token == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() {
      _sending = true;
      _error = null;
    });

    final service = ChatService();
    final chatResult = await service.createOrGetChat(
      accessToken: token,
      itemId: widget.listing.item.id,
    );
    if (!mounted) return;
    if (!chatResult.success || chatResult.chat == null) {
      setState(() {
        _sending = false;
        _error = chatResult.message;
      });
      return;
    }

    final offerResult = await service.sendOffer(
      accessToken: token,
      chatId: chatResult.chat!.id,
      offerAmount: amount,
      quantity: _quantity,
      message: _messageController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _sending = false);

    if (!offerResult.success) {
      setState(() => _error = offerResult.message);
      return;
    }

    navigator.pop();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('تم إرسال عرضك إلى البائع'),
        backgroundColor: AppColors.success,
      ),
    );
    navigator.push(
      MaterialPageRoute(
        builder: (_) => StoreChatScreen(
          chatId: chatResult.chat!.id,
          title: widget.listing.item.owner.username,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.listing.item;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SafeArea(
          top: false,
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: item.firstImage != null
                            ? AppNetworkImage(
                                item.firstImage!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => _thumbFallback(),
                              )
                            : _thumbFallback(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'قدّم عرضاً',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                Row(
                  children: [
                    const Text(
                      'الكمية',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    _stepper(),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'عرضك للكمية كاملة (${formatIqd(_listingTotal)} حسب السعر الحالي)',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    hintText: 'مثال: ${formatNum(_listingTotal * 0.85)}',
                    suffixText: 'IQD',
                    filled: true,
                    fillColor: AppColors.surfaceContainerLowest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.surfaceContainer),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _messageController,
                  maxLines: 2,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    hintText: 'رسالة للبائع (اختياري)',
                    filled: true,
                    fillColor: AppColors.surfaceContainerLowest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.surfaceContainer),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _sending ? null : _submit,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.local_offer_outlined),
                    label:
                        Text(_sending ? 'جاري الإرسال...' : 'إرسال العرض'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryContainer,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _thumbFallback() => Container(
        color: AppColors.surfaceContainer,
        child: const Icon(Icons.image, color: AppColors.onSurfaceVariant),
      );

  Widget _stepper() {
    final canInc = _quantity < _maxQty;
    final canDec = _quantity > 1;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceContainer),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepBtn(Icons.remove_rounded, canDec ? _dec : null),
          Container(
            width: 40,
            alignment: Alignment.center,
            child: Text(
              '$_quantity',
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface),
            ),
          ),
          _stepBtn(Icons.add_rounded, canInc ? _inc : null),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback? onTap) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 42,
        height: 42,
        child: Icon(
          icon,
          size: 19,
          color: enabled
              ? AppColors.primary
              : AppColors.outline.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}
