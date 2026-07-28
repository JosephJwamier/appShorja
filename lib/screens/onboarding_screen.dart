import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class _OnboardingSlide {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String description;
  const _OnboardingSlide({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.description,
  });
}

const _slides = [
  _OnboardingSlide(
    icon: Icons.storefront_outlined,
    iconColor: AppColors.primary,
    iconBg: AppColors.primaryFixed,
    title: 'تصفّح واشترِ بثقة',
    description:
        'آلاف المنتجات من متاجر حقيقية — بسعر ثابت أو عبر مزاد مباشر، كلها بمكان واحد.',
  ),
  _OnboardingSlide(
    icon: Icons.gavel_rounded,
    iconColor: AppColors.tertiary,
    iconBg: AppColors.tertiaryFixed,
    title: 'مزادات وبث مباشر',
    description:
        'زايد لحظيًا على المنتجات، أو شاهد بث مباشر من المتجر واحجز المنتج فور ظهوره.',
  ),
  _OnboardingSlide(
    icon: Icons.verified_user_outlined,
    iconColor: AppColors.secondary,
    iconBg: AppColors.secondaryFixed,
    title: 'ادفع بأمان',
    description:
        'اختر عربونًا بسيطًا الآن والباقي كاش عند الاستلام، أو ادفع كامل المبلغ — '
        'أموالك تبقى محفوظة حتى تؤكّد استلام منتجك.',
  ),
  _OnboardingSlide(
    icon: Icons.local_shipping_outlined,
    iconColor: AppColors.primary,
    iconBg: AppColors.primaryFixed,
    title: 'تتبّع التوصيل خطوة بخطوة',
    description:
        'تابع حالة طلبك حتى وصوله، وأكّد الاستلام لإتمام العملية وتحرير المبلغ للبائع.',
  ),
];

/// One-time first-launch walkthrough of what makes this app different
/// (fixed-price + auctions + live shopping) and how the deposit/full-payment
/// + escrow-style delivery flow works, at a high level. [onDone] persists
/// the "seen" flag and is called on both "ابدأ الآن" and "تخطّي" — shown
/// only once per install, driven by AuthGate in main.dart.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_index == _slides.length - 1) {
      widget.onDone();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _index == _slides.length - 1;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextButton(
                    onPressed: widget.onDone,
                    child: const Text(
                      'تخطّي',
                      style: TextStyle(color: AppColors.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _slides.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) {
                    final s = _slides[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              color: s.iconBg,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(s.icon, size: 64, color: s.iconColor),
                          ),
                          const SizedBox(height: 36),
                          Text(
                            s.title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            s.description,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 15,
                              height: 1.6,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _slides.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _index ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _index
                          ? AppColors.primary
                          : AppColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: SizedBox(
                  height: 54,
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _next,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      isLast ? 'ابدأ الآن' : 'التالي',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
