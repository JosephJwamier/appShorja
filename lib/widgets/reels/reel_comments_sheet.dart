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
///
/// الردود بمستوى واحد كإنستغرام: كل تعليق رئيسي تحته ردوده، وأيّ أحد —
/// البائع أو مشاهد آخر — يردّ على أيّ تعليق أو ردّ.
Future<void> showReelCommentsSheet(
  BuildContext context, {
  required Reel reel,
  required String accessToken,
  required int? currentUserId,
  required bool isStoreOwner,
  VoidCallback? onCommentPosted,
  /// التعليق الذي جاء منه الإشعار: تُمرَّر إليه القائمة ويُظلَّل لحظات.
  /// بدونها يفتح صاحب الريل ورقةً فيها خمسون تعليقاً ويبحث عن الذي
  /// أُخبر عنه — وهو غالباً سؤال عن البضاعة ينتظر جواباً.
  int? highlightCommentId,
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
      highlightCommentId: highlightCommentId,
    ),
  );
}

class _ReelCommentsSheet extends StatefulWidget {
  final Reel reel;
  final String accessToken;
  final int? currentUserId;
  final bool isStoreOwner;
  final VoidCallback? onCommentPosted;
  final int? highlightCommentId;

  const _ReelCommentsSheet({
    required this.reel,
    required this.accessToken,
    required this.currentUserId,
    required this.isStoreOwner,
    this.onCommentPosted,
    this.highlightCommentId,
  });

  @override
  State<_ReelCommentsSheet> createState() => _ReelCommentsSheetState();
}

class _ReelCommentsSheetState extends State<_ReelCommentsSheet> {
  final _service = ReelService();
  final _controller = TextEditingController();
  final _inputFocus = FocusNode();
  final _listController = ScrollController();

  /// التعليقات الرئيسية، وردود كلٍّ منها داخله.
  List<ReelComment> _comments = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _error;

  /// التعليق الذي يُكتب الردّ عليه الآن، أو null لتعليق جديد.
  ReelComment? _replyTo;

