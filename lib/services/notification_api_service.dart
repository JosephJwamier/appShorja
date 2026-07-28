import 'dart:convert';
import '../models/app_notification.dart';
import 'api_client.dart';

class NotificationApiService {
  final _client = ApiClient.instance;

  // token is kept for call-site compatibility — ApiClient tracks the live
  // token itself (and silently refreshes it on a 401).
  Future<List<AppNotification>> fetchAll(String token) async {
    try {
      final response = await _client.get('/notifications/');
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        // Handle both paginated { results: [...] } and plain list responses
        final List items = decoded is Map ? decoded['results'] as List : decoded as List;
        return items
            .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> markRead(String token, String id) async {
    try {
      await _client.post('/notifications/$id/mark_read/', body: {'is_read': true});
    } catch (_) {}
  }

  Future<void> markAllRead(String token) async {
    try {
      await _client.post('/notifications/mark_all_read/', body: {'is_read': true});
    } catch (_) {}
  }

  Future<void> delete(String token, String id) async {
    try {
      await _client.delete('/notifications/$id/');
    } catch (_) {}
  }

  Future<void> clearAll(String token) async {
    try {
      await _client.delete('/notifications/clear-all/');
    } catch (_) {}
  }
}
