import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../utils/refreshable_tab.dart';
import '../../utils/visibility_aware_tab.dart';
import '../../widgets/media/media_tab_switcher.dart';
import '../live/live_sessions_screen.dart';
import '../reels/reels_feed_screen.dart';

/// تبويب «ميديا» الموحّد في `MainShell`: الريلز تظهر أولاً، والبث المباشر
/// خلف مبدّل نصّي من كلمتين أعلى الشاشة.
///
/// لماذا مضيف بدل دمج الشاشتين في واحدة: كلٌّ منهما تدير حالة ثقيلة مستقلة —
/// [ReelsFeedScreen] تدير نافذة مشغّلات فيديو ومؤقّت تسجيل مشاهدة وتفضيل كتم
/// محفوظاً، و[LiveSessionsScreen] تدير شبكة وترتيباً وبروفايدر منفصلاً — فيبقى
/// كلٌّ في ملفه، ويتولّى هذا المضيف التبديل ودورة الحياة فقط.
///
/// دورة الحياة: [IndexedStack] يُبقي الطفلين حيّين، لذا نمرّر إشارات
/// [VisibilityAwareTab] إلى الطفل النشط وحده. بدونها يظلّ فيديو الريل يعمل
/// خلف شاشة البث فيسمع المستخدم صوتين معاً.
class MediaHubScreen extends StatefulWidget {
  const MediaHubScreen({super.key});

  @override
  State<MediaHubScreen> createState() => MediaHubScreenState();
}

class MediaHubScreenState extends State<MediaHubScreen>
    implements RefreshableTab, VisibilityAwareTab {
  static const _reelsIndex = 0;
  static const _liveIndex = 1;

  final _reelsKey = GlobalKey();
  final _liveKey = GlobalKey();

  int _subIndex = _reelsIndex;

  /// شاشة البث لا تُبنى قبل أوّل فتح لها — وإلا انطلق طلب قائمة البثوث عند
  /// إقلاع التطبيق (حيث تُبنى كل تبويبات `MainShell` دفعةً واحدة) لمستخدم قد
  /// لا يفتح البث إطلاقاً.
  bool _liveEverOpened = false;

  GlobalKey? _keyFor(int index) => switch (index) {
        _reelsIndex => _reelsKey,
        _liveIndex => _liveEverOpened ? _liveKey : null,
        _ => null,
      };

  void _notifyVisibility(int index, {required bool visible}) {
    final state = _keyFor(index)?.currentState;
    if (state is! VisibilityAwareTab) return;
    final aware = state as VisibilityAwareTab;
    if (visible) {
      aware.onTabVisible();
    } else {
      aware.onTabHidden();
    }
  }

  void _refreshChild(int index) {
    final state = _keyFor(index)?.currentState;
    if (state is RefreshableTab) (state as RefreshableTab).refreshTab();
  }

  void _select(int index) {
    if (index == _subIndex) return;
    final liveAlreadyBuilt = _liveEverOpened;

    _notifyVisibility(_subIndex, visible: false);
    setState(() {
      _subIndex = index;
      if (index == _liveIndex) _liveEverOpened = true;
    });

    // بعد الإطار: عند أوّل فتح للبث يكون الطفل قد بُني للتوّ، فلا وجود لـ
    // currentState قبل اكتمال هذا الإطار.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notifyVisibility(index, visible: true);
      // البثوث تنتهي بسرعة، فقائمة قديمة تعني بطاقات لبثوث ميتة — نحدّثها
      // كلّما عاد المستخدم إليها. الريلز على العكس: تحديثها يعيد الخلاصة إلى
      // أوّلها فيفقد المستخدم موضعه، لذا لا نحدّثها هنا.
      if (index == _liveIndex && liveAlreadyBuilt) _refreshChild(_liveIndex);
    });
  }

  // ---- عقود التبويب المُمرَّرة من MainShell إلى الطفل النشط --------------

  @override
  Future<void> refreshTab() async => _refreshChild(_subIndex);

  @override
  void onTabHidden() => _notifyVisibility(_subIndex, visible: false);

  @override
  void onTabVisible() => _notifyVisibility(_subIndex, visible: true);

  @override
  Widget build(BuildContext context) {
    final isReels = _subIndex == _reelsIndex;
    final switcher = MediaTabSwitcher(
      selectedIndex: _subIndex,
      onSelected: _select,
      onDark: isReels,
    );

    return Stack(
      children: [
        Positioned.fill(
          child: IndexedStack(
            index: _subIndex,
            children: [
              // startVisible: false — هذا المضيف هو من يقرّر متى يبدأ التشغيل
              // عبر [onTabVisible]، وإلّا انطلق الفيديو عند إقلاع التطبيق
              // بينما المستخدم على تبويب آخر.
              ReelsFeedScreen(key: _reelsKey, startVisible: false),
              _liveEverOpened
                  ? LiveSessionsScreen(key: _liveKey, embedded: true)
                  : const SizedBox.shrink(),
            ],
          ),
        ),
        // الشريط العلوي. في وضع الريلز نتركه شفافاً وبعرض المبدّل وحده حتى
        // تمرّ اللمسات إلى زرّي «ريلزاتي» و«كتم الصوت» على طرفَي الشاشة؛ وفي
        // وضع البث نملأ العرض بلون السطح ليقرأ كترويسة بديلة عن AppBar
        // المحذوف، فلا يمرّ محتوى الشبكة تحته.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: MediaTabSwitcher.height,
              child: isReels
                  ? Center(child: switcher)
                  : ColoredBox(
                      color: AppColors.surface,
                      child: Center(child: switcher),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
