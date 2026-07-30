import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/live_session_viewer.dart';
import '../../services/live_session_service.dart';
import '../../theme/app_colors.dart';

/// Store-owner-only sheet opened by tapping the live viewer-count chip —
/// searchable, paginated list of everyone who has watched this session,
/// with per-viewer ban/unban and promote/demote-to-moderator actions.
/// Ban/moderator status is scoped to this session only (see backend
/// LiveSessionBan/LiveSessionModerator docstrings) — it never carries over
/// to the store's other broadcasts.
Future<void> showLiveViewersSheet(
  BuildContext context, {
  required int sessionId,
  required String accessToken,
  required int? currentUserId,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => LiveViewersSheet(
      sessionId: sessionId,
      accessToken: accessToken,
      currentUserId: currentUserId,
    ),
  );
}

class LiveViewersSheet extends StatefulWidget {
  final int sessionId;
  final String accessToken;
  final int? currentUserId;

  const LiveViewersSheet({
    super.key,
    required this.sessionId,
    required this.accessToken,
    required this.currentUserId,
  });

  @override
  State<LiveViewersSheet> createState() => _LiveViewersSheetState();
}

class _LiveViewersSheetState extends State<LiveViewersSheet> {
  final _service = LiveSessionService();
  final _searchController = TextEditingController();
  Timer? _debounce;

  final List<LiveSessionViewer> _viewers = [];
  int _page = 1;
  bool _hasMore = true;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;
  final Set<int> _busyUserIds = {};

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _load(reset: true));
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _error = null;
        _page = 1;
        _hasMore = true;
        _viewers.clear();
      });
    } else {
      setState(() => _isLoadingMore = true);
    }

    try {
      final result = await _service.fetchViewers(
        accessToken: widget.accessToken,
        sessionId: widget.sessionId,
        search: _searchController.text.trim(),
        page: _page,
      );
      if (!mounted) return;
      setState(() {
        _viewers.addAll(result.viewers);
        _hasMore = result.hasMore;
        _page++;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'فشل تحميل قائمة المشاهدين';
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _toggleModerator(LiveSessionViewer viewer) async {
    setState(() => _busyUserIds.add(viewer.userId));
    final result = viewer.isModerator
        ? await _service.removeModerator(
            accessToken: widget.accessToken, sessionId: widget.sessionId, userId: viewer.userId)
        : await _service.addModerator(
            accessToken: widget.accessToken, sessionId: widget.sessionId, userId: viewer.userId);
    if (!mounted) return;
    setState(() => _busyUserIds.remove(viewer.userId));
    if (result.success) {
      _updateViewer(viewer.userId, (v) => v.copyWith(isModerator: !viewer.isModerator));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  Future<void> _toggleBan(LiveSessionViewer viewer) async {
    if (viewer.isBanned) {
      setState(() => _busyUserIds.add(viewer.userId));
      final result = await _service.unbanViewer(
          accessToken: widget.accessToken, sessionId: widget.sessionId, userId: viewer.userId);
      if (!mounted) return;
      setState(() => _busyUserIds.remove(viewer.userId));
      if (result.success) {
        _updateViewer(viewer.userId, (v) => v.copyWith(isBanned: false));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حظر المستخدم؟'),
        content: Text('لن يستطيع ${viewer.username} التعليق أو مشاهدة هذا البث بعد الآن.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('تراجع')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حظر', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busyUserIds.add(viewer.userId));
    final result = await _service.banViewer(
        accessToken: widget.accessToken, sessionId: widget.sessionId, userId: viewer.userId);
    if (!mounted) return;
    setState(() => _busyUserIds.remove(viewer.userId));
    if (result.success) {
      _updateViewer(viewer.userId, (v) => v.copyWith(isBanned: true));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  void _updateViewer(int userId, LiveSessionViewer Function(LiveSessionViewer) update) {
    final index = _viewers.indexWhere((v) => v.userId == userId);
    if (index == -1) return;
    setState(() => _viewers[index] = update(_viewers[index]));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    const Text('المشاهدون',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  textAlign: TextAlign.right,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'ابحث عن مشاهد...',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (!_isLoading &&
                        !_isLoadingMore &&
                        _hasMore &&
                        notification.metrics.pixels >=
                            notification.metrics.maxScrollExtent - 200) {
                      _load();
                    }
                    return false;
                  },
                  child: _buildList(scrollController),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildList(ScrollController controller) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_viewers.isEmpty) {
      return const Center(child: Text('لا يوجد مشاهدون بعد'));
    }
    return ListView.separated(
      controller: controller,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: _viewers.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index >= _viewers.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return _buildViewerTile(_viewers[index]);
      },
    );
  }

  Widget _buildViewerTile(LiveSessionViewer viewer) {
    final isSelf = viewer.userId == widget.currentUserId;
    final busy = _busyUserIds.contains(viewer.userId);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: (viewer.isWatching ? AppColors.success : Colors.grey)
            .withValues(alpha: 0.15),
        child: Icon(Icons.person, color: viewer.isWatching ? AppColors.success : Colors.grey),
      ),
      title: Text(viewer.username, textAlign: TextAlign.right),
      subtitle: Wrap(
        alignment: WrapAlignment.end,
        spacing: 6,
        children: [
          if (isSelf) const _Badge(label: 'أنت', color: AppColors.primary),
          if (viewer.isModerator) const _Badge(label: 'أدمن', color: AppColors.gold),
          if (viewer.isBanned) const _Badge(label: 'محظور', color: AppColors.error),
          if (!viewer.isWatching) const _Badge(label: 'غادر', color: Colors.grey),
        ],
      ),
      trailing: isSelf
          ? null
          : busy
              ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: viewer.isModerator ? 'إزالة الإشراف' : 'رفع كأدمن',
                      icon: Icon(
                        viewer.isModerator ? Icons.remove_moderator : Icons.add_moderator,
                        color: viewer.isModerator ? AppColors.gold : AppColors.onSurfaceVariant,
                      ),
                      onPressed: viewer.isBanned ? null : () => _toggleModerator(viewer),
                    ),
                    IconButton(
                      tooltip: viewer.isBanned ? 'إلغاء الحظر' : 'حظر',
                      icon: Icon(
                        viewer.isBanned ? Icons.lock_open : Icons.block,
                        color: AppColors.error,
                      ),
                      onPressed: () => _toggleBan(viewer),
                    ),
                  ],
                ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
    );
  }
}
