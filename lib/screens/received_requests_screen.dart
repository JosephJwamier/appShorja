import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/representative_request.dart';
import '../providers/auth_provider.dart';
import '../providers/representative_requests_provider.dart';

class ReceivedRequestsScreen extends StatefulWidget {
  const ReceivedRequestsScreen({super.key});

  @override
  State<ReceivedRequestsScreen> createState() => _ReceivedRequestsScreenState();
}

class _ReceivedRequestsScreenState extends State<ReceivedRequestsScreen> {
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
    await provider.loadReceivedRequests(accessToken: auth.accessToken!);
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
        title: const Text('طلبات المندوبيّة الواردة'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Consumer<RepresentativeRequestsProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading && provider.received.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (provider.errorMessage != null && provider.received.isEmpty) {
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
                    Text(provider.errorMessage!, textAlign: TextAlign.center),
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
          if (provider.received.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_outlined, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text(
                    'لا توجد طلبات واردة',
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
              itemCount: provider.received.length,
              // ↓↓↓ تعديل ١: استخراج متغيّر r وإضافة مفتاح للبطاقة
              itemBuilder: (context, index) {
                final r = provider.received[index];
                return _RequestCard(key: ValueKey(r.id), request: r);
              },
              // ↑↑↑ نهاية تعديل ١
            ),
          );
        },
      ),
    );
  }
}

// ↓↓↓ تعديل ٢: تحويل البطاقة كاملة من ساكنة إلى حيّة مع منطق القبول والرفض
class _RequestCard extends StatefulWidget {
  final RepresentativeRequest request;
  const _RequestCard({super.key, required this.request});

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
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

  // ↓↓↓ تعديل ٣: دالة تأكيد القبول
  Future<void> _confirmAccept() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('قبول طلب المندوبيّة'),
        content: Text(
          'بقبولك، سيستطيع ${widget.request.representative.username} العمل كمندوب لـ "${widget.request.item.title}" بنسبة ${widget.request.commissionPercentage.toStringAsFixed(1)}٪. هل تؤكّد؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('قبول'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _accept();
  }

  // ↓↓↓ تعديل ٤: تنفيذ القبول الفعليّ عبر المكان المركزيّ
  Future<void> _accept() async {
    setState(() => _isProcessing = true);

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final provider = Provider.of<RepresentativeRequestsProvider>(
      context,
      listen: false,
    );

    final result = await provider.acceptRequest(
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

  // ↓↓↓ تعديل ٥: حوار الرفض مع حقل سبب
  Future<void> _confirmReject() async {
    final controller = TextEditingController();
    bool submitted = false;

    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('رفض طلب المندوبيّة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('اكتب سبب الرفض (اختياري):'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'مثلاً: لا أحتاج مندوباً حالياً',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              if (submitted) return;
              submitted = true;
              Navigator.pop(dialogContext, controller.text.trim());
            },
            child: const Text('رفض'),
          ),
        ],
      ),
    );

    if (reason == null) return;
    await _reject(reason);
  }

  // ↓↓↓ تعديل ٦: تنفيذ الرفض الفعليّ عبر المكان المركزيّ
  Future<void> _reject(String reason) async {
    setState(() => _isProcessing = true);

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final provider = Provider.of<RepresentativeRequestsProvider>(
      context,
      listen: false,
    );

    final result = await provider.rejectRequest(
      accessToken: auth.accessToken!,
      requestId: widget.request.id,
      rejectionReason: reason,
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
            // الترويسة: صورة، عنوان، حالة
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
                        'من ${request.representative.username}',
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
            // النسبة
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
            // الصلاحيّات
            const Text(
              'الصلاحيّات المطلوبة',
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
            // رسالة المتقدّم
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
                  request.requestMessage,
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
              ),
            ],
            // ↓↓↓ تعديل ٧: عرض سبب الرفض حين يكون موجوداً
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
            // ↓↓↓ تعديل ٨: أزرار القبول والرفض المفعّلة مع مؤشّر التحميل
            if (request.canAccept || request.canReject) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  if (request.canReject)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isProcessing ? null : _confirmReject,
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
                          'رفض',
                          style: TextStyle(color: Colors.red),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                        ),
                      ),
                    ),
                  if (request.canReject && request.canAccept)
                    const SizedBox(width: 8),
                  if (request.canAccept)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isProcessing ? null : _confirmAccept,
                        icon: _isProcessing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check),
                        label: const Text('قبول'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            if (!request.canAccept &&
                !request.canReject &&
                (request.status == 'cancelled' ||
                    request.status == 'rejected')) ...[
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
// ↑↑↑ نهاية تعديل ٢ (نهاية صنف البطاقة الحيّة)