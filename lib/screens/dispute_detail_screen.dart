import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/dispute.dart';
import '../services/dispute_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_network_image.dart';
import '../widgets/dispute_images_picker.dart';

/// النزاع كاملاً: الشكوى، وما قاله الطرفان وما أرفقاه، وردٌّ جديد ما دام
/// مفتوحاً. يعيد true إن أُضيف ردّ.
class DisputeDetailScreen extends StatefulWidget {
  final Dispute dispute;
  final int currentUserId;
  const DisputeDetailScreen({
    super.key,
    required this.dispute,
    required this.currentUserId,
  });

  @override
  State<DisputeDetailScreen> createState() => _DisputeDetailScreenState();
}

class _DisputeDetailScreenState extends State<DisputeDetailScreen> {
  late Dispute _dispute = widget.dispute;
  final _text = TextEditingController();
  List<XFile> _images = [];
  bool _sending = false;
  bool _changed = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  int get _imagesLeft {
    final sent = _dispute.replies
        .where((r) => r.authorId == widget.currentUserId)
        .fold(0, (n, r) => n + r.images.length);
    return kMaxDisputeImages - sent;
  }

  Future<void> _send() async {
    if (_text.text.trim().isEmpty && _images.isEmpty) return;
    setState(() => _sending = true);
    final result = await DisputeService().reply(
      disputeId: _dispute.id,
      text: _text.text.trim(),
      images: _images,
    );
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (result.dispute != null) {
        _dispute = result.dispute!;
        _changed = true;
        _text.clear();
        _images = [];
      }
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.message)));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: const Text('تفاصيل النزاع'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () => Navigator.pop(context, _changed),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(_dispute.title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(_dispute.item.title,
                style: const TextStyle(color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 12),
            Text(_dispute.description),
            const Divider(height: 28),
            if (_dispute.replies.isEmpty)
              const Text('لا ردود بعد',
                  style: TextStyle(color: AppColors.onSurfaceVariant)),
            for (final r in _dispute.replies) _reply(r),
            if (_dispute.resolution.isNotEmpty) ...[
              const Divider(height: 28),
              const Text('قرار الإدارة',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(_dispute.resolution),
            ],
            if (_dispute.canReply) ...[
              const Divider(height: 28),
              TextField(
                controller: _text,
                maxLines: 4,
                maxLength: 3000,
                decoration: const InputDecoration(
                  labelText: 'ردّك',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                ),
              ),
              if (_imagesLeft > 0) ...[
                const SizedBox(height: 8),
                DisputeImagesPicker(
                  images: _images,
                  max: _imagesLeft,
                  onChanged: (images) => setState(() => _images = images),
                ),
              ],
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _sending ? null : _send,
                child: Text(_sending ? 'جارٍ الإرسال...' : 'إرسال الرد'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _reply(DisputeReply r) {
    final who = r.authorId == widget.currentUserId
        ? 'أنت'
        : r.isComplainant
            ? 'المشتكي'
            : 'المشتكى عليه';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceContainer),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(who,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary)),
          if (r.text.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(r.text),
          ],
          if (r.images.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final url in r.images)
                  GestureDetector(
                    onTap: () => _open(url),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 84,
                        height: 84,
                        child: AppNetworkImage(
                          url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _open(String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          body: Center(
            child: InteractiveViewer(
              child: AppNetworkImage(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
