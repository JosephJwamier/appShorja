import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../models/product_review.dart';
import '../../providers/auth_provider.dart';
import '../../providers/review_provider.dart';
import '../../theme/app_colors.dart';
import 'star_rating_widget.dart';

class AddEditReviewBottomSheet extends StatefulWidget {
  final ProductReview? existing;

  const AddEditReviewBottomSheet({super.key, this.existing});

  @override
  State<AddEditReviewBottomSheet> createState() =>
      _AddEditReviewBottomSheetState();
}

class _AddEditReviewBottomSheetState extends State<AddEditReviewBottomSheet> {
  late int _score;
  late TextEditingController _commentCtrl;
  XFile? _pickedImage;
  String? _error;
  bool _isSubmitting = false;

  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _score = widget.existing?.score ?? 0;
    _commentCtrl = TextEditingController(text: widget.existing?.comment ?? '');
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.existing != null;

  Future<void> _pickImage(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1200,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      setState(() => _error = 'حجم الصورة يجب أن لا يتجاوز 5 ميجابايت');
      return;
    }
    setState(() => _pickedImage = file);
  }

  Future<void> _submit() async {
    if (_score == 0) {
      setState(() => _error = 'يرجى اختيار تقييم من نجمة إلى خمس نجوم');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    final token = context.read<AuthProvider>().accessToken;
    if (token == null) {
      setState(() {
        _isSubmitting = false;
        _error = 'يجب تسجيل الدخول أولاً';
      });
      return;
    }

    final provider = context.read<ReviewProvider>();

    try {
      if (_isEdit) {
        await provider.updateReview(
          token: token,
          reviewId: widget.existing!.id,
          score: _score,
          comment: _commentCtrl.text.trim(),
          image: _pickedImage,
        );
      } else {
        await provider.createReview(
          token: token,
          score: _score,
          comment: _commentCtrl.text.trim(),
          image: _pickedImage,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      if (msg == '401') {
        if (mounted) Navigator.pop(context);
        return;
      }
      if (msg == '403') {
        setState(() {
          _isSubmitting = false;
          _error = 'غير مسموح بهذه العملية';
        });
        return;
      }
      if (msg == '500') {
        setState(() {
          _isSubmitting = false;
          _error = 'خطأ في الخادم، حاول مجدداً';
        });
        return;
      }
      setState(() {
        _isSubmitting = false;
        _error = msg;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomPad),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Title
            Text(
              _isEdit ? 'تعديل تقييمك' : 'أضف تقييمك',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'شاركنا رأيك لمساعدة الآخرين',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            // Star selector
            Center(
              child: Column(
                children: [
                  StarSelector(
                    selected: _score,
                    onChanged: (v) => setState(() => _score = v),
                    size: 46,
                  ),
                  const SizedBox(height: 8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      _starLabel(_score),
                      key: ValueKey(_score),
                      style: TextStyle(
                        color: _score > 0
                            ? AppColors.primary
                            : AppColors.onSurfaceVariant,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Comment field
            TextField(
              controller: _commentCtrl,
              maxLines: 4,
              maxLength: 500,
              textDirection: TextDirection.rtl,
              decoration: InputDecoration(
                hintText: 'شارك تجربتك مع هذا المنتج (اختياري)',
                hintTextDirection: TextDirection.rtl,
                filled: true,
                fillColor: AppColors.surfaceContainerLowest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.surfaceContainer),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.surfaceContainer),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Image picker
            _buildImagePicker(),
            // Error banner
            if (_error != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: AppColors.error, size: 17),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                            color: AppColors.error, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            // Submit button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      AppColors.primary.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        _isEdit ? 'حفظ التعديل' : 'إرسال التقييم',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePicker() {
    if (_pickedImage != null) {
      return Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              File(_pickedImage!.path),
              width: 80,
              height: 80,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('تم اختيار الصورة',
                  style: TextStyle(
                      fontSize: 13, color: AppColors.onSurfaceVariant)),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () => setState(() => _pickedImage = null),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('إزالة'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.error,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'إضافة صورة (اختياري)',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _PickerButton(
              icon: Icons.camera_alt_outlined,
              label: 'الكاميرا',
              onTap: () => _pickImage(ImageSource.camera),
            ),
            const SizedBox(width: 10),
            _PickerButton(
              icon: Icons.photo_library_outlined,
              label: 'المعرض',
              onTap: () => _pickImage(ImageSource.gallery),
            ),
          ],
        ),
      ],
    );
  }

  String _starLabel(int score) {
    switch (score) {
      case 1:
        return 'سيء جداً ★';
      case 2:
        return 'سيء ★★';
      case 3:
        return 'مقبول ★★★';
      case 4:
        return 'جيد ★★★★';
      case 5:
        return 'ممتاز! ★★★★★';
      default:
        return 'اضغط لاختيار تقييمك';
    }
  }
}

class _PickerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PickerButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          border: Border.all(color: AppColors.surfaceContainer),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: AppColors.secondary),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
