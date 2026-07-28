import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_notification.dart';
import '../services/notification_api_service.dart';

export '../models/app_notification.dart';

class NotificationsProvider extends ChangeNotifier {
  final List<AppNotification> _notifications = [];
  final NotificationApiService _apiService = NotificationApiService();

  String? _currentUserId;
  String? _currentToken;
  bool _isLoading = false;

  List<AppNotification> get notifications {
    final sorted = List<AppNotification>.from(_notifications)
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return List.unmodifiable(sorted);
  }

  int get unreadCount => _notifications.where((n) => !n.isRead).length;
  bool get isLoading => _isLoading;

  /// Called after login or auto-login to load this user's notifications.
  Future<void> loadAndSync(String userId, String token) async {
    _currentUserId = userId;
    _currentToken = token;

    // Show cached data immediately for instant display
    await _loadFromCache(userId);

    _isLoading = true;
    notifyListeners();
    try {
      final backendList = await _apiService.fetchAll(token);
      final backendIds = backendList.map((n) => n.id).toSet();
      // Preserve local FCM notifications not yet reflected in backend
      final localOnly = _notifications
          .where((n) => n.id.startsWith('local_') && !backendIds.contains(n.id))
          .toList();
      _notifications
        ..clear()
        ..addAll(backendList)
        ..addAll(localOnly);
      await _saveToCache(userId);
    } catch (_) {}
    _isLoading = false;
    notifyListeners();
  }

  /// Called before logout: persists the current list then clears the provider.
  Future<void> saveAndClear(String userId) async {
    await _saveToCache(userId);
    _notifications.clear();
    _currentUserId = null;
    _currentToken = null;
    notifyListeners();
  }

  Future<void> _loadFromCache(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('notifications_$userId');
    if (raw != null) {
      final List list = jsonDecode(raw) as List;
      _notifications.clear();
      _notifications.addAll(
        list.map((e) => AppNotification.fromCacheJson(e as Map<String, dynamic>)),
      );
      notifyListeners();
    }
  }

  Future<void> _saveToCache(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'notifications_$userId',
      jsonEncode(_notifications.map((n) => n.toJson()).toList()),
    );
  }

  void addNotification({
    required String title,
    required String body,
    String type = 'general',
    Map<String, dynamic> data = const {},
  }) {
    _notifications.add(AppNotification(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      body: body,
      type: type,
      receivedAt: DateTime.now(),
      data: data,
    ));
    notifyListeners();
    if (_currentUserId != null) _saveToCache(_currentUserId!);
  }

  Future<void> markAllRead() async {
    for (final n in _notifications) {
      n.isRead = true;
    }
    notifyListeners();
    if (_currentToken != null) {
      await _apiService.markAllRead(_currentToken!);
      if (_currentUserId != null) await _saveToCache(_currentUserId!);
    }
  }

  Future<void> markRead(String id) async {
    final n = _notifications.where((n) => n.id == id).firstOrNull;
    if (n != null && !n.isRead) {
      n.isRead = true;
      notifyListeners();
      if (_currentToken != null) {
        await _apiService.markRead(_currentToken!, id);
        if (_currentUserId != null) await _saveToCache(_currentUserId!);
      }
    }
  }

  /// Removes a single notification — swipe-to-dismiss on the notifications
  /// screen. 'local_' ids are FCM-only entries never persisted server-side
  /// (see addNotification), so there's nothing to delete on the backend.
  Future<void> deleteNotification(String id) async {
    _notifications.removeWhere((n) => n.id == id);
    notifyListeners();
    if (_currentUserId != null) await _saveToCache(_currentUserId!);
    if (_currentToken != null && !id.startsWith('local_')) {
      await _apiService.delete(_currentToken!, id);
    }
  }

  /// Clears every notification for the current user, on the server too.
  Future<void> deleteAll() async {
    _notifications.clear();
    notifyListeners();
    if (_currentUserId != null) await _saveToCache(_currentUserId!);
    if (_currentToken != null) {
      await _apiService.clearAll(_currentToken!);
    }
  }

  void clearAll() {
    _notifications.clear();
    _currentUserId = null;
    _currentToken = null;
    notifyListeners();
  }
}
