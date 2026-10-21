import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import '../../models/reel.dart';
import '../app_network_image.dart';

const _mutePrefKey = 'reels_muted';

/// كم يُسمح للفيديو أن يُقصّ عند ملء الشاشة قبل أن نتحوّل إلى احتوائه كاملاً
/// بين شريطين أسودين. النسبة هي `أكبر البعدين ÷ أصغرهما` بين نسبة الفيديو
/// ونسبة الصندوق، و1.35 تُبقي كل الصيغ العمودية المعتادة (9:16 وأطول) ملء
/// الشاشة على هواتف 20:9، بينما يُحتوى المربّع و4:3 والأفقي بدل اقتطاع ثلث
/// الكادر منها.
const _maxCoverCropFactor = 1.35;

/// ما يحتاجه بانِي الطبقة العلوية عن الصفحة المعروضة حالياً.
class ReelPageInfo {
  final Reel reel;
  final int index;
  final bool isMuted;
  final VoidCallback onMuteToggle;

  const ReelPageInfo({
    required this.reel,
    required this.index,
    required this.isMuted,
    required this.onMuteToggle,
  });
}

typedef ReelOverlayBuilder = Widget Function(BuildContext context, ReelPageInfo info);

/// مشغّل عمودي بفيديو واحد لكل صفحة، تتشارَكه خلاصة الريلز العامة
/// (`ReelsFeedScreen`) وشاشة مشاهدة المالك لريلزاته (`MyReelViewerScreen`).
///
/// يملك شيئاً واحداً: نافذة مشغّلات الفيديو. لا يبقى حيّاً سوى مشغّل الصفحة
/// الحالية ومشغّل التالية (تحميل مسبق كي لا يظهر مؤشّر انتظار عند السحب
/// للأمام)، وأي مشغّل أبعد من ذلك يُتخلَّص منه فوراً. التشغيل يتبع الصفحة
/// النشطة، ويتوقّف عند تصغير التطبيق أو عند صيرورة [isActive] خطأً — وهذه
/// الأخيرة هي كيف تقول الشاشة المضيفة «ما زلتُ مركّبة لكنّي لم أعد ظاهرة»
/// (خلف تبويب آخر أو تحت شاشة مدفوعة)، وهي حالة يُخفيها IndexedStack فيظلّ
/// الريل يعمل — ويُسمع — بلا أن يُرى.
///
/// كل ما عدا ذلك يخصّ المضيف ويصل عبر [overlayBuilder] و[onPageChanged]: أي
/// طبقة تُرسم فوق الفيديو، وهل تُسجَّل مشاهدة، وهل تُجلب صفحات إضافية.
///
/// الكتم يُحفظ هنا لا في كل مضيف على حدة: هو تفضيل واحد عن الريلز عموماً،
/// ومن كتم الخلاصة يتوقّع أن تكون ريلزاته مكتومة أيضاً.
class ReelVideoPager extends StatefulWidget {
  final List<Reel> reels;
  final int initialIndex;
  final bool isActive;
  final ValueChanged<int>? onPageChanged;

  /// يُنادى مرّة واحدة حين يبلغ المشاهد نهاية ريل.
  ///
  /// أقوى إشارة اهتمام وأرخصها: الإعجاب والتعليق فعلان واعيان يفعلهما
  /// قلّة، وإكمال المشاهدة يفعله كل من أعجبه الريل بلا أن يُطلب منه شيء.
  /// والفيديو يُعاد تلقائياً (`setLooping`)، فلولا حارسٌ لتكرّر النداء مع
  /// كل دورة.
  final ValueChanged<int>? onCompleted;

  final ReelOverlayBuilder overlayBuilder;

  const ReelVideoPager({
    super.key,
    required this.reels,
    required this.overlayBuilder,
    this.initialIndex = 0,
    this.isActive = true,
    this.onPageChanged,
    this.onCompleted,
  });

  @override
  State<ReelVideoPager> createState() => _ReelVideoPagerState();
}

