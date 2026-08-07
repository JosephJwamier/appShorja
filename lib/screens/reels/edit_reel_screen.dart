import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/product.dart';
import '../../models/reel.dart';
import '../../providers/auth_provider.dart';
import '../../services/reel_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_network_image.dart';
import '../../widgets/reels/tag_item_picker_sheet.dart';

/// Editing an already-published reel: caption and tagged product only.
///
/// The video is deliberately not editable — its S3 object is written once at
/// finalize and never rewritten, so "changing the video" is delete + post a
/// new one. The thumbnail here is a read-only reminder of *which* reel is
/// being edited, not something the form touches.
///
/// Mirrors create_reel_screen.dart's review stage (same caption field, same
/// tag-picker sheet, same dark chrome) so the two screens don't feel like
/// different products — but on light chrome, since this is reached from
/// MyReelsScreen rather than from over a full-bleed video.
///
/// Pops with the updated [Reel] on success so the caller can patch its lists
/// without a refetch.
class EditReelScreen extends StatefulWidget {
  final Reel reel;

  const EditReelScreen({super.key, required this.reel});

  @override
  State<EditReelScreen> createState() => _EditReelScreenState();
}

class _EditReelScreenState extends State<EditReelScreen> {
  final _service = ReelService();
  late final _captionController =
      TextEditingController(text: widget.reel.caption);

  /// The picker returns a [Product]; the reel carries a lighter [ReelItemRef].
  /// We hold whichever we have and render from [_taggedTitle] so a
  /// freshly-picked item and a pre-existing tag look identical.
  Product? _pickedItem;
  late ReelItemRef? _existingItem = widget.reel.item;

  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  int? get _taggedItemId => _pickedItem?.id ?? _existingItem?.id;
  String? get _taggedTitle => _pickedItem?.title ?? _existingItem?.title;
  String? get _taggedImage => _pickedItem?.firstImage ?? _existingItem?.imageUrl;

  bool get _hasChanges =>
      _captionController.text.trim() != widget.reel.caption ||
      _taggedItemId != widget.reel.item?.id;

  Future<void> _pickTaggedItem() async {
    final auth = context.read<AuthProvider>();
    final token = auth.accessToken;
    final ownerId = auth.user?.id;
    if (token == null || ownerId == null) return;
    final item = await showTagItemPickerSheet(
      context,
      accessToken: token,
      ownerId: ownerId,
    );
    if (item != null && mounted) {
      setState(() {
        _pickedItem = item;
        _existingItem = null;
      });
    }
  }

  void _clearTaggedItem() {
    setState(() {
      _pickedItem = null;
      _existingItem = null;
    });
  }

  Future<void> _save() async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null || _isSaving) return;

    setState(() {
      _isSaving = true;
      _error = null;
    });

    final caption = _captionController.text.trim();
    final itemId = _taggedItemId;
    final result = await _service.updateReel(
      accessToken: token,
      reelId: widget.reel.id,
      caption: caption,
      itemId: itemId,
      // The reel had a tag and no longer does — send an explicit null so the
      // backend clears it rather than reading the omitted key as "unchanged".
      clearItem: itemId == null && widget.reel.item != null,
    );
    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _isSaving = false;
        _error = result.message;
      });
      return;
    }

    // Prefer the server's copy; fall back to patching locally if the response
    // body wasn't parseable (the write still landed).
    final updated = result.reel ??
        widget.reel.copyWith(
          caption: caption,
          clearItem: itemId == null,
          item: _pickedItem != null
              ? ReelItemRef(
                  id: _pickedItem!.id,
                  title: _pickedItem!.title,
                  imageUrl: _pickedItem!.firstImage,
                  price: _pickedItem!.price,
                )
              : null,
        );
    Navigator.pop(context, updated);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(title: const Text('تعديل الريل')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildPreviewRow(),
            const SizedBox(height: 20),
            const Text('الوصف',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            TextField(
              controller: _captionController,
              textAlign: TextAlign.right,
              maxLines: 3,
              maxLength: 300,
              enabled: !_isSaving,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'اكتب وصفاً للريل...',
                filled: true,
                fillColor: AppColors.surfaceContainerLowest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text('المنتج الموسوم',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            _buildTagRow(),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!,
                  style: const TextStyle(color: AppColors.error),
                  textAlign: TextAlign.center),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: (_hasChanges && !_isSaving) ? _save : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('حفظ التعديلات'),
            ),
            const SizedBox(height: 12),
            const Text(
              'لا يمكن استبدال الفيديو نفسه — احذف الريل وانشر واحداً جديداً.',
              style: TextStyle(color: AppColors.onSurfaceVariant, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewRow() {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 64,
            height: 96,
            child: widget.reel.thumbnailUrl != null
                ? AppNetworkImage(widget.reel.thumbnailUrl!, fit: BoxFit.cover)
                : Container(
                    color: AppColors.surfaceContainer,
                    child: const Icon(Icons.videocam_outlined,
                        color: AppColors.onSurfaceVariant),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.reel.caption.isEmpty ? 'بدون وصف' : widget.reel.caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.visibility,
                      size: 14, color: AppColors.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text('${widget.reel.viewCount}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.onSurfaceVariant)),
                  const SizedBox(width: 12),
                  const Icon(Icons.favorite,
                      size: 14, color: AppColors.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text('${widget.reel.likesCount}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTagRow() {
    final title = _taggedTitle;
    if (title == null) {
      return OutlinedButton.icon(
        onPressed: _isSaving ? null : _pickTaggedItem,
        icon: const Icon(Icons.shopping_bag_outlined),
        label: const Text('وسم منتج (اختياري)'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
        ),
      );
    }
    final image = _taggedImage;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceContainer),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 40,
              height: 40,
              child: image != null
                  ? AppNetworkImage(image, fit: BoxFit.cover)
                  : Container(
                      color: AppColors.surfaceContainer,
                      child: const Icon(Icons.inventory_2_outlined,
                          size: 18, color: AppColors.onSurfaceVariant),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          TextButton(
            onPressed: _isSaving ? null : _pickTaggedItem,
            child: const Text('تغيير'),
          ),
          IconButton(
            tooltip: 'إزالة الوسم',
            icon: const Icon(Icons.close, size: 18),
            onPressed: _isSaving ? null : _clearTaggedItem,
          ),
        ],
      ),
    );
  }
}
