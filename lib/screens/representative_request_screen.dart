import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/notification_service.dart';
import '../services/representative_service.dart';

class RepresentativeRequestScreen extends StatefulWidget {
  final int itemId;
  final String itemTitle;

  const RepresentativeRequestScreen({
    super.key,
    required this.itemId,
    required this.itemTitle,
  });

  @override
  State<RepresentativeRequestScreen> createState() =>
      _RepresentativeRequestScreenState();
}

class _RepresentativeRequestScreenState
    extends State<RepresentativeRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _commissionController = TextEditingController(text: '10');
  final _messageController = TextEditingController();

  bool _canList = true;
  bool _canNegotiate = true;
  bool _canCompleteSale = false;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _commissionController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_canList && !_canNegotiate && !_canCompleteSale) {
      setState(() => _errorMessage = 'اختر صلاحيّة واحدة على الأقل');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final service = RepresentativeService();

      final result = await service.createRequest(
        accessToken: auth.accessToken!,
        itemId: widget.itemId,
        commissionPercentage: double.parse(_commissionController.text),
        canList: _canList,
        canNegotiate: _canNegotiate,
        canCompleteSale: _canCompleteSale,
        requestMessage: _messageController.text.trim(),
      );

      if (!mounted) return;

      setState(() => _isSubmitting = false);

      if (result.success) {
        // أول طلب مندوبية ناجح هو أول لحظة يصبح فيها إشعار الرد (قبول/رفض)
        // مفيدًا فعليًا — نطلب إذن الإشعارات هنا بدل أول فتحة للتطبيق.
        NotificationService.requestPermissionIfNeeded();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      } else {
        setState(() => _errorMessage = result.message);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('طلب أن أكون مندوباً'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.handshake_outlined, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'تطلب أن تكون مندوباً لـ "${widget.itemTitle}"',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _commissionController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'النسبة المقترحة (٪)',
                  helperText: 'النسبة التي تأخذها من كل عمليّة بيع',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'النسبة مطلوبة';
                  final n = double.tryParse(v);
                  if (n == null || n <= 0 || n > 100) {
                    return 'النسبة بين 0 و 100';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              const Text(
                'الصلاحيّات المطلوبة',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    CheckboxListTile(
                      value: _canList,
                      onChanged: (v) => setState(() => _canList = v ?? false),
                      title: const Text('عرض المنتج للبيع'),
                      subtitle: const Text('نشر بسعر ثابت أو في مزاد'),
                    ),
                    const Divider(height: 1),
                    CheckboxListTile(
                      value: _canNegotiate,
                      onChanged: (v) =>
                          setState(() => _canNegotiate = v ?? false),
                      title: const Text('التفاوض على السعر'),
                      subtitle: const Text('قبول المفاوضة مع المشترين'),
                    ),
                    const Divider(height: 1),
                    CheckboxListTile(
                      value: _canCompleteSale,
                      onChanged: (v) =>
                          setState(() => _canCompleteSale = v ?? false),
                      title: const Text('إتمام البيع'),
                      subtitle: const Text('إغلاق الصفقة نهائياً مع المشتري'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _messageController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'رسالة للمالك (اختياري)',
                  hintText: 'اشرح لماذا تريد أن تكون مندوباً...',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 24),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _submit,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.send),
                  label: Text(
                      _isSubmitting ? 'جاري الإرسال...' : 'إرسال الطلب'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}