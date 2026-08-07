import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:v_video_compressor/v_video_compressor.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;
import '../../models/product.dart';
import '../../models/reel.dart';
import '../../providers/auth_provider.dart';
import '../../services/reel_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/reels/tag_item_picker_sheet.dart';

enum _Stage { picking, reviewing, uploading }

/// Create-reel flow: pick a video → compress it on-device (no server
/// processing, per the reels plan) → extract a thumbnail frame → optional
/// product tag → caption → upload both files directly to S3 via presigned
/// URLs → finalize. Pops with the created [Reel] on success so the feed
/// screen can prepend it immediately.
///
/// Package choice: `v_video_compressor` (as recommended in the plan) — it
/// resolved cleanly via `flutter pub get` with no version-conflict/platform
/// issues, so the `video_compress` fallback wasn't needed. Thumbnail
/// extraction uses the separate `video_thumbnail` package rather than
/// v_video_compressor's own (it also has one) — keeps the two concerns on
/// two single-purpose packages as the plan called out explicitly.
class CreateReelScreen extends StatefulWidget {
  const CreateReelScreen({super.key});

  @override
  State<CreateReelScreen> createState() => _CreateReelScreenState();
}

class _CreateReelScreenState extends State<CreateReelScreen> {
  final _reelService = ReelService();
  final _compressor = VVideoCompressor();
  final _captionController = TextEditingController();

  _Stage _stage = _Stage.picking;
  String? _error;

  VideoPlayerController? _previewController;
  int _durationSeconds = 0;

  bool _isCompressing = false;
  double _compressProgress = 0;
  String? _compressedVideoPath;
  Uint8List? _thumbnailBytes;

  Product? _taggedItem;

  bool _isUploading = false;
  double _uploadProgress = 0;
  String _uploadStageLabel = '';

  @override
  void dispose() {
    _captionController.dispose();
    _previewController?.dispose();
    super.dispose();
  }

  Future<void> _pickVideo(ImageSource source) async {
    setState(() => _error = null);
    XFile? picked;
    try {
      picked = await ImagePicker().pickVideo(
        source: source,
        maxDuration: const Duration(seconds: 90),
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'تعذّر فتح الكاميرا/المعرض: $e');
      return;
    }
    if (picked == null) return;

    final controller = VideoPlayerController.file(File(picked.path));
    try {
      await controller.initialize();
    } catch (e) {
      controller.dispose();
      if (mounted) setState(() => _error = 'ملف الفيديو غير صالح');
      return;
    }
    controller.setLooping(true);
    controller.play();

    if (!mounted) {
      controller.dispose();
      return;
    }
    setState(() {
      _previewController = controller;
      _durationSeconds = controller.value.duration.inSeconds;
      _stage = _Stage.reviewing;
    });

    unawaited(_compressAndExtractThumbnail(picked.path));
  }

  Future<void> _compressAndExtractThumbnail(String sourcePath) async {
    setState(() {
      _isCompressing = true;
      _compressProgress = 0;
      _compressedVideoPath = null;
      _thumbnailBytes = null;
    });

    try {
      final result = await _compressor.compressVideo(
        sourcePath,
        const VVideoCompressionConfig.medium(),
        onProgress: (progress) {
          if (mounted) setState(() => _compressProgress = progress);
        },
      );
      if (result == null) throw Exception('فشل ضغط الفيديو');

      final thumb = await vt.VideoThumbnail.thumbnailData(
        video: result.compressedFilePath,
        imageFormat: vt.ImageFormat.JPEG,
        maxWidth: 720,
        quality: 80,
      );
      if (thumb == null) throw Exception('تعذّر استخراج صورة مصغّرة من الفيديو');

      if (!mounted) return;
      setState(() {
        _compressedVideoPath = result.compressedFilePath;
        _thumbnailBytes = thumb;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'تعذّر تجهيز الفيديو للنشر: ${e.toString().replaceFirst('Exception: ', '')}');
      }
    } finally {
      if (mounted) setState(() => _isCompressing = false);
    }
  }

  Future<void> _pickTaggedItem() async {
    final auth = context.read<AuthProvider>();
    final token = auth.accessToken;
    final ownerId = auth.user?.id;
    if (token == null || ownerId == null) return;
    final item = await showTagItemPickerSheet(context, accessToken: token, ownerId: ownerId);
    if (item != null && mounted) setState(() => _taggedItem = item);
  }

  bool get _readyToPublish =>
      _compressedVideoPath != null && _thumbnailBytes != null && !_isCompressing && !_isUploading;

