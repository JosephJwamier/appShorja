import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'app_network_image.dart';

/// عارض صور بملء الشاشة: تمرير بين الصور، وتكبير بالقرص.
///
/// شريط المنتج يعرض الصورة مقصوصة (`BoxFit.cover`) لتملأ عرض الشاشة —
/// وهو ما يناسب التصفّح لكنه يقتطع الحواف. والمشتري الذي يريد أن يتفحّص
/// بضاعة قبل أن يدفع يحتاج الصورة كاملة بلا قصّ، وبإمكان التكبير.
///
/// يُفتح على الصورة التي ضُغطت لا على الأولى: من ضغط الصورة الثالثة
/// يقصدها هي، وإعادته إلى البداية تجبره على التمرير إليها من جديد.
class ImageGalleryViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const ImageGalleryViewer({
    super.key,
    required this.images,
    this.initialIndex = 0,
  });

  static Future<void> open(
    BuildContext context, {
    required List<String> images,
    int initialIndex = 0,
  }) {
    if (images.isEmpty) return Future.value();
    return Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ImageGalleryViewer(
          images: images,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  @override
  State<ImageGalleryViewer> createState() => _ImageGalleryViewerState();
}

class _ImageGalleryViewerState extends State<ImageGalleryViewer> {
  late final PageController _controller;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex.clamp(0, widget.images.length - 1);
    _controller = PageController(initialPage: _current);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final many = widget.images.length > 1;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (context, index) => InteractiveViewer(
              // يسمح التكبير حتى 4x: تفاصيل القماش أو خدش في جهاز
              // مستعمل لا تظهر في عرض الشاشة.
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: AppNetworkImage(
                  widget.images[index],
                  // contain لا cover: بلا قصّ — هذا سبب فتح الشاشة أصلاً.
                  fit: BoxFit.contain,
                  width: double.infinity,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.broken_image,
                    size: 80,
                    color: AppColors.outline,
                  ),
                ),
              ),
            ),
          ),

          // الإغلاق فوق كل شيء، وبعيداً عن شريط الحالة.
          PositionedDirectional(
            top: MediaQuery.of(context).padding.top + 8,
            start: 8,
            child: _RoundIconButton(
              icon: Icons.close,
              onTap: () => Navigator.pop(context),
            ),
          ),

          if (many) ...[
            PositionedDirectional(
              bottom: MediaQuery.of(context).padding.bottom + 24,
              start: 0,
              end: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${_current + 1} / ${widget.images.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            ),

            // أسهم للتنقّل: التمرير يعمل، لكن الأسهم تُعلن أن هناك
            // المزيد — ومن لا يجرّب التمرير يظنّ الصورة وحيدة.
            if (_current > 0)
              PositionedDirectional(
                start: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _RoundIconButton(
                    icon: Icons.chevron_right,
                    onTap: () => _controller.previousPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    ),
                  ),
                ),
              ),
            if (_current < widget.images.length - 1)
              PositionedDirectional(
                end: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _RoundIconButton(
                    icon: Icons.chevron_left,
                    onTap: () => _controller.nextPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}