  /// سلاسل فتحها المستخدم. الطويلة مطويّة افتراضياً كي لا يدفع نقاشٌ واحد
  /// بقية الأسئلة خارج الورقة.
  final Set<int> _expanded = {};
  static const _collapseAbove = 2;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      // إعادة التحميل بعد النشر لا تُخفي القائمة خلف مؤشّر: تبقى ظاهرة
      // إلى أن تُستبدل، فلا ترمش الورقة مع كل ردّ.
      _isLoading = _comments.isEmpty;
      _error = null;
    });
    try {
      final comments = await _service.fetchComments(
        accessToken: widget.accessToken,
        reelId: widget.reel.id,
      );
      if (!mounted) return;
      setState(() => _comments = comments);
      _scrollToHighlighted();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// يفتح السلسلة التي فيها التعليق المقصود ويمرّر القائمة إليها.
  ///
  /// تقدير بارتفاع صفّ ثابت لا مفاتيح عامة: الصفوف متفاوتة قليلاً بطول
  /// النصّ، والتقدير يضع السلسلة في الشاشة — والتظليل يُكمل التعريف.
  void _scrollToHighlighted() {
    final target = widget.highlightCommentId;
    if (target == null) return;
    final index = _comments.indexWhere(
      (c) => c.id == target || c.replies.any((r) => r.id == target),
    );
    if (index < 0) return;
    setState(() => _expanded.add(_comments[index].id));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_listController.hasClients) return;
      const estimatedRowHeight = 84.0;
      final offset = (index * estimatedRowHeight)
          .clamp(0.0, _listController.position.maxScrollExtent);
      _listController.animateTo(
        offset,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    });
  }

  void _startReply(ReelComment comment) {
    setState(() => _replyTo = comment);
    _inputFocus.requestFocus();
  }

  void _cancelReply() => setState(() => _replyTo = null);

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;
    final replyTo = _replyTo;
    setState(() => _isSending = true);
    final result = await _service.postComment(
      accessToken: widget.accessToken,
      reelId: widget.reel.id,
      content: text,
      parentId: replyTo?.id,
    );
    if (!mounted) return;
    setState(() => _isSending = false);
    if (result.success) {
      _controller.clear();
      setState(() {
        _replyTo = null;
        // الردّ الجديد يجب أن يُرى فور نشره، ولو كانت سلسلته مطويّة.
        if (replyTo != null) _expanded.add(replyTo.parentId ?? replyTo.id);
      });
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
      setState(() {
        if (comment.isReply) {
          _comments = [
            for (final c in _comments)
              c.id == comment.parentId
                  ? c.copyWith(
                      replies: c.replies.where((r) => r.id != comment.id).toList())
                  : c,
          ];
        } else {
          _comments.removeWhere((c) => c.id == comment.id);
        }
        final replyTarget = _replyTo;
        if (replyTarget != null &&
            (replyTarget.id == comment.id || replyTarget.parentId == comment.id)) {
          _replyTo = null;
        }
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  @override
  void dispose() {
    _listController.dispose();
    _controller.dispose();
    _inputFocus.dispose();
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
                Expanded(child: _buildList()),
                const Divider(height: 1),
                if (_replyTo != null)
                  _ReplyingToBar(username: _replyTo!.username, onCancel: _cancelReply),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            focusNode: _inputFocus,
                            textInputAction: TextInputAction.send,
                            maxLength: 300,
                            minLines: 1,
                            maxLines: 4,
                            decoration: InputDecoration(
                              hintText: _replyTo != null
                                  ? 'اكتب ردّك على ${_replyTo!.username}...'
                                  : 'أضف تعليقاً...',
                              counterText: '',
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
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: _replyTo != null ? 'إرسال الردّ' : 'إرسال التعليق',
                          icon: _isSending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.send, color: AppColors.primary),
                          onPressed: _isSending ? null : _submit,
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

  Widget _buildList() {
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
      // متحكّم خاص لا متحكّم الورقة: التمرير إلى تعليق بعينه يخصّ هذه
      // القائمة، وتحريك متحكّم الورقة كان سيسحبها لا محتواها.
      controller: _listController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _comments.length,
      itemBuilder: (context, index) => _buildThread(_comments[index]),
    );
  }

  Widget _buildThread(ReelComment comment) {
    final replies = comment.replies;
    final collapsible = replies.length > _collapseAbove;
    final collapsed = collapsible && !_expanded.contains(comment.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildRow(comment),
          // الردود مُزاحة تحت صورة صاحب التعليق، فيُقرأ النقاش كوحدة واحدة.
          if (!collapsed)
            for (final reply in replies)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 40),
                child: _buildRow(reply),
              ),
          if (collapsible)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 40),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    if (collapsed) {
                      _expanded.add(comment.id);
                    } else {
                      _expanded.remove(comment.id);
                    }
                  }),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.onSurfaceVariant,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: Icon(
                    collapsed ? Icons.expand_more_rounded : Icons.expand_less_rounded,
                    size: 18,
                  ),
                  label: Text(
                    collapsed ? 'عرض ${replies.length} ردود' : 'إخفاء الردود',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRow(ReelComment comment) {
    final canDelete = widget.isStoreOwner || comment.userId == widget.currentUserId;
    final isHighlighted = comment.id == widget.highlightCommentId;
    final isReply = comment.isReply;

    return Container(
      decoration: isHighlighted
          ? BoxDecoration(
              color: AppColors.primaryContainer.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            )
          : null,
      padding: const EdgeInsetsDirectional.fromSTEB(4, 6, 0, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: isReply ? 13 : 16,
            backgroundColor:
                comment.isStoreOwner ? AppColors.primary : AppColors.primaryContainer,
            child: Text(
              comment.username.isNotEmpty
                  ? comment.username.characters.first.toUpperCase()
                  : '?',
              style: TextStyle(
                color: Colors.white,
                fontSize: isReply ? 11 : 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        comment.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                    if (comment.isStoreOwner) ...[
                      const SizedBox(width: 6),
                      const _SellerBadge(),
                    ],
                    const SizedBox(width: 6),
                    Text(relativeTimeAr(comment.createdAt),
                        style: const TextStyle(color: AppColors.onSurfaceVariant, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    children: [
                      if (comment.replyToUsername != null)
                        TextSpan(
                          text: '@${comment.replyToUsername} ',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      TextSpan(text: comment.content),
                    ],
                  ),
                  style: const TextStyle(fontSize: 13, height: 1.35),
                ),
                TextButton(
                  onPressed: () => _startReply(comment),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.onSurfaceVariant,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(44, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('ردّ',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          if (canDelete)
            IconButton(
              tooltip: 'حذف',
              icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.onSurfaceVariant),
              onPressed: () => _delete(comment),
            ),
        ],
      ),
    );
  }
}

/// وسم صاحب المتجر بجانب اسمه: جواب البائع عن سؤال البضاعة غير رأي زبون.
class _SellerBadge extends StatelessWidget {
  const _SellerBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'البائع',
        style: TextStyle(
          color: AppColors.primary,
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// شريط فوق حقل الكتابة يقول لمن يُكتب الردّ، مع زرّ إلغائه.
class _ReplyingToBar extends StatelessWidget {
  final String username;
  final VoidCallback onCancel;

  const _ReplyingToBar({required this.username, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceContainerLow,
      padding: const EdgeInsetsDirectional.only(start: 16, end: 4),
      child: Row(
        children: [
          const Icon(Icons.reply_rounded, size: 16, color: AppColors.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'تردّ على '),
                TextSpan(
                  text: username,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: AppColors.onSurfaceVariant),
            ),
          ),
          IconButton(
            tooltip: 'إلغاء الردّ',
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}
