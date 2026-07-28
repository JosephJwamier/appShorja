import 'package:flutter/material.dart';
import '../../models/live_comment.dart';

/// Presentational live-comments overlay (list + input) shared by the
/// broadcast and viewer screens. All state (the comment list, WebSocket
/// connection, sending) is owned by the parent screen — this widget is
/// purely controlled, matching this app's existing pattern of keeping
/// real-time state local to the screen rather than in a Provider.
///
/// New comments slide/fade in at the bottom and push older ones up; a top
/// gradient mask fades comments out as they near the top edge, and the
/// buffer is capped so very long streams don't keep every comment mounted
/// (TikTok-style live comment feed).
class LiveCommentsPanel extends StatefulWidget {
  final List<LiveComment> comments;
  final int? currentUserId;
  final bool isModerator;
  final ValueChanged<String> onSend;
  final ValueChanged<LiveComment>? onDelete;
  final bool canComment;

  const LiveCommentsPanel({
    super.key,
    required this.comments,
    required this.currentUserId,
    this.isModerator = false,
    required this.onSend,
    this.onDelete,
    this.canComment = true,
  });

  @override
  State<LiveCommentsPanel> createState() => _LiveCommentsPanelState();
}

class _LiveCommentsPanelState extends State<LiveCommentsPanel> {
  static const _maxVisible = 50;
  static const _transitionDuration = Duration(milliseconds: 320);

  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _listKey = GlobalKey<AnimatedListState>();
  late final List<LiveComment> _displayed;

  @override
  void initState() {
    super.initState();
    _displayed = widget.comments.length > _maxVisible
        ? widget.comments.sublist(widget.comments.length - _maxVisible)
        : List.of(widget.comments);
  }

  @override
  void didUpdateWidget(covariant LiveCommentsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newIds = widget.comments.map((c) => c.id).toSet();
    final displayedIds = _displayed.map((c) => c.id).toSet();

    // Comments removed upstream (moderator delete / comment_deleted event).
    for (final id in displayedIds.difference(newIds)) {
      final index = _displayed.indexWhere((c) => c.id == id);
      if (index == -1) continue;
      final removed = _displayed.removeAt(index);
      _listKey.currentState?.removeItem(
        index,
        (context, animation) => _buildItem(removed, animation),
        duration: _transitionDuration,
      );
    }

    // New comments, in source order. A large batch (initial history load)
    // is inserted instantly; single real-time arrivals get the slide/fade.
    final added =
        widget.comments.where((c) => !displayedIds.contains(c.id)).toList();
    final isBulkLoad = added.length > 3;
    for (final comment in added) {
      _displayed.add(comment);
      _listKey.currentState?.insertItem(
        _displayed.length - 1,
        duration: isBulkLoad ? Duration.zero : _transitionDuration,
      );
    }

    // Cap the buffer so long-running streams don't accumulate forever —
    // the oldest visible comment fades out at the top as it's dropped.
    while (_displayed.length > _maxVisible) {
      _displayed.removeAt(0);
      _listKey.currentState?.removeItem(
        0,
        (context, animation) => const SizedBox.shrink(),
        duration: Duration.zero,
      );
    }

    if (added.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }

  Widget _buildItem(LiveComment comment, Animation<double> animation) {
    final canDelete = widget.onDelete != null &&
        (widget.isModerator || comment.userId == widget.currentUserId);
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
    return SizeTransition(
      sizeFactor: curved,
      child: FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.4),
            end: Offset.zero,
          ).animate(curved),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              textDirection: TextDirection.rtl,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: RichText(
                      textAlign: TextAlign.right,
                      text: TextSpan(
                        style:
                            const TextStyle(fontSize: 13, color: Colors.white),
                        children: [
                          TextSpan(
                            text: '${comment.username}  ',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(text: comment.content),
                        ],
                      ),
                    ),
                  ),
                ),
                if (canDelete)
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: Colors.white70),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => widget.onDelete!(comment),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 180,
          child: ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.white],
              stops: [0.0, 0.3],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: AnimatedList(
              key: _listKey,
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              initialItemCount: _displayed.length,
              itemBuilder: (context, index, animation) {
                if (index < 0 || index >= _displayed.length) {
                  return const SizedBox.shrink();
                }
                return _buildItem(_displayed[index], animation);
              },
            ),
          ),
        ),
        if (widget.canComment)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: _submit,
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'اكتب تعليقاً...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.black.withValues(alpha: 0.35),
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
      ],
    );
  }
}
