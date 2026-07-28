import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/coupon_collection.dart';
import '../providers/auth_provider.dart';
import '../services/store_service.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';

const _months = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

String _formatDate(DateTime dt) => '${dt.day} ${_months[dt.month - 1]} ${dt.year}';

class MyCouponsScreen extends StatefulWidget {
  const MyCouponsScreen({super.key});

  @override
  State<MyCouponsScreen> createState() => _MyCouponsScreenState();
}

class _MyCouponsScreenState extends State<MyCouponsScreen> {
  final _service = StoreService();
  List<CouponCollection> _coupons = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final coupons = await _service.fetchMyCoupons(accessToken: token);
      if (mounted) {
        setState(() {
          _coupons = coupons;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: const Text('كوبوناتي'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
    }
    if (_coupons.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.confirmation_number_outlined,
                  size: 64, color: AppColors.outline),
              const SizedBox(height: 12),
              const Text('لم تجمع أي كوبونات بعد',
                  style: TextStyle(
                      color: AppColors.onSurfaceVariant, fontSize: 15)),
              const SizedBox(height: 8),
              const Text(
                'تصفّح المتاجر واجمع كوبونات الخصم لتستخدمها عند الشراء',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _coupons.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) => _couponTile(_coupons[i]),
      ),
    );
  }

  Widget _couponTile(CouponCollection c) {
    final statusLabel =
        c.isUsed ? 'مستخدم' : (c.isExpired ? 'غير صالح' : 'صالح للاستخدام');
    final statusColor = c.isUsed
        ? AppColors.onSurfaceVariant
        : (c.isExpired ? AppColors.error : AppColors.primary);
    final dimmed = c.isUsed || c.isExpired;

    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: statusColor),
                  ),
                ),
                const Spacer(),
                Text(
                  formatIqd(c.coupon.amount),
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (c.coupon.storeName.isNotEmpty)
              Text(
                c.coupon.storeName,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface),
              ),
            const SizedBox(height: 4),
            Text(
              'كود: ${c.coupon.code}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              c.coupon.minOrderAmount > 0
                  ? 'للطلبات فوق ${formatIqd(c.coupon.minOrderAmount)}'
                  : 'بدون حد أدنى للطلب',
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              'جُمع في: ${_formatDate(c.collectedAt)}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
