import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_colors.dart';

/// لكل طرف في النزاع (services/disputes.py: MAX_IMAGES_EACH).
const kMaxDisputeImages = 5;

class DisputeImagesPicker extends StatelessWidget {
  final List<XFile> images;
  final int max;
  final ValueChanged<List<XFile>> onChanged;

  const DisputeImagesPicker({
    super.key,
    required this.images,
    required this.onChanged,
    this.max = kMaxDisputeImages,
  });

  Future<void> _pick() async {
    final picked = await ImagePicker()
        .pickMultiImage(imageQuality: 80, maxWidth: 1600);
    if (picked.isEmpty) return;
    onChanged([...images, ...picked].take(max).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final image in images)
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(image.path),
                    width: 72, height: 72, fit: BoxFit.cover),
              ),
              Positioned(
                top: 0,
                left: 0,
                child: GestureDetector(
                  onTap: () =>
                      onChanged(images.where((i) => i != image).toList()),
                  child: const CircleAvatar(
                    radius: 11,
                    backgroundColor: Colors.black54,
                    child: Icon(Icons.close, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        if (images.length < max)
          OutlinedButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.add_a_photo_outlined, size: 18),
            label: Text('صور (حتى $max)'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.onSurfaceVariant,
              minimumSize: const Size(72, 72),
            ),
          ),
      ],
    );
  }
}
