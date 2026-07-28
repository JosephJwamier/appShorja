import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user.dart';
import 'api_client.dart';

class AuthService {
  final _client = ApiClient.instance;

  Future<({User user, String accessToken, String refreshToken})> login({
    required String username,
    required String password,
  }) async {
    final response = await _client.post(
      '/auth/login/',
      body: {'username': username, 'password': password},
      auth: false,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (
        user: User.fromJson(data['user']),
        accessToken: data['tokens']['access'] as String,
        refreshToken: data['tokens']['refresh'] as String,
      );
    } else {
      throw Exception('فشل تسجيل الدخول');
    }
  }

  Future<({User user, String accessToken, String refreshToken})> register({
    required String username,
    required String email,
    required String phone,
    required String password,
    required String password2,
  }) async {
    final response = await _client.post(
      '/auth/register/',
      body: {
        'username': username,
        'email': email,
        'phone': phone,
        'password': password,
        'password2': password2,
      },
      auth: false,
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (
        user: User.fromJson(data['user']),
        accessToken: data['tokens']['access'] as String,
        refreshToken: data['tokens']['refresh'] as String,
      );
    } else {
      try {
        final errorData = jsonDecode(response.body) as Map<String, dynamic>;
        final firstField = errorData.entries.first;
        final firstError = (firstField.value as List).first;
        throw Exception(firstError.toString());
      } catch (_) {
        throw Exception('فشل إنشاء الحساب');
      }
    }
  }

  /// Signs in (or registers) via Google/Facebook. [idToken] is the Firebase
  /// Auth ID token obtained after signing in with the native Google/Facebook
  /// credential — the backend verifies it with firebase_admin.
  Future<({User user, String accessToken, String refreshToken})> socialLogin({
    required String idToken,
  }) async {
    final response = await _client.post(
      '/auth/social-login/',
      body: {'id_token': idToken},
      auth: false,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (
        user: User.fromJson(data['user']),
        accessToken: data['tokens']['access'] as String,
        refreshToken: data['tokens']['refresh'] as String,
      );
    }
    throw Exception(_extractError(response, 'فشل تسجيل الدخول'));
  }

