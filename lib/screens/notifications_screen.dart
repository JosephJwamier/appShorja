import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/notifications_provider.dart';
import '../services/delivery_service.dart';
import '../services/reservation_service.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import 'reservations_screen.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  IconData _iconForType(String type) {
    switch (type) {
      case 'new_message': return Icons.chat_bubble_outline;
      case 'new_bid': return Icons.gavel;
      case 'auction_won': return Icons.emoji_events_outlined;
      case 'outbid': return Icons.trending_up;
      case 'reservation_created':
      case 'reservation_confirmed': return Icons.bookmark_added_outlined;
      case 'reservation_expiring': return Icons.timer_outlined;
      case 'reservation_completed': return Icons.check_circle_outline;
      case 'payment_release_requested': return Icons.campaign_outlined;
      case 'delivery_assigned': return Icons.local_shipping_outlined;
      case 'delivery_arrived': return Icons.local_shipping_outlined;
      case 'delivery_refused':
      case 'delivery_return_scheduled': return Icons.assignment_return_outlined;
      case 'refund_processed': return Icons.replay_outlined;
      default: return Icons.notifications_outlined;
    }
  }

  Future<void> _confirmReceipt(
      BuildContext context, NotificationsProvider provider, AppNotification n) async {
    final reservationId = int.tryParse(n.data['reservation_id']?.toString() ?? '');
    if (reservationId == null) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ReservationService().approveAndReleasePayment(
        accessToken: auth.accessToken!,
        reservationId: reservationId,
      );
      messenger.showSnackBar(const SnackBar(
          content: Text('تم تأكيد الاستلام وتحويل المبلغ إلى البائع'),
          backgroundColor: AppColors.success));
      await provider.markRead(n.id);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error));
    }
  }

  Future<void> _confirmDeliveryReceipt(
      BuildContext context, NotificationsProvider provider, AppNotification n) async {
    final deliveryOrderId = int.tryParse(n.data['delivery_order_id']?.toString() ?? '');
    if (deliveryOrderId == null) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await DeliveryService().confirmReceipt(
        accessToken: auth.accessToken!,
        deliveryOrderId: deliveryOrderId,
      );
      messenger.showSnackBar(const SnackBar(
          content: Text(
              'تم تأكيد الاستلام — سيُحرَّر المبلغ للبائع خلال 7 أيام أو عند موافقتك'),
          backgroundColor: AppColors.success));
      await provider.markRead(n.id);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error));
    }
  }

  Future<void> _refuseDeliveryReceipt(
      BuildContext context, NotificationsProvider provider, AppNotification n) async {
    final deliveryOrderId = int.tryParse(n.data['delivery_order_id']?.toString() ?? '');
    if (deliveryOrderId == null) return;
    final reasonController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('رفض استلام المنتج'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'إذا كانت لديك مشكلة حقيقية بالمنتج، اكتبها أدناه — ستتم مراجعتها من فريق الدعم وقد تسترد كامل مبلغك.',
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'وصف المشكلة (اختياري)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 10),
            const Text(
              'بدون وصف مشكلة، سيُعتبر رفضاً بلا سبب: يُخصَم العربون (وأجور التوصيل إن دفعتها كاملة)، ويُعاد الباقي بعد استلام الشركة للمنتج منك.',
              style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('تراجع'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('رفض الاستلام', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await DeliveryService().refuseReceipt(
        accessToken: auth.accessToken!,
        deliveryOrderId: deliveryOrderId,
        reason: reasonController.text.trim(),
      );
      messenger.showSnackBar(SnackBar(
          content: Text(message), backgroundColor: AppColors.success));
      await provider.markRead(n.id);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error));
    }
  }

  Future<void> _confirmClearAll(
      BuildContext context, NotificationsProvider provider) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('مسح كل الإشعارات'),
        content: const Text('سيتم حذف جميع الإشعارات نهائيًا. هل أنت متأكد؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('تراجع'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('مسح الكل', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await provider.deleteAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NotificationsProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('الإشعارات'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              if (provider.notifications.isNotEmpty) ...[
                TextButton(
                  onPressed: provider.markAllRead,
                  child: const Text(
                    'قراءة الكل',
                    style: TextStyle(color: AppColors.primary),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined, color: AppColors.error),
                  tooltip: 'مسح الكل',
                  onPressed: () => _confirmClearAll(context, provider),
                ),
              ],
            ],
          ),
          body: provider.isLoading && provider.notifications.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : provider.notifications.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.notifications_off_outlined,
                          size: 64, color: AppColors.onSurfaceVariant),
                      SizedBox(height: 12),
                      Text('لا توجد إشعارات',
                          style: TextStyle(color: AppColors.onSurfaceVariant)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: provider.notifications.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final n = provider.notifications[index];
                    return Dismissible(
                      key: Key(n.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.only(left: 20),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.delete_outline,
                            color: AppColors.error),
                      ),
                      onDismissed: (_) => provider.deleteNotification(n.id),
                      child: GestureDetector(
                        onTap: () => provider.markRead(n.id),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: n.isRead
                                ? AppColors.surfaceContainerLowest
                                : AppColors.primaryContainer.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: n.isRead
                                  ? AppColors.surfaceContainer
                                  : AppColors.primary.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryContainer
                                      .withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(_iconForType(n.type),
                                    color: AppColors.primary, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Row(
                                      children: [
                                        if (!n.isRead)
                                          Container(
                                            width: 8,
                                            height: 8,
                                            margin: const EdgeInsets.only(left: 6),
                                            decoration: const BoxDecoration(
                                              color: AppColors.primary,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        Expanded(
                                          child: Text(
                                            n.title,
                                            style: TextStyle(
                                              fontWeight: n.isRead
                                                  ? FontWeight.normal
                                                  : FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                            textAlign: TextAlign.right,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      n.body,
                                      style: const TextStyle(
                                        color: AppColors.onSurfaceVariant,
                                        fontSize: 13,
                                      ),
                                      textAlign: TextAlign.right,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      relativeTimeAr(n.receivedAt),
                                      style: const TextStyle(
                                        color: AppColors.onSurfaceVariant,
                                        fontSize: 11,
                                      ),
                                    ),
                                    if (n.type == 'reservation_expiring') ...[
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        width: double.infinity,
                                        child: FilledButton.icon(
                                          onPressed: () {
                                            provider.markRead(n.id);
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    const ReservationsScreen(),
                                              ),
                                            );
                                          },
                                          icon: const Icon(
                                              Icons.bookmark_outlined,
                                              size: 16),
                                          label: const Text('عرض حجوزاتي'),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: AppColors.primary,
                                            foregroundColor: Colors.white,
                                            visualDensity: VisualDensity.compact,
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8)),
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (n.type == 'payment_release_requested' &&
                                        n.data['reservation_id'] != null) ...[
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        width: double.infinity,
                                        child: FilledButton.icon(
                                          onPressed: () =>
                                              _confirmReceipt(context, provider, n),
                                          icon: const Icon(
                                              Icons.verified_outlined,
                                              size: 16),
                                          label: const Text('تم التأكد من المنتج'),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: AppColors.primary,
                                            foregroundColor: Colors.white,
                                            visualDensity: VisualDensity.compact,
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8)),
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (n.type == 'delivery_arrived' &&
                                        n.data['delivery_order_id'] != null) ...[
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: FilledButton.icon(
                                              onPressed: () =>
                                                  _confirmDeliveryReceipt(
                                                      context, provider, n),
                                              icon: const Icon(
                                                  Icons.verified_outlined,
                                                  size: 16),
                                              label: const Text('تم الاستلام'),
                                              style: FilledButton.styleFrom(
                                                backgroundColor:
                                                    AppColors.success,
                                                foregroundColor: Colors.white,
                                                visualDensity:
                                                    VisualDensity.compact,
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8)),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: () =>
                                                  _refuseDeliveryReceipt(
                                                      context, provider, n),
                                              icon: const Icon(Icons.close,
                                                  size: 16),
                                              label: const Text('رفض الاستلام'),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor:
                                                    AppColors.error,
                                                side: const BorderSide(
                                                    color: AppColors.error),
                                                visualDensity:
                                                    VisualDensity.compact,
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8)),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
