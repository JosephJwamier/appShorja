import 'package:flutter/material.dart';
import 'package:marketplace_app/widgets/app_network_image.dart';
import 'package:provider/provider.dart';
import '../models/dispute.dart';
import '../providers/auth_provider.dart';
import '../services/dispute_service.dart';
import '../theme/app_colors.dart';

const _months = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

String _formatDate(DateTime dt) => '${dt.day} ${_months[dt.month - 1]} ${dt.year}';

class DisputesScreen extends StatefulWidget {
  const DisputesScreen({super.key});

  @override
  State<DisputesScreen> createState() => _DisputesScreenState();
}

class _DisputesScreenState extends State<DisputesScreen> {
  List<Dispute> _disputes = [];
  bool _loading = true;
  String? _error;
  int _currentUserId = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    final token = auth.accessToken;
    if (token == null) return;
    _currentUserId = auth.user?.id ?? -1;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final disputes = await DisputeService().fetchMyDisputes(accessToken: token);
      if (mounted) {
        setState(() {
          _disputes = disputes;
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
          title: const Text('الطلبات المرفوضة'),
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
    if (_disputes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.assignment_late_outlined,
                  size: 64, color: AppColors.outline),
              const SizedBox(height: 12),
              const Text('لا توجد طلبات مرفوضة',
                  style: TextStyle(
                      color: AppColors.onSurfaceVariant, fontSize: 15)),
              const SizedBox(height: 8),
              const Text(
                'إذا واجهت مشكلة بأحد حجوزاتك، يمكنك الإبلاغ عنها من "حجوزاتي"',
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
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _disputes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) => _disputeTile(_disputes[i]),
      ),
    );
  }

  ({Color bg, Color fg, IconData icon}) _statusStyle(String status) {
    switch (status) {
      case 'open':
        return (
          bg: const Color(0xFFFFF8E1),
          fg: const Color(0xFFF57F17),
          icon: Icons.hourglass_top_rounded,
        );
      case 'investigating':
        return (
          bg: const Color(0xFFE3F2FD),
          fg: const Color(0xFF1565C0),
          icon: Icons.search_rounded,
        );
      case 'resolved':
        return (
          bg: const Color(0xFFE8F5E9),
          fg: const Color(0xFF2E7D32),
          icon: Icons.check_circle_outline,
        );
      default:
        return (
          bg: AppColors.surfaceContainerLow,
          fg: AppColors.onSurfaceVariant,
          icon: Icons.block_outlined,
        );
    }
  }

  Widget _disputeTile(Dispute d) {
    final s = _statusStyle(d.status);
    final iAmComplainant = d.isComplainant(_currentUserId);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceContainer),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: s.bg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(s.icon, size: 13, color: s.fg),
                    const SizedBox(width: 4),
                    Text(disputeStatusLabel(d.status),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: s.fg)),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                iAmComplainant ? 'أنت الشاكي' : 'شكوى مقدَّمة ضدّك',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: d.item.firstImage != null
                      ? AppNetworkImage(d.item.firstImage!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _thumbFallback())
                      : _thumbFallback(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(d.item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(d.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AppColors.onSurface)),
          const SizedBox(height: 8),
          Text('تاريخ الإبلاغ: ${_formatDate(d.createdAt)}',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.onSurfaceVariant)),
          if (d.status == 'resolved') ...[
            const Divider(height: 20),
            Row(
              children: [
                const Icon(Icons.verified_outlined,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    disputeResolutionLabel(d.resolutionAction),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary),
                  ),
                ),
              ],
            ),
            if (d.resolution.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(d.resolution,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.onSurfaceVariant)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _thumbFallback() => Container(
        color: AppColors.surfaceContainer,
        child: const Icon(Icons.image, size: 18, color: AppColors.onSurfaceVariant),
      );
}
