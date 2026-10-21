import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/live_session_service.dart';
import '../../services/notification_service.dart';
import '../../theme/app_colors.dart';
import 'live_broadcast_screen.dart';

/// Quick "start a live broadcast" form — title only, goes live immediately
/// and hands off straight to the broadcaster screen.
class CreateLiveSessionScreen extends StatefulWidget {
  const CreateLiveSessionScreen({super.key});

  @override
  State<CreateLiveSessionScreen> createState() => _CreateLiveSessionScreenState();
}

class _CreateLiveSessionScreenState extends State<CreateLiveSessionScreen> {
  final _titleController = TextEditingController();
  final _service = LiveSessionService();
  bool _isStarting = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('اكتب عنواناً للبث')));
      return;
    }

    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;

    setState(() => _isStarting = true);
    final result = await _service.createLiveSession(
      accessToken: token,
      title: title,
      startImmediately: true,
    );
    if (!mounted) return;
    setState(() => _isStarting = false);

    if (result.success && result.session != null) {
      // أول بث ناجح هو أول لحظة يصبح فيها إشعار المزايدات/التعليقات أثناء
      // البث مفيدًا للبائع — نطلب إذن الإشعارات هنا بدل أول فتحة للتطبيق.
      //
      // وبانتظارٍ لا إطلاقاً: أندرويد يعرض حوار إذن واحداً في كل مرّة،
      // وشاشة البثّ تطلب الكاميرا والميكروفون فور فتحها. فإطلاق هذا الطلب
      // بلا انتظار يجعل طلب الكاميرا يصل وحوار الإشعارات معروض — فيُسقطه
      // النظام بلا حوار ويعود «مرفوض». وكان أثره أن أول بثّ لا يُسأل فيه
      // البائع عن الكاميرا أبداً فيفشل، ثم يُسأل في البثّ التالي حين يكون
      // إذن الإشعارات قد حُسم.
      await NotificationService.requestPermissionIfNeeded();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => LiveBroadcastScreen(sessionId: result.session!.id),
        ),
      );
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: const Text('بدء بث مباشر'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'عنوان البث',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _titleController,
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  hintText: 'مثال: عروض اليوم',
                  filled: true,
                  fillColor: AppColors.surfaceContainerLowest,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _isStarting ? null : _start,
                icon: _isStarting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.videocam),
                label: const Text('ابدأ البث الآن'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'سيبدأ البث فوراً بعد الضغط، وستنتقل مباشرة إلى شاشة التحكم بالبث.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
