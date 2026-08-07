import 'package:flutter/material.dart';
import '../../models/reel.dart';
import '../../services/reel_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/formatters.dart';

/// Reel comments as a standalone modal bottom sheet (fetch-on-open, no
/// WebSocket) rather than the inline AnimatedList overlay LiveCommentsPanel
/// uses — that widget's design assumes a live, WebSocket-fed comment stream
/// pinned inside the broadcast overlay; reels are REST-only and comments are
/// opened on demand, which is the standard TikTok/Reels "tap to open a
/// sheet" interaction. Keeps the same spirit (simple list + input, delete
/// for own comment or the store owner) without ban support, which only
/// makes sense for a live moderator.
Future<void> showReelCommentsSheet(
  BuildContext context, {
  required Reel reel,
  required String accessToken,
  required int? currentUserId,
  required bool isStoreOwner,
  VoidCallback? onCommentPosted,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceContainerLowest,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _ReelCommentsSheet(
      reel: reel,
      accessToken: accessToken,
      currentUserId: currentUserId,
      isStoreOwner: isStoreOwner,
      onCommentPosted: onCommentPosted,
    ),
  );
}

class _ReelCommentsSheet extends StatefulWidget {
  final Reel reel;
  final String accessToken;
  final int? currentUserId;
  final bool isStoreOwner;
  final VoidCallback? onCommentPosted;

  const _ReelCommentsSheet({
    required this.reel,
    required this.accessToken,
    required this.currentUserId,
    required this.isStoreOwner,
    this.onCommentPosted,
  });

  @override
  State<_ReelCommentsSheet> createState() => _ReelCommentsSheetState();
}

class _ReelCommentsSheetState extends State<_ReelCommentsSheet> {
  final _service = ReelService();
  final _controller = TextEditingController();
  List<ReelComment> _comments = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final comments = await _service.fetchComments(
        accessToken: widget.accessToken,
        reelId: widget.reel.id,
      );
      if (!mounted) return;
      setState(() => _comments = comments);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;
    setState(() => _isSending = true);
    final result = await _service.postComment(
      accessToken: widget.accessToken,
      reelId: widget.reel.id,
      content: text,
    );
    if (!mounted) return;
    setState(() => _isSending = false);
    if (result.success) {
      _controller.clear();
      widget.onCommentPosted?.call();
      await _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  Future<void> _delete(ReelComment comment) async {
    final result = await _service.deleteComment(
      accessToken: widget.accessToken,
      reelId: widget.reel.id,
      commentId: comment.id,
    );
    if (!mounted) return;
    if (result.success) {
      setState(() => _comments.removeWhere((c) => c.id == comment.id));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('التعليقات (${widget.reel.commentsCount})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                const Divider(height: 1),
                Expanded(child: _buildList(scrollController)),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Row(
                      children: [
                        IconButton(
                          icon: _isSending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.send, color: AppColors.primary),
                          onPressed: _isSending ? null : _submit,
                        ),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            textAlign: TextAlign.right,
                            decoration: InputDecoration(
                              hintText: 'أضف تعليقاً...',
                              filled: true,
                              fillColor: AppColors.surfaceContainer,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onSubmitted: (_) => _submit(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildList(ScrollController scrollController) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _load, child: const Text('إعادة المحاولة')),
          ],
        ),
      );
    }
    if (_comments.isEmpty) {
      return const Center(
        child: Text('لا توجد تعليقات بعد — كن أول من يعلّق',
            style: TextStyle(color: AppColors.onSurfaceVariant)),
      );
    }
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _comments.length,
      itemBuilder: (context, index) {
        final comment = _comments[index];
        final canDelete = widget.isStoreOwner || comment.userId == widget.currentUserId;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.primaryContainer,
                child: Text(
                  comment.username.isNotEmpty ? comment.username.characters.first.toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(comment.username,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(width: 6),
                        Text(relativeTimeAr(comment.createdAt),
                            style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(comment.content, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              if (canDelete)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.onSurfaceVariant),
                  onPressed: () => _delete(comment),
                ),
            ],
          ),
        );
      },
    );
  }
}