  /// Parses a Django error body into a single readable message, checking the
  /// common shapes this backend uses (`error`, `message`, or field-level
  /// validation errors).
  String _extractError(http.Response response, String fallback) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) {
        if (body['error'] != null) return body['error'].toString();
        if (body['message'] != null) return body['message'].toString();
        final firstField = body.entries.first;
        final value = firstField.value;
        final firstError = value is List ? value.first : value;
        return firstError.toString();
      }
    } catch (_) {
      // fall through
    }
    return fallback;
  }

  // accessToken is kept on every method below for call-site compatibility —
  // ApiClient tracks the live token itself (and silently refreshes it on a
  // 401), so it's no longer read directly here.

  Future<({bool success, String message, User? user})> updateProfile({
    required String accessToken,
    String? username,
    String? email,
    String? phone,
  }) async {
    final response = await _client.patch(
      '/auth/profile/update/',
      body: {
        'username': ?username,
        'email': ?email,
        'phone': ?phone,
      },
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (success: true, message: 'تم تحديث البيانات', user: User.fromJson(data));
    }
    return (
      success: false,
      message: _extractError(response, 'تعذّر تحديث البيانات'),
      user: null,
    );
  }

  Future<({bool success, String message})> changePassword({
    required String accessToken,
    required String oldPassword,
    required String newPassword,
    required String newPassword2,
  }) async {
    final response = await _client.post(
      '/auth/change-password/',
      body: {
        'old_password': oldPassword,
        'new_password': newPassword,
        'new_password2': newPassword2,
      },
    );
    if (response.statusCode == 200) {
      return (success: true, message: 'تم تغيير كلمة المرور بنجاح');
    }
    return (success: false, message: _extractError(response, 'تعذّر تغيير كلمة المرور'));
  }

  /// Sends a fresh 6-digit email verification code.
  Future<({bool success, String message})> sendEmailVerificationCode({
    required String accessToken,
  }) async {
    final response = await _client.post('/auth/resend-verification/');
    if (response.statusCode == 200) {
      return (success: true, message: 'تم إرسال رمز التحقق إلى بريدك');
    }
    return (success: false, message: _extractError(response, 'تعذّر إرسال رمز التحقق'));
  }

  Future<({bool success, String message})> verifyEmailCode({
    required String accessToken,
    required String code,
  }) async {
    final response = await _client.post(
      '/auth/verify-email/',
      body: {'code': code},
    );
    if (response.statusCode == 200) {
      return (success: true, message: 'تم تفعيل بريدك الإلكتروني');
    }
    return (success: false, message: _extractError(response, 'رمز غير صحيح'));
  }

  /// Sends a fresh 6-digit SMS verification code to the user's phone.
  Future<({bool success, String message})> sendPhoneVerificationCode({
    required String accessToken,
  }) async {
    final response = await _client.get('/auth/verify-phone/');
    if (response.statusCode == 200) {
      return (success: true, message: 'تم إرسال رمز التحقق برسالة نصية');
    }
    return (success: false, message: _extractError(response, 'تعذّر إرسال رمز التحقق'));
  }

  Future<({bool success, String message})> verifyPhoneCode({
    required String accessToken,
    required String code,
  }) async {
    final response = await _client.post(
      '/auth/verify-phone/',
      body: {'code': code},
    );
    if (response.statusCode == 200) {
      return (success: true, message: 'تم تفعيل رقم هاتفك');
    }
    return (success: false, message: _extractError(response, 'رمز غير صحيح'));
  }

  /// Requests a password-reset code by email (no auth — used from the
  /// login screen). Always reports success to avoid revealing whether the
  /// email is registered.
  Future<({bool success, String message})> requestPasswordResetCode({
    required String email,
  }) async {
    final response = await _client.post(
      '/auth/reset-password/',
      body: {'email': email},
      auth: false,
    );
    final message = response.statusCode == 200
        ? _tryMessage(response) ?? 'إذا كان البريد مسجّلاً ستصلك رسالة برمز التحقق'
        : 'إذا كان البريد مسجّلاً ستصلك رسالة برمز التحقق';
    return (success: true, message: message);
  }

  Future<({bool success, String message})> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
    required String newPassword2,
  }) async {
    final response = await _client.post(
      '/auth/reset-password-confirm/',
      body: {
        'email': email,
        'code': code,
        'new_password': newPassword,
        'new_password2': newPassword2,
      },
      auth: false,
    );
    if (response.statusCode == 200) {
      return (success: true, message: 'تم تغيير كلمة المرور — يمكنك تسجيل الدخول الآن');
    }
    return (success: false, message: _extractError(response, 'رمز غير صحيح أو منتهي'));
  }

  String? _tryMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['message'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Send FCM token to Django backend so server can push notifications to this device
  Future<void> updateFcmToken({
    required String accessToken,
    required String fcmToken,
  }) async {
    try {
      await _client.post('/users/update-fcm-token/', body: {'fcm_token': fcmToken});
    } catch (_) {
      // Non-critical — silently ignore failures
    }
  }

  /// Remove FCM token from backend on logout
  Future<void> removeFcmToken({required String accessToken}) async {
    try {
      await _client.post('/users/remove-fcm-token/');
    } catch (_) {
      // Non-critical
    }
  }

  /// Saves the categories picked on the (skippable) onboarding screen.
  /// Passing an empty list just clears them — this call is best-effort and
  /// never blocks the user from entering the app.
  Future<void> saveInterests({
    required String accessToken,
    required List<int> categoryIds,
  }) async {
    try {
      await _client.post(
        '/users/interests/',
        body: {'category_ids': categoryIds},
      );
    } catch (_) {
      // Non-critical — onboarding must never get stuck on a network error
    }
  }

  /// Permanently deletes (deactivates) the current user's account. The
  /// backend refuses with an explanatory message while a wallet balance or
  /// an open reservation/dispute still exists.
  Future<({bool success, String message})> deleteAccount({
    required String accessToken,
  }) async {
    final response = await _client.post('/users/delete-account/');
    if (response.statusCode == 200) {
      return (success: true, message: 'تم حذف الحساب بنجاح');
    }
    return (success: false, message: _extractError(response, 'تعذّر حذف الحساب'));
  }

  /// Mint a Firebase Auth custom token for the current Django user, so the
  /// client can sign in to Firebase Auth with the same identity and talk to
  /// Firestore directly (realtime chat).
  Future<String?> getFirebaseToken({required String accessToken}) async {
    try {
      final response = await _client.post('/auth/firebase-token/');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['firebase_token'] as String?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
