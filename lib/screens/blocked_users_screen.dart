import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import '../theme/app_colors.dart';

/// من حظرتُهم، وزرّ إلغاء الحظر لكل واحد.
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  final _service = ChatService();
  late Future<List<({int? chatId, String name})>> _blocked =
      _service.fetchBlocked();

  Future<void> _unblock(int chatId) async {
    final result = await _service.setBlocked(chatId, false);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.message)));
    setState(() {
      _blocked = _service.fetchBlocked();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('المحظورون')),
        body: FutureBuilder(
          future: _blocked,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final people = snapshot.data;
            if (people == null) {
              return Center(
                child: TextButton(
                  onPressed: () => setState(() {
                    _blocked = _service.fetchBlocked();
                  }),
                  child: const Text('تعذّر التحميل — إعادة المحاولة'),
                ),
              );
            }
            if (people.isEmpty) {
              return const Center(
                child: Text(
                  'لم تحظر أحداً',
                  style: TextStyle(color: AppColors.onSurfaceVariant),
                ),
              );
            }
            return ListView(
              children: [
                for (final p in people)
                  ListTile(
                    leading: const Icon(Icons.person_off_outlined),
                    title: Text(p.name),
                    trailing: p.chatId == null
                        ? null
                        : TextButton(
                            onPressed: () => _unblock(p.chatId!),
                            child: const Text('إلغاء الحظر'),
                          ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
