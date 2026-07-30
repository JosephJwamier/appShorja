import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/chat.dart';
import '../providers/auth_provider.dart';
import '../providers/chats_provider.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import '../utils/refreshable_tab.dart';
import 'store_chat_screen.dart';

/// Conversations inbox (المحادثات) — list of all the user's chats
/// (store-level and item-level), replacing the old Notifications tab.
///
/// [archived] switches this same screen into "الأرشيف" mode: a separate
/// [ChatsProvider] instance (see [_openArchive]) loads `?archived=true`
/// instead, and swiping a tile unarchives it instead of archiving it.
class ChatsListScreen extends StatefulWidget {
  final bool archived;

  const ChatsListScreen({super.key, this.archived = false});

  @override
  State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen>
    implements RefreshableTab {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // العرض الرئيسي محمّل مسبقاً منذ تسجيل الدخول (AuthProvider.login) —
    // أما الأرشيف فهو مزوّد جديد فارغ يحتاج تحميلاً أولياً هنا.
    if (widget.archived) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final threshold = _scrollController.position.maxScrollExtent - 200;
    if (_scrollController.position.pixels >= threshold) {
      context.read<ChatsProvider>().loadMore();
    }
  }

  @override
  Future<void> refreshTab() => _refresh();

  Future<void> _refresh() async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;
    await context
        .read<ChatsProvider>()
        .load(accessToken: token, archived: widget.archived);
  }

  Future<void> _openChat(ChatSummary chat) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoreChatScreen(
          chatId: chat.id,
          title: chat.displayTitle,
          avatarUrl: chat.displayAvatarUrl,
          isSupportChat: chat.isSupport,
        ),
      ),
    );
    if (mounted) _refresh();
  }

  void _openArchive() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => ChatsProvider(),
          child: const ChatsListScreen(archived: true),
        ),
      ),
    );
  }

  /// Used as [Dismissible.confirmDismiss] rather than `onDismissed` — the
  /// archive/unarchive call is a real network request that can fail, and
  /// returning false here makes the tile snap back instead of vanishing
  /// while the chat is still sitting in the provider's list.
  Future<bool> _toggleArchived(ChatSummary chat) async {
    final messenger = ScaffoldMessenger.of(context);
    final success = await context
        .read<ChatsProvider>()
        .setArchived(chat.id, !widget.archived);
    if (!success && mounted) {
      messenger.showSnackBar(SnackBar(
        content: Text(widget.archived ? 'تعذّر إلغاء الأرشفة' : 'تعذّرت الأرشفة'),
        backgroundColor: AppColors.error,
      ));
    }
    return success;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Consumer<ChatsProvider>(
        builder: (context, provider, _) {
          return Scaffold(
            appBar: AppBar(
              title: Text(widget.archived ? 'الأرشيف' : 'المحادثات'),
              actions: widget.archived
                  ? null
                  : [
                      IconButton(
                        icon: const Icon(Icons.archive_outlined),
                        tooltip: 'الأرشيف',
                        onPressed: _openArchive,
                      ),
                    ],
            ),
            body: provider.isLoading && provider.chats.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _refresh,
                    child: provider.chats.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              const SizedBox(height: 120),
                              Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                        widget.archived
                                            ? Icons.archive_outlined
                                            : Icons.chat_bubble_outline,
                                        size: 64,
                                        color: AppColors.onSurfaceVariant),
                                    const SizedBox(height: 12),
                                    Text(
                                        widget.archived
                                            ? 'لا توجد محادثات مؤرشفة'
                                            : 'لا توجد محادثات بعد',
                                        style: const TextStyle(
                                            color:
                                                AppColors.onSurfaceVariant)),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            controller: _scrollController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(12),
                            itemCount: provider.chats.length +
                                (provider.hasMore ? 1 : 0),
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 4),
                            itemBuilder: (context, index) {
                              if (index >= provider.chats.length) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Center(
                                    child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  ),
                                );
                              }
                              final chat = provider.chats[index];
                              return Dismissible(
                                key: ValueKey('chat-${chat.id}'),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.only(left: 20),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    widget.archived
                                        ? Icons.unarchive_outlined
                                        : Icons.archive_outlined,
                                    color: AppColors.primary,
                                  ),
                                ),
                                confirmDismiss: (_) => _toggleArchived(chat),
                                child: _ChatTile(
                                  chat: chat,
                                  timeAgoText: chat.lastMessageAt != null
                                      ? relativeTimeAr(chat.lastMessageAt!)
                                      : '',
                                  onTap: () => _openChat(chat),
                                ),
                              );
                            },
                          ),
                  ),
          );
        },
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  final ChatSummary chat;
  final String timeAgoText;
  final VoidCallback onTap;

  const _ChatTile({
    required this.chat,
    required this.timeAgoText,
    required this.onTap,
  });

  /// A small icon distinguishing "who"/"what kind" of conversation this is
  /// at a glance — item-based chats don't get one here since their item
  /// context is already spelled out in [_itemContextLine].
  IconData? get _kindIcon {
    if (chat.isSupport) return Icons.support_agent;
    if (chat.storeId != null) return Icons.storefront;
    return null;
  }

  Widget? _itemContextLine() {
    if (chat.itemTitle == null) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              chat.itemTitle!,
              style: const TextStyle(
                color: AppColors.onSurfaceVariant,
                fontSize: 11.5,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.shopping_bag_outlined,
              size: 12, color: AppColors.onSurfaceVariant),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unread = chat.unreadCount > 0;
    final kindIcon = _kindIcon;
    final itemContext = _itemContextLine();
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.surfaceContainer),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.surfaceContainer,
              backgroundImage: chat.displayAvatarUrl != null
                  ? NetworkImage(chat.displayAvatarUrl!)
                  : null,
              child: chat.displayAvatarUrl == null
                  ? (chat.isSupport
                      ? const Icon(Icons.support_agent,
                          color: AppColors.primary)
                      : Text(
                          chat.displayTitle.isNotEmpty
                              ? chat.displayTitle[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold),
                        ))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          chat.displayTitle,
                          style: TextStyle(
                            fontWeight:
                                unread ? FontWeight.bold : FontWeight.w600,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                        ),
                      ),
                      if (kindIcon != null) ...[
                        const SizedBox(width: 4),
                        Icon(kindIcon, size: 14, color: AppColors.primary),
                      ],
                    ],
                  ),
                  ?itemContext,
                  const SizedBox(height: 2),
                  Text(
                    chat.lastMessageType == 'image'
                        ? '📷 صورة'
                        : (chat.lastMessageContent ?? 'ابدأ المحادثة'),
                    style: TextStyle(
                      color: unread
                          ? AppColors.onSurface
                          : AppColors.onSurfaceVariant,
                      fontWeight: unread ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  timeAgoText,
                  style: const TextStyle(
                      color: AppColors.onSurfaceVariant, fontSize: 11),
                ),
                const SizedBox(height: 6),
                if (unread)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                    ),
                    child: Text(
                      '${chat.unreadCount}',
                      style: const TextStyle(
                          color: AppColors.onPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
