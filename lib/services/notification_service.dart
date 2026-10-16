import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef OnNotificationReceived = void Function(
    String title, String body, String type, Map<String, dynamic> data);

/// Fired when the user taps a notification (system tray or in-app banner)
/// while the app can navigate immediately — i.e. NOT for the cold-start
/// `getInitialMessage` case, which is stashed in [NotificationService.pendingTapType]
/// / [NotificationService.pendingTapData] instead since no navigator exists yet.
typedef OnNotificationTap = void Function(
    String type, Map<String, dynamic> data);

OnNotificationReceived? _onNotificationReceived;
OnNotificationTap? _onNotificationTapCallback;

/// معرّفات أزرار الإشعار. تصل في NotificationResponse.actionId.
const String kActionCompleteReservation = 'complete_reservation';
const String kActionDismiss = 'dismiss';

/// بناء إشعار بأزرار من حمولة بيانات.
///
/// الخادم يرسل هذا النوع **بلا كتلة notification** عمداً: ما دامت موجودة
/// يرسم أندرويد الإشعار بنفسه في الخلفية — بلا أزرار ولا سبيل لإضافتها.
/// فالأزرار تعني أن التطبيق هو من يبني، هنا وفي المقدّمة على السواء.
Future<void> _showActionableNotification(
  FlutterLocalNotificationsPlugin plugin,
  Map<String, dynamic> data,
) async {
  final title = data['title'] as String? ?? 'الشورجة';
  final body = data['body'] as String? ?? '';

  await plugin.show(
    data['reservation_id'].hashCode,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        'high_importance_channel',
        'إشعارات الشورجة',
        channelDescription: 'إشعارات الحجوزات والمزادات والرسائل',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        actions: const [
          AndroidNotificationAction(
            kActionCompleteReservation,
            'أكمل الحجز',
            showsUserInterface: true, // يفتح التطبيق على الحجز
          ),
          AndroidNotificationAction(
            kActionDismiss,
            'لاحقاً',
            cancelNotification: true,
          ),
        ],
      ),
      iOS: const DarwinNotificationDetails(),
    ),
    payload: jsonEncode(data),
  );
}

