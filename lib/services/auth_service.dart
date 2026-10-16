import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import '../config/api_config.dart';
import '../models/user.dart';
import 'api_client.dart';

class AuthService {
  final _client = ApiClient.instance;

  /// [identifier] رقم هاتف في الواجهة الجديدة، لكن LoginView يقبل أيضاً
  /// اسم مستخدم أو بريداً — فالحسابات القديمة تبقى قادرة على الدخول.
  Future<({User user, String accessToken, String refreshToken})> login({
    required String identifier,
    required String password,
  }) async {
    final response = await _client.post(
      '/auth/login/',
      body: {'username': identifier, 'password': password},
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

  /// التسجيل بلا اسم مستخدم: الخادم يولّده من الرقم. الاسم الأول
  /// والأخير يُعرّفان صاحب الحساب، والرقم يُدخله إليه.
  Future<({User user, String accessToken, String refreshToken})> register({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String password,
    required String password2,
  }) async {
    final response = await _client.post(
      '/auth/register/',
      body: {
        'first_name': firstName,
        'last_name': lastName,
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

  /// Multipart (not the shared ApiClient's JSON PATCH) since avatar upload
  /// needs a file field — same reasoning as StoreService.updateStore
  /// (see StoreService's note on bypassing ApiClient directly). Text fields
  /// go through fine as regular multipart fields either way.
  Future<({bool success, String message, User? user})> updateProfile({
    required String accessToken,
    String? username,
    String? firstName,
    String? lastName,
    String? email,
    String? phone,
    String? bio,
    DateTime? dateOfBirth,
    XFile? avatar,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/auth/profile/update/');
    final request = http.MultipartRequest('PATCH', uri);
    request.headers['Authorization'] = 'Bearer $accessToken';

    if (username != null) request.fields['username'] = username;
    if (firstName != null) request.fields['first_name'] = firstName;
    if (lastName != null) request.fields['last_name'] = lastName;
    if (email != null) request.fields['email'] = email;
    if (phone != null) request.fields['phone'] = phone;
    if (bio != null) request.fields['bio'] = bio;
    if (dateOfBirth != null) {
      request.fields['date_of_birth'] =
          dateOfBirth.toIso8601String().split('T').first;
    }
    if (avatar != null) {
      final bytes = await avatar.readAsBytes();
      request.files.add(
        http.MultipartFile.fromBytes(
          'avatar',
          bytes,
          filename: avatar.name,
          contentType: MediaType('image', 'jpeg'),
        ),
      );
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

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

  /// Marks the phone verified from a Firebase ID token carrying a verified
  /// `phone_number` claim — see [FirebasePhoneAuth]. The SMS itself is sent
  /// by Firebase from the device; the server's only job is to check the token
  /// and confirm its phone matches this account's.
  Future<({bool success, String message})> verifyPhoneWithFirebase({
    required String accessToken,
    required String idToken,
  }) async {
    final response = await _client.post(
      '/auth/verify-phone/',
      body: {'id_token': idToken},
    );
    if (response.statusCode == 200) {
      return (success: true, message: 'تم تفعيل رقم هاتفك');
    }
    return (success: false, message: _extractError(response, 'تعذّر تفعيل الرقم'));
  }

  /// Legacy server-generated SMS code (Twilio). Superseded by
  /// [verifyPhoneWithFirebase] and no longer called from the app — kept
  /// because the endpoint still accepts it, so an older build in the wild
  /// keeps working.
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
  /// الملف الشخصي للمستخدم الحالي.
  ///
  /// يُستعمل حين تُستعاد جلسة برمز بلا مستخدم محفوظ — فالخادم هو المصدر
  /// الوحيد الباقي للاسم والصورة. يُرجع null بدل أن يرمي: هذا استرجاع
  /// في الخلفية لا فعل طلبه المستخدم، وفشله لا يستحق شاشة خطأ.
  Future<User?> fetchProfile({required String accessToken}) async {
    final response = await _client.get('/auth/profile/');
    if (response.statusCode != 200) return null;
    return User.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Resets a password with proof of holding the account's phone.
  ///
  /// The only route open to the many accounts that have no email. There is
  /// no code to send or compare here: Firebase Phone Auth delivers the SMS
  /// from the device and [phoneIdToken] is the proof it was received.
  ///
  /// The server answers the same way whether the number has an account or
  /// not, so a success here does not confirm that one exists — it only
  /// says the request was well formed.
  Future<({bool success, String message})> resetPasswordByPhone({
    required String phoneIdToken,
    required String newPassword,
  }) async {
    final response = await _client.post(
      '/auth/reset-password-phone/',
      body: {'id_token': phoneIdToken, 'new_password': newPassword},
      auth: false,
    );
    if (response.statusCode == 200) {
      return (
        success: true,
        message: _tryMessage(response) ?? 'تم تغيير كلمة المرور',
      );
    }
    return (
      success: false,
      message: _extractError(response, 'تعذّر تغيير كلمة المرور'),
    );
  }

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
