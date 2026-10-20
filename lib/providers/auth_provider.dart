import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart'
    show FirebaseAuth;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../services/analytics_service.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import 'notifications_provider.dart';
import 'chats_provider.dart';

/// Firestore-based chat is paused while Firebase billing is disabled — live
/// chat uses the WebSocket transport instead. The old Firestore-backed chat
/// implementation was removed (not just disabled) since it had already been
/// dead code for a while; reactivating this would mean rebuilding it.
const bool kFirestoreChatEnabled = false;

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  // Tokens are the credential that grants account access, so they live in
  // Keychain/Keystore rather than SharedPreferences' plaintext XML/plist —
  // the cached user profile below is just display data, not a credential.
  static const _secureStorage = FlutterSecureStorage();

  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _userKey = 'user_data';

  User? _user;
  String? _accessToken;
  String? _refreshToken;
  bool _isLoading = false;
  String? _errorMessage;

  // Subscription to Firebase token rotations
  StreamSubscription<String>? _tokenRefreshSub;

  User? get user => _user;
  String? get accessToken => _accessToken;

  /// الرمز للقراءات المفتوحة للجميع — فارغٌ للضيف لا `null`.
  ///
  /// `ApiClient` يحذف ترويسة `Authorization` كلّها عند الفراغ، فالطلب يصل
  /// الخادم كزائر فعلاً ويُجاب. استعملها في كل نداء تصفّح (منتجات، فئات،
  /// متاجر، مزادات، ريلز) بدل حراسة `if (token == null) return` — فتلك
  /// كانت تمنع الشاشة من المحاولة أصلاً، فتبقى فارغةً للضيف بينما نقاط
  /// الخادم مفتوحة له (AllowAny) وتنتظر طلباً لا يأتي.
  ///
  /// وما يحتاج هوية فعلاً لا يُحرَس بهذه بل بـ`requireAuth` — فتُطلب
  /// بوضوح بدل أن يضغط المستخدم زرّاً لا يفعل شيئاً.
  String get browseToken => _accessToken ?? '';
  String? get refreshToken => _refreshToken;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isLoggedIn => _accessToken != null;

  AuthProvider() {
    // Wires ApiClient to always see the live tokens (and to persist a
    // refreshed pair back here) without ApiClient needing to import this
    // file — see services/api_client.dart for why.
    ApiClient.instance.configure(
      getAccessToken: () => _accessToken,
      getRefreshToken: () => _refreshToken,
      onTokensRefreshed: (access, refresh) {
        _accessToken = access;
        _refreshToken = refresh;
        _secureStorage.write(key: _accessTokenKey, value: access);
        _secureStorage.write(key: _refreshTokenKey, value: refresh);
        notifyListeners();
      },
      onSessionExpired: _clearLocalSession,
    );
  }

  Future<void> tryAutoLogin({
    NotificationsProvider? notificationsProvider,
    ChatsProvider? chatsProvider,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    var savedAccess = await _secureStorage.read(key: _accessTokenKey);
    var savedRefresh = await _secureStorage.read(key: _refreshTokenKey);

    // One-time migration for installs from before tokens moved to secure
    // storage: an existing session in plaintext SharedPreferences should
    // still resume instead of silently signing the user out.
    if (savedAccess == null || savedRefresh == null) {
      final legacyAccess = prefs.getString(_accessTokenKey);
      final legacyRefresh = prefs.getString(_refreshTokenKey);
      if (legacyAccess != null && legacyRefresh != null) {
        await _secureStorage.write(key: _accessTokenKey, value: legacyAccess);
        await _secureStorage.write(key: _refreshTokenKey, value: legacyRefresh);
        await prefs.remove(_accessTokenKey);
        await prefs.remove(_refreshTokenKey);
        savedAccess = legacyAccess;
        savedRefresh = legacyRefresh;
      }
    }

    final savedUserJson = prefs.getString(_userKey);

    if (savedAccess != null && savedRefresh != null) {
      _accessToken = savedAccess;
      _refreshToken = savedRefresh;
      if (savedUserJson != null) {
        _user = User.fromJson(
          jsonDecode(savedUserJson) as Map<String, dynamic>,
        );
      } else {
        // رمز بلا مستخدم: جلسة نصفها محفوظ. تحدث لمن سجّل بنسخة سابقة
        // لا تحفظ المستخدم، وقد تحدث إن فشلت كتابة SharedPreferences.
        // الملف الشخصي يُجلب من الخادم بدل ترك الحساب بلا اسم إلى الأبد
        // — فلا مخرج للمستخدم غير تسجيل خروج لا يعرف أنه يحتاجه.
        unawaited(_restoreUserFromServer(savedAccess));
      }
      notifyListeners();
      _startFcmSync(savedAccess);
      _signInToFirebase(savedAccess);
      // Fire-and-forget — don't block auto-login on the chats list fetch
      chatsProvider?.load(accessToken: savedAccess);

      if (notificationsProvider != null && _user != null) {
        // Fire-and-forget — don't block auto-login on notification fetch
        notificationsProvider.loadAndSync(_user!.id.toString(), savedAccess);
      }
    }
  }

  /// يجلب الملف الشخصي حين يُستعاد رمز بلا مستخدم محفوظ.
  Future<void> _restoreUserFromServer(String accessToken) async {
    try {
      final user = await _authService.fetchProfile(accessToken: accessToken);
      if (user == null) return;
      _user = user;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userKey, jsonEncode(user.toJson()));
      notifyListeners();
    } catch (e) {
      debugPrint('[Auth] Could not restore profile: $e');
    }
  }

  Future<bool> login({
    required String username,
    required String password,
    NotificationsProvider? notificationsProvider,
    ChatsProvider? chatsProvider,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _authService.login(
        identifier: username,
        password: password,
      );
      _user = result.user;
      _accessToken = result.accessToken;
      _refreshToken = result.refreshToken;

      await _secureStorage.write(key: _accessTokenKey, value: result.accessToken);
      await _secureStorage.write(key: _refreshTokenKey, value: result.refreshToken);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userKey, jsonEncode(result.user.toJson()));

      _isLoading = false;
      notifyListeners();

      _startFcmSync(result.accessToken);
      _signInToFirebase(result.accessToken);
      chatsProvider?.load(accessToken: result.accessToken);
      AppAnalytics.instance.setUserId(id: result.user.id.toString());
      AppAnalytics.login(method: 'password');

      if (notificationsProvider != null) {
        await notificationsProvider.loadAndSync(
          result.user.id.toString(),
          result.accessToken,
        );
      }

      return true;
    } catch (e) {
      _errorMessage = e is NoConnectionException
          ? e.toString()
          : 'فشل تسجيل الدخول، تحقّق من بياناتك';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String password,
    required String password2,
    ChatsProvider? chatsProvider,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _authService.register(
        firstName: firstName,
        lastName: lastName,
        email: email,
        phone: phone,
        password: password,
        password2: password2,
      );
      _user = result.user;
      _accessToken = result.accessToken;
      _refreshToken = result.refreshToken;

      await _secureStorage.write(key: _accessTokenKey, value: result.accessToken);
      await _secureStorage.write(key: _refreshTokenKey, value: result.refreshToken);
      // كان هذا السطر ناقصاً هنا وموجوداً في login(): الرمزان يُحفظان
      // في التخزين الآمن والمستخدم في SharedPreferences — مخزنان
      // منفصلان، فنسيان أحدهما يُنتج جلسة نصفها محفوظ. بعد إعادة فتح
      // التطبيق كان المسجّل حديثاً يُعتبر داخلاً (الرمز موجود) بلا اسم
      // ولا صورة (المستخدم مفقود).
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userKey, jsonEncode(result.user.toJson()));

      _isLoading = false;
      notifyListeners();

      _startFcmSync(result.accessToken);
      _signInToFirebase(result.accessToken);
      chatsProvider?.load(accessToken: result.accessToken);
      AppAnalytics.instance.setUserId(id: result.user.id.toString());
      AppAnalytics.signUp(method: 'password');

      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Updates the cached user (e.g. after a profile edit or verification
  /// succeeds) and persists it so it survives app restarts.
  Future<void> updateUser(User updated) async {
    _user = updated;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(updated.toJson()));
    notifyListeners();
  }

  Future<void> logout({NotificationsProvider? notificationsProvider}) async {
    // Persist and clear per-user notifications before losing the user ID
    if (notificationsProvider != null && _user != null) {
      await notificationsProvider.saveAndClear(_user!.id.toString());
    }

    // Stop listening for token rotations before clearing the access token
    _stopFcmSync();

    if (!kIsWeb && kFirestoreChatEnabled) {
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {
        // Non-critical
      }
    }

    if (!kIsWeb && _accessToken != null) {
      // Remove token from backend so this user stops receiving notifications.
      // We do NOT delete the Firebase token from the device — if another user
      // logs in next, getToken() will return the same device token immediately
      // instead of waiting for Firebase to re-register, which could return null.
      await _authService.removeFcmToken(accessToken: _accessToken!);
    }

    await _clearLocalSession();
  }

  /// Permanently deletes the current user's account server-side, then clears
  /// local session state exactly like [logout]. The backend refuses (and
  /// this returns its message instead of clearing anything) while a wallet
  /// balance or an open reservation/dispute still exists. Returns `null` on
  /// success.
  Future<String?> deleteAccount({
    NotificationsProvider? notificationsProvider,
  }) async {
    final token = _accessToken;
    if (token == null) return null;

    final result = await _authService.deleteAccount(accessToken: token);
    if (!result.success) {
      return result.message;
    }

    if (notificationsProvider != null && _user != null) {
      await notificationsProvider.saveAndClear(_user!.id.toString());
    }
    _stopFcmSync();
    // The account is already deactivated server-side at this point — there's
    // no backend session left to sign out of or remove an FCM token from.
    await _clearLocalSession();
    return null;
  }

  Future<void> _clearLocalSession() async {
    _user = null;
    _accessToken = null;
    _refreshToken = null;

    await _secureStorage.delete(key: _accessTokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    // Stop attributing subsequent (anonymous) events to this user.
    AppAnalytics.instance.setUserId(id: null);

    notifyListeners();
  }

  /// Syncs the current FCM token to the backend, then keeps it in sync
  /// automatically whenever Firebase rotates the token.
  void _startFcmSync(String accessToken) {
    if (kIsWeb) return;

    // Cancel any previous subscription (e.g. from a previous login session)
    _stopFcmSync();

    // Send the current token now (fire-and-forget)
    _pushFcmToken(accessToken);

    // Re-send automatically whenever Firebase issues a new token
    _tokenRefreshSub = NotificationService.onTokenRefresh.listen((newToken) {
      debugPrint('[FCM] Token rotated — syncing to backend');
      _authService.updateFcmToken(
        accessToken: accessToken,
        fcmToken: newToken,
      );
    });
  }

  void _stopFcmSync() {
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
  }

  /// Signs into Firebase Auth using a custom token minted by the Django
  /// backend for the current user, so the client can read/write Firestore
  /// directly (realtime chat) under Security Rules. Fire-and-forget: chat
  /// screens tolerate a not-yet-signed-in Firebase Auth state by waiting on
  /// FirebaseAuth.instance.authStateChanges().
  Future<void> _signInToFirebase(String accessToken) async {
    if (kIsWeb || !kFirestoreChatEnabled) return;

    try {
      final token = await _authService.getFirebaseToken(accessToken: accessToken);
      if (token == null) {
        debugPrint('[Firebase] Could not obtain custom token — Firestore chat will not work');
        return;
      }
      await FirebaseAuth.instance.signInWithCustomToken(token);
      debugPrint('[Firebase] Signed in to Firebase Auth');
    } catch (e) {
      debugPrint('[Firebase] Sign-in failed: $e');
    }
  }

  Future<void> _pushFcmToken(String accessToken) async {
    final fcmToken = await NotificationService.getToken();
    if (fcmToken != null) {
      await _authService.updateFcmToken(
        accessToken: accessToken,
        fcmToken: fcmToken,
      );
      debugPrint('[FCM] Token synced to backend');
    } else {
      debugPrint('[FCM] Could not obtain token — notifications will not work on this device');
    }
  }

  @override
  void dispose() {
    _stopFcmSync();
    super.dispose();
  }
}
