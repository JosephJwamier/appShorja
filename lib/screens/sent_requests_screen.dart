import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/representative_request.dart';
import '../providers/auth_provider.dart';
import '../providers/representative_requests_provider.dart';

class SentRequestsScreen extends StatefulWidget {
  const SentRequestsScreen({super.key});

  @override
  State<SentRequestsScreen> createState() => _SentRequestsScreenState();
}

class _SentRequestsScreenState extends State<SentRequestsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final provider = Provider.of<RepresentativeRequestsProvider>(
      context,
      listen: false,
    );
    await provider.loadSentRequests(accessToken: auth.accessToken!);
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
        title: const Text('طلباتي المرسلة'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Consumer<RepresentativeRequestsProvider>(
        builder: (context, provider, _) {
          if (provider.isLoadingSent && provider.sent.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (provider.errorSent != null && provider.sent.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 50,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 12),
                    Text(provider.errorSent!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _load,
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (provider.sent.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.outbox_outlined,
                    size: 80,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'لم ترسل أيّ طلب بعد',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: provider.sent.length,
              itemBuilder: (context, index) {
                final r = provider.sent[index];
                return _SentRequestCard(key: ValueKey(r.id), request: r);
              },
            ),
          );
        },
      ),
    );
  }
}

class _SentRequestCard extends StatefulWidget {
  final RepresentativeRequest request;
  const _SentRequestCard({super.key, required this.request});

  @override
  State<_SentRequestCard> createState() => _SentRequestCardState();
}

class _SentRequestCardState extends State<_SentRequestCard> {
  bool _isProcessing = false;

  ({Color color, String label}) _statusInfo(String status) {
    switch (status) {
      case 'pending':
        return (color: Colors.orange, label: 'بانتظار');
      case 'accepted':
        return (color: Colors.green, label: 'مقبول');
      case 'rejected':
        return (color: Colors.red, label: 'مرفوض');
      case 'cancelled':
        return (color: Colors.grey, label: 'ملغى');
      default:
        return (color: Colors.blueGrey, label: status);
    }
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inDays > 0) return 'منذ ${diff.inDays} يوم';
    if (diff.inHours > 0) return 'منذ ${diff.inHours} ساعة';
    if (diff.inMinutes > 0) return 'منذ ${diff.inMinutes} دقيقة';
    return 'الآن';
  }

  Widget _permChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Text(
        label,
        style: TextStyle(color: Colors.blue[700], fontSize: 12),
      ),
    );
  }

  Future<void> _confirmCancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إلغاء الطلب'),
        content: Text(
          'هل تريد إلغاء طلب المندوبيّة لـ "${widget.request.item.title}"؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('لا'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('نعم، ألغِ'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _cancel();
  }

  Future<void> _cancel() async {
    setState(() => _isProcessing = true);

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final provider = Provider.of<RepresentativeRequestsProvider>(
      context,
      listen: false,
    );

    final result = await provider.cancelRequest(
      accessToken: auth.accessToken!,
      requestId: widget.request.id,
    );

    if (!mounted) return;
    setState(() => _isProcessing = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? Colors.green : Colors.red,
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف من السجلّ'),
        content: Text(
          'هل تريد حذف هذا الطلب نهائياً من سجلّك؟ لن يمكن استرجاعه.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _delete();
  }

  Future<void> _delete() async {
    setState(() => _isProcessing = true);

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final provider = Provider.of<RepresentativeRequestsProvider>(
      context,
      listen: false,
    );

    final result = await provider.deleteRequest(
      accessToken: auth.accessToken!,
      requestId: widget.request.id,
    );

    if (!mounted) return;
    // ملاحظة: لا نُعيد ضبط _isProcessing لأنّ البطاقة ستُزال من القائمة
    // إن نجح الحذف، فلا حاجة لرسم زائد عليها

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? Colors.green : Colors.red,
      ),
    );

    if (!result.success && mounted) {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final status = _statusInfo(request.status);
    final image = request.item.firstImage;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 60,
                  height: 60,
                  child: image != null
                      ? Image.network(
                          image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: Colors.grey[300],
                            child: const Icon(Icons.broken_image),
                          ),
                        )
                      : Container(
                          color: Colors.grey[300],
                          child: const Icon(Icons.image),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.item.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'إلى ${request.owner.username}',
                        style: TextStyle(color: Colors.grey[700], fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatDate(request.createdAt),
                        style: TextStyle(color: Colors.grey[600], fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: status.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status.label,
                    style: TextStyle(
                      color: status.color,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                const Icon(Icons.percent, color: Colors.blue, size: 18),
                const SizedBox(width: 8),
                Text(
                  'النسبة المقترحة: ${request.commissionPercentage.toStringAsFixed(1)} ٪',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'الصلاحيّات التي طلبتها',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (request.canList) _permChip('عرض للبيع'),
                if (request.canNegotiate) _permChip('تفاوض'),
                if (request.canCompleteSale) _permChip('إتمام بيع'),
              ],
            ),
            if (request.requestMessage.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'رسالتك: ${request.requestMessage}',
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
              ),
            ],
            if (request.rejectionReason.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 18, color: Colors.red[700]),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'سبب الرفض: ${request.rejectionReason}',
                        style: TextStyle(color: Colors.red[700], fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (request.canCancel) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isProcessing ? null : _confirmCancel,
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.red,
                          ),
                        )
                      : const Icon(Icons.close, color: Colors.red),
                  label: const Text(
                    'إلغاء الطلب',
                    style: TextStyle(color: Colors.red),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ),
            ] else if (request.status == 'cancelled' ||
                request.status == 'rejected') ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isProcessing ? null : _confirmDelete,
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.grey,
                          ),
                        )
                      : Icon(Icons.delete_outline, color: Colors.grey[700]),
                  label: Text(
                    'حذف من السجلّ',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey[400]!),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