class _ReelVideoPagerState extends State<ReelVideoPager>
    with WidgetsBindingObserver {
  late final PageController _pageController =
      PageController(initialPage: widget.initialIndex);
  final Map<int, VideoPlayerController> _controllers = {};

  late int _currentIndex = widget.initialIndex;
  bool _isMuted = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _isMuted = prefs.getBool(_mutePrefKey) ?? true);
    _syncControllerWindow();
  }

  @override
  void didUpdateWidget(ReelVideoPager oldWidget) {
    super.didUpdateWidget(oldWidget);

    // إعادة تحميل (أو حذف ريل) قد تضع ريلاً مختلفاً في الفهرس نفسه، والمشغّل
    // المخزَّن هناك سيعرض عندها الفيديو الخطأ. نُسقط كل مشغّل تغيّر معرّف
    // ريله، ونترك البقية كما هي حتى لا يُقطع التشغيل بلا داعٍ.
    for (final index in _controllers.keys.toList()) {
      final oldId = index < oldWidget.reels.length ? oldWidget.reels[index].id : null;
      final newId = index < widget.reels.length ? widget.reels[index].id : null;
      if (oldId != newId) _disposeControllerAt(index);
    }

    if (widget.reels.isEmpty) return;

    // انكمشت القائمة تحت الصفحة المعروضة (حذف الريل الأخير مثلاً).
    if (_currentIndex >= widget.reels.length) {
      _currentIndex = widget.reels.length - 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(_currentIndex);
        }
      });
    }

    _syncControllerWindow();
    if (widget.isActive != oldWidget.isActive) _applyPlaybackState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final current = _controllers[_currentIndex];
    if (current == null || !current.value.isInitialized) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      current.pause();
    } else if (state == AppLifecycleState.resumed && widget.isActive) {
      current.play();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    for (final c in _controllers.values) {
      c.pause();
      c.dispose();
    }
    super.dispose();
  }

  // ---- إدارة نافذة المشغّلات --------------------------------------------

  void _disposeControllerAt(int index) {
    final controller = _controllers.remove(index);
    controller?.pause();
    controller?.dispose();
  }

  Future<void> _initController(int index) async {
    if (_controllers.containsKey(index)) return;
    if (index < 0 || index >= widget.reels.length) return;
    final reel = widget.reels[index];
    if (reel.videoUrl.isEmpty) return;

    final controller = VideoPlayerController.networkUrl(Uri.parse(reel.videoUrl));
    _controllers[index] = controller;
    try {
      await controller.initialize();
      if (!mounted || _controllers[index] != controller) {
        // تم التخلص من هذا المتحكم أثناء التهيئة (خرج المستخدم من النافذة).
        await controller.dispose();
        return;
      }
      await controller.setLooping(true);
      await controller.setVolume(_isMuted ? 0 : 1);
      controller.addListener(() => _checkCompleted(index, controller));
      if (index == _currentIndex && widget.isActive) controller.play();
      if (mounted) setState(() {});
    } catch (_) {
      _controllers.remove(index);
      controller.dispose();
    }
  }

  /// الريلز التي بُلّغ عن إكمالها في هذه الجلسة — فلا يتكرّر البلاغ مع
  /// كل دورة إعادة ولا مع كل مرور على الصفحة.
  final Set<int> _completedReelIds = {};

  /// بلغ المشاهد النهاية؟
  ///
  /// بهامش نصف ثانية لا بتطابق تامّ: آخر إطار قد لا يُبلَّغ عنه بدقّة،
  /// ومع `setLooping` يقفز الموضع إلى الصفر فور الانتهاء — فانتظار
  /// التساوي التامّ يعني ألّا يُحتسب إكمال أبداً.
  void _checkCompleted(int index, VideoPlayerController controller) {
    if (widget.onCompleted == null) return;
    if (index < 0 || index >= widget.reels.length) return;

    final value = controller.value;
    if (!value.isInitialized) return;
    final duration = value.duration;
    if (duration <= Duration.zero) return;

    final reelId = widget.reels[index].id;
    if (_completedReelIds.contains(reelId)) return;

    if (value.position >= duration - const Duration(milliseconds: 500)) {
      _completedReelIds.add(reelId);
      widget.onCompleted!(index);
    }
  }

  void _syncControllerWindow() {
    final keep = {_currentIndex - 1, _currentIndex, _currentIndex + 1}
        .where((i) => i >= 0 && i < widget.reels.length)
        .toSet();

    for (final k in _controllers.keys.where((k) => !keep.contains(k)).toList()) {
      _disposeControllerAt(k);
    }

    // الحالي أولاً، ثم التالي للتحميل المسبق.
    _initController(_currentIndex);
    _initController(_currentIndex + 1);
  }

  void _applyPlaybackState() {
    _controllers.forEach((index, controller) {
      if (!controller.value.isInitialized) return;
      if (index == _currentIndex && widget.isActive) {
        controller.play();
      } else {
        controller.pause();
      }
    });
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
    _syncControllerWindow();
    _applyPlaybackState();
    widget.onPageChanged?.call(index);
  }

  Future<void> _toggleMute() async {
    setState(() => _isMuted = !_isMuted);
    for (final c in _controllers.values) {
      if (c.value.isInitialized) c.setVolume(_isMuted ? 0 : 1);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_mutePrefKey, _isMuted);
  }

  void _togglePlayPause(int index) {
    final controller = _controllers[index];
    if (controller == null || !controller.value.isInitialized) return;
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        controller.play();
      }
    });
  }

  // ---- العرض -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      itemCount: widget.reels.length,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, index) {
        final reel = widget.reels[index];
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: _buildVideoArea(reel, index)),
            SafeArea(
              child: widget.overlayBuilder(
                context,
                ReelPageInfo(
                  reel: reel,
                  index: index,
                  isMuted: _isMuted,
                  onMuteToggle: _toggleMute,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// ملء الشاشة إن كانت نسبة الفيديو قريبة من نسبتها، وإلّا احتواؤه كاملاً
  /// بين شريطين أسودين.
  ///
  /// `BoxFit.cover` وحده يقتطع من الفيديوهات المربّعة أو الأفقية ما يقارب ثلث
  /// الكادر رأسياً، فيضيع رأس المتحدّث أو المنتج نفسه. والعكس (`contain`
  /// دائماً) يترك شريطين أسودين حتى لريل 9:16 عمودي كان سيملأ الشاشة تماماً.
  /// لذا نقيس نسبة القصّ ونختار.
  ///
  /// [box] هو مربّع العرض الفعلي وليس الشاشة كاملة — فهو أقصر منها بارتفاع
  /// شريط التنقّل السفلي، والفرق يكفي لقلب القرار على الشاشات العريضة.
  BoxFit _fitForVideo(VideoPlayerController controller, Size box) {
    if (box.width <= 0 || box.height <= 0) return BoxFit.contain;
    final videoAspect = controller.value.aspectRatio;
    if (videoAspect <= 0) return BoxFit.contain;

    final boxAspect = box.width / box.height;
    final crop = videoAspect > boxAspect
        ? videoAspect / boxAspect
        : boxAspect / videoAspect;
    return crop <= _maxCoverCropFactor ? BoxFit.cover : BoxFit.contain;
  }

  Widget _buildVideoArea(Reel reel, int index) {
    final controller = _controllers[index];
    if (controller != null && controller.value.isInitialized) {
      return GestureDetector(
        onTap: () => _togglePlayPause(index),
        // opaque: في وضع contain يصبح ما حول الفيديو شريطين أسودين، ونريد
        // النقر عليهما أن يوقف/يشغّل أيضاً كما داخل الكادر.
        behavior: HitTestBehavior.opaque,
        child: ColoredBox(
          color: Colors.black,
          child: LayoutBuilder(
            // SizedBox.expand وليس Center: تحت قيود مرنة يتقلّص FittedBox إلى
            // الحجم الطبيعي للفيديو ولا يُكبّره أبداً — والريلز مضغوطة على
            // الجهاز قبل الرفع، فدقّتها أصغر من دقّة الشاشة، فكانت تُعرض
            // بمقاسها الأصلي وسط سواد بدل أن تملأ الشاشة. القيود الضيّقة هنا
            // هي ما يجعل cover/contain يعملان على مساحة الشاشة كاملة.
            builder: (context, constraints) => SizedBox.expand(
              child: FittedBox(
                fit: _fitForVideo(controller, constraints.biggest),
                // cover يتجاوز حدود الصندوق بطبيعته، وبدون قصّ يرتسم الفائض
                // فوق طبقة الأزرار وفوق الصفحة المجاورة في PageView.
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: controller.value.size.width,
                  height: controller.value.size.height,
                  child: VideoPlayer(controller),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        reel.thumbnailUrl != null
            ? AppNetworkImage(reel.thumbnailUrl!, fit: BoxFit.cover)
            : Container(color: Colors.black),
        const Center(child: CircularProgressIndicator(color: Colors.white)),
      ],
    );
  }
}