@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  // رسالة بيانات فقط: لا يرسم أندرويد شيئاً، فإن لم نبنِه هنا لم يرَ
  // المستخدم إشعاراً إطلاقاً.
  if (message.data['actionable'] == '1') {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ));
    await _showActionableNotification(plugin, message.data);
    return;
  }
  debugPrint('[FCM Background] ${message.notification?.title}');
}

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'high_importance_channel';
  static const _channelName = 'الإشعارات المهمة';
  static const _channelDesc = 'إشعارات تطبيق الشورجة';

  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
    _channelId,
    _channelName,
    description: _channelDesc,
    importance: Importance.high,
  );

  /// Exposes the Firebase token-refresh stream so callers can sync the new
  /// token to the backend whenever Firebase rotates it.
  static Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  /// Set when the app is launched (cold start) by tapping a notification,
  /// i.e. via `getInitialMessage()` — at that point no navigator/widget tree
  /// exists yet, so the tap can't be handled immediately. The app shell reads
  /// and clears these once it has mounted and the user is authenticated.
  static String? pendingTapType;
  static Map<String, dynamic>? pendingTapData;

  /// Call once from main() after Firebase.initializeApp()
  static Future<void> initialize({
    OnNotificationReceived? onReceived,
    OnNotificationTap? onTap,
  }) async {
    _onNotificationReceived = onReceived;
    _onNotificationTapCallback = onTap;

    FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _localNotifications.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    // App was backgrounded (not terminated) and the user tapped the system
    // notification to resume it — the navigator already exists, so this can
    // navigate immediately.
    FirebaseMessaging.onMessageOpenedApp.listen(_handleRemoteMessageTap);

    // App was terminated and got launched by tapping the notification — no
    // navigator exists yet, so stash the payload for the app shell to consume.
    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      pendingTapType = initial.data['type'] as String? ?? 'general';
      pendingTapData = initial.data;
    }

    // مسار منفصل للإشعارات التفاعلية: هذه يبنيها التطبيق محلياً، فلا
    // يعرفها getInitialMessage() ولا onMessageOpenedApp — كلاهما يخصّ
    // إشعارات رسمها FCM. بدون هذا الفرع يفتح الضغط على «أكمل الحجز»
    // التطبيقَ على الشاشة الرئيسية وكأن الزرّ لم يُضغط.
    final launch =
        await _localNotifications.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      final response = launch!.notificationResponse;
      if (response?.actionId != kActionDismiss && response?.payload != null) {
        try {
          final data =
              jsonDecode(response!.payload!) as Map<String, dynamic>;
          pendingTapType = data['type'] as String? ?? 'general';
          pendingTapData = data;
        } catch (e) {
          debugPrint('[FCM] Bad launch payload: $e');
        }
      }
    }
  }

  static const _permissionRequestedKey = 'notification_permission_requested';

  /// Requests the OS notification permission the first time the user does
  /// something that actually benefits from it (e.g. follows a store or
  /// places their first bid) instead of at cold start, before they have any
  /// context for why the app wants it. Asking in-context roughly doubles
  /// opt-in rates, so this must be called from those moments rather than
  /// from [initialize]. Only fires once per install.
  static Future<void> requestPermissionIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_permissionRequestedKey) ?? false) return;
    await prefs.setBool(_permissionRequestedKey, true);
    await _requestPermission();
  }

  static Future<void> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint('[FCM] Permission: ${settings.authorizationStatus}');

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static void _onForegroundMessage(RemoteMessage message) {
    // تفاعليّ: يُبنى بأزراره حتى في المقدّمة، وبيانات فقط تعني أن
    // message.notification فارغة فلا يصلح الفرع أدناه أصلاً.
    if (message.data['actionable'] == '1') {
      _showActionableNotification(_localNotifications, message.data);
      _onNotificationReceived?.call(
        message.data['title'] as String? ?? '',
        message.data['body'] as String? ?? '',
        message.data['type'] as String? ?? 'general',
        message.data,
      );
      return;
    }

    final notification = message.notification;
    if (notification == null) return;

    final title = notification.title ?? '';
    final body = notification.body ?? '';
    final type = message.data['type'] as String? ?? 'general';

    _localNotifications.show(
      notification.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      // Carried so a tap on this foreground banner (routed to
      // _onLocalNotificationTap) can navigate to the same destination as a
      // tap on a background/terminated-app system notification would.
      payload: jsonEncode(message.data),
    );

    _onNotificationReceived?.call(title, body, type, message.data);
  }

  /// App was backgrounded (not terminated) and the user tapped the system
  /// notification to resume it, or `getInitialMessage()` deferred here isn't
  /// used — the navigator already exists, so this navigates immediately.
  static void _handleRemoteMessageTap(RemoteMessage message) {
    final type = message.data['type'] as String? ?? 'general';
    debugPrint('[FCM Tap] type=$type');
    _onNotificationTapCallback?.call(type, message.data);
  }

  /// The user tapped the local (foreground) notification banner shown by
  /// [_onForegroundMessage]. Decodes the payload stashed there back into the
  /// original data map so it can be routed the same way as a remote tap.
  static void _onLocalNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;
    // «لاحقاً» يُغلق الإشعار ولا يفتح شيئاً: من ضغطه قال إنه مشغول،
    // وفتح التطبيق عليه يناقض ما طلبه.
    if (response.actionId == kActionDismiss) return;

    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final type = data['type'] as String? ?? 'general';
      _onNotificationTapCallback?.call(type, data);
    } catch (e) {
      debugPrint('[FCM] Failed to decode local notification payload: $e');
    }
  }

  /// Returns the FCM registration token for this device.
  /// Retries up to [retries] times with a short delay if the token is null
  /// (can happen briefly after app install or after Firebase re-registration).
  static Future<String?> getToken({int retries = 3}) async {
    for (var i = 0; i < retries; i++) {
      try {
        final token = await _messaging.getToken();
        if (token != null) {
          debugPrint('[FCM] Token obtained (attempt ${i + 1}): ${token.substring(0, 20)}...');
          return token;
        }
        debugPrint('[FCM] getToken returned null (attempt ${i + 1}/$retries), retrying...');
        await Future.delayed(const Duration(seconds: 2));
      } catch (e) {
        debugPrint('[FCM] getToken error (attempt ${i + 1}): $e');
        if (i < retries - 1) await Future.delayed(const Duration(seconds: 2));
      }
    }
    debugPrint('[FCM] Failed to obtain token after $retries attempts');
    return null;
  }

  /// Send an immediate local test notification (no backend/Firebase needed)
  static Future<void> sendTestNotification() async {
    const title = 'إشعار تجريبي';
    const body = 'الإشعارات تعمل بشكل صحيح!';

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );

    _onNotificationReceived?.call(title, body, 'test', const {});
  }
}