  Future<void> _publish() async {
    if (!_readyToPublish) return;
    setState(() {
      _stage = _Stage.uploading;
      _isUploading = true;
      _uploadProgress = 0;
      _uploadStageLabel = 'جارِ التحضير...';
      _error = null;
    });

    const videoContentType = 'video/mp4';
    const thumbnailContentType = 'image/jpeg';

    try {
      final videoBytes = await File(_compressedVideoPath!).readAsBytes();

      final handshake = await _reelService.requestUploadUrl(
        contentType: videoContentType,
        hasThumbnail: true,
      );
      final reelId = handshake['reel_id'] as int;
      final videoUploadUrl = handshake['video_upload_url'] as String;
      final thumbnailUploadUrl = handshake['thumbnail_upload_url'] as String?;

      setState(() => _uploadStageLabel = 'جارِ رفع الفيديو...');
      await _reelService.uploadBytesToS3(
        uploadUrl: videoUploadUrl,
        bytes: videoBytes,
        contentType: videoContentType,
        onProgress: (p) {
          // نُبقي 15% أخيرة لرفع الصورة المصغّرة + النشر حتى لا يبدو الشريط
          // وكأنه انتهى بينما لا يزال هناك عمل متبقٍ.
          if (mounted) setState(() => _uploadProgress = p * 0.85);
        },
      );

      if (thumbnailUploadUrl != null) {
        setState(() => _uploadStageLabel = 'جارِ رفع الصورة المصغّرة...');
        await _reelService.uploadBytesToS3(
          uploadUrl: thumbnailUploadUrl,
          bytes: _thumbnailBytes!,
          contentType: thumbnailContentType,
        );
      }

      setState(() {
        _uploadProgress = 0.95;
        _uploadStageLabel = 'جارِ النشر...';
      });
      final reel = await _reelService.finalizeReel(
        reelId: reelId,
        caption: _captionController.text.trim(),
        itemId: _taggedItem?.id,
        durationSeconds: _durationSeconds,
      );

      if (!mounted) return;
      setState(() => _uploadProgress = 1);
      Navigator.pop(context, reel);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.reviewing;
        _isUploading = false;
        _error = 'فشل النشر: ${e.toString().replaceFirst('Exception: ', '')}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope(
        canPop: _stage != _Stage.uploading,
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text('ريل جديد'),
          ),
          body: switch (_stage) {
            _Stage.picking => _buildPickStage(),
            _Stage.reviewing => _buildReviewStage(),
            _Stage.uploading => _buildUploadStage(),
          },
        ),
      ),
    );
  }

  Widget _buildPickStage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.video_call_outlined, size: 72, color: Colors.white54),
            const SizedBox(height: 16),
            const Text('اختر فيديو قصير لنشره كريل',
                style: TextStyle(color: Colors.white, fontSize: 15), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: AppColors.error), textAlign: TextAlign.center),
              const SizedBox(height: 16),
            ],
            ElevatedButton.icon(
              onPressed: () => _pickVideo(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('اختر من المعرض'),
              style: ElevatedButton.styleFrom(minimumSize: const Size(240, 46)),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _pickVideo(ImageSource.camera),
              icon: const Icon(Icons.videocam_outlined, color: Colors.white),
              label: const Text('تصوير فيديو', style: TextStyle(color: Colors.white)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(240, 46),
                side: const BorderSide(color: Colors.white54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewStage() {
    final controller = _previewController;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (controller != null && controller.value.isInitialized)
            AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: VideoPlayer(controller),
              ),
            ),
          const SizedBox(height: 12),
          if (_isCompressing)
            Column(
              children: [
                LinearProgressIndicator(value: _compressProgress == 0 ? null : _compressProgress),
                const SizedBox(height: 6),
                Text('جارِ ضغط الفيديو... ${(_compressProgress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            )
          else if (_compressedVideoPath != null)
            const Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.success, size: 16),
                SizedBox(width: 6),
                Text('الفيديو جاهز للنشر', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _captionController,
            textAlign: TextAlign.right,
            maxLines: 3,
            maxLength: 300,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'اكتب وصفاً للريل...',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Colors.white10,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 8),
          _taggedItem == null
              ? OutlinedButton.icon(
                  onPressed: _pickTaggedItem,
                  icon: const Icon(Icons.shopping_bag_outlined, color: Colors.white),
                  label: const Text('وسم منتج (اختياري)', style: TextStyle(color: Colors.white)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white54)),
                )
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      const Icon(Icons.shopping_bag, color: AppColors.gold, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_taggedItem!.title,
                            style: const TextStyle(color: Colors.white),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                        onPressed: () => setState(() => _taggedItem = null),
                      ),
                    ],
                  ),
                ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.error), textAlign: TextAlign.center),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _readyToPublish ? _publish : null,
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            child: const Text('نشر الريل'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              _previewController?.dispose();
              setState(() {
                _previewController = null;
                _stage = _Stage.picking;
                _compressedVideoPath = null;
                _thumbnailBytes = null;
                _taggedItem = null;
                _error = null;
              });
            },
            child: const Text('اختيار فيديو آخر', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadStage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: CircularProgressIndicator(
                value: _uploadProgress == 0 ? null : _uploadProgress,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(_uploadStageLabel, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 6),
            Text('${(_uploadProgress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
