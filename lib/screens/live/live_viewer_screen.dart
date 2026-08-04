import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../config/api_config.dart';
import '../../config/deep_link_config.dart';
import '../../models/live_comment.dart';
import '../../models/live_session.dart';
import '../../providers/auth_provider.dart';
import '../../providers/live_sessions_provider.dart';
import '../../services/auction_service.dart';
import '../../services/live_session_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/formatters.dart';
import '../../utils/share_helper.dart';
import '../../widgets/live/live_comments_panel.dart';
import '../../widgets/live/live_product_control_sheets.dart';
import '../../widgets/live/live_viewers_sheet.dart';
import '../reservations_screen.dart';
import '../../features/location/providers/location_provider.dart';
import '../../features/location/screens/location_picker_sheet.dart';
import '../../features/location/screens/add_edit_location_screen.dart';

/// Viewer screen: subscribes to the broadcaster's Agora feed, shows the
/// currently-showing product with a one-tap Reserve button (captures the
/// actual rendered video frame as proof, charges the deposit immediately),
/// live comments, and likes. Real-time events arrive over the ws/live/
/// socket, same connection pattern as StoreChatScreen/AuctionDetailsScreen.
class LiveViewerScreen extends StatefulWidget {
  final int sessionId;
  const LiveViewerScreen({super.key, required this.sessionId});

  @override
  State<LiveViewerScreen> createState() => _LiveViewerScreenState();
}

class _LiveViewerScreenState extends State<LiveViewerScreen> {
  final _service = LiveSessionService();
  final _videoBoundaryKey = GlobalKey();

  LiveSession? _session;
  LiveSessionItem? _nowShowing;
  LiveAuction? _liveAuction;
  Timer? _auctionTicker;
  bool _isBidding = false;
  String? _loadError;
  bool _streamEnded = false;

  RtcEngine? _engine;
  int? _remoteUid;
  String? _channelName;
  String? _agoraError;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;

  final List<LiveComment> _comments = [];
  bool _isCapturing = false;
  int _reserveCooldownSeconds = 0;
  Timer? _cooldownTimer;
  bool _banned = false;

  String get _accessToken => context.read<AuthProvider>().accessToken!;
  int? get _currentUserId => context.read<AuthProvider>().user?.id;
  String? get _currentUsername => context.read<AuthProvider>().user?.username;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final session = await _service.fetchLiveSessionDetail(
        accessToken: _accessToken,
        sessionId: widget.sessionId,
      );
      if (!mounted) return;
      setState(() {
        _session = session;
        _nowShowing = session.currentNowShowing;
        _liveAuction = session.currentLiveAuction;
      });
      if (_liveAuction != null) _startAuctionTicker();
    } catch (e) {
      if (mounted) setState(() => _loadError = e.toString());
      return;
    }

    _connectWebSocket();
    _loadComments();
    await _initAgora();
  }

  Future<void> _initAgora() async {
    try {
      final joinToken = await _service.fetchJoinToken(
        accessToken: _accessToken,
        sessionId: widget.sessionId,
        role: 'subscriber',
      );
      _channelName = joinToken.channelName;

      final engine = createAgoraRtcEngine();
      await engine.initialize(RtcEngineContext(appId: joinToken.appId));
      await engine.enableVideo();
      engine.registerEventHandler(RtcEngineEventHandler(
        onUserJoined: (connection, remoteUid, elapsed) {
          if (mounted) setState(() => _remoteUid = remoteUid);
        },
        onUserOffline: (connection, remoteUid, reason) {
          if (mounted) setState(() => _remoteUid = null);
        },
        onError: (err, msg) {
          if (mounted) setState(() => _agoraError = 'تعذّر تشغيل البث: $msg');
        },
      ));
      await engine.joinChannel(
        token: joinToken.token,
        channelId: joinToken.channelName,
        uid: joinToken.uid,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
          clientRoleType: ClientRoleType.clientRoleAudience,
        ),
      );
      _engine = engine;
    } catch (e) {
      if (mounted) setState(() => _agoraError = 'تعذّر الاتصال بالبث: $e');
    }
  }

  void _connectWebSocket() {
    try {
      final url = Uri.parse(
        ApiConfig.wsUrl('/ws/live/${widget.sessionId}/?token=$_accessToken'),
      );
      _channel = WebSocketChannel.connect(url);
      _subscription = _channel!.stream.listen(
        _handleWsMessage,
        onError: (_) => _scheduleReconnect(),
        onDone: _handleWsDone,
      );
      _reconnectAttempts = 0;
    } catch (_) {
      // Screen still shows the last-known session state — just retry quietly.
      _scheduleReconnect();
    }
  }

  /// A rejected connect() closes with code 4403 (see backend
  /// LiveSessionConsumer.is_banned) before the server ever accepts the
  /// socket — e.g. reopening the stream after already being banned.
  /// Without this check that rejection would just look like a dropped
  /// connection and retry forever.
  void _handleWsDone() {
    if (_channel?.closeCode == 4403) {
      _onBanned();
      return;
    }
    _scheduleReconnect();
  }

  /// A dropped connection is common on mobile networks — without this the
  /// viewer count/comments/now-showing feed just goes silent until the
  /// viewer leaves and reopens the screen. Backs off up to 30s so a
  /// genuinely offline device isn't hammered with reconnect attempts.
  void _scheduleReconnect() {
    if (!mounted || _streamEnded || _banned) return;
    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    final delaySeconds = [2, 4, 8, 16, 30][
        (_reconnectAttempts - 1).clamp(0, 4)];
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (mounted && !_streamEnded) _connectWebSocket();
    });
  }

  void _handleWsMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      final payload = data['data'] as Map<String, dynamic>? ?? {};

      switch (data['type']) {
        case 'viewer_count':
          if (_session != null) {
            setState(() => _session =
                _session!.copyWith(currentViewerCount: payload['current_viewer_count'] as int? ?? 0));
          }
          break;
        case 'like_update':
          if (_session != null) {
            setState(() => _session = _session!.copyWith(likesCount: payload['likes_count'] as int? ?? 0));
          }
          break;
        case 'product_now_showing':
          setState(() => _nowShowing = LiveSessionItem(
                id: payload['queue_item_id'] as int,
                itemId: payload['item_id'] as int,
                itemTitle: payload['item_title'] as String? ?? '',
                price: double.tryParse(payload['price'].toString()) ?? 0,
                depositAmount: double.tryParse(payload['deposit_amount'].toString()) ?? 0,
                order: 0,
                status: 'now_showing',
              ));
          break;
        case 'item_sold_out':
          if (_nowShowing != null && _nowShowing!.id == payload['queue_item_id']) {
            setState(() => _nowShowing = _nowShowing!.copyWith(status: 'sold_out'));
          }
          break;
        case 'auction_started':
          setState(() {
            _nowShowing = null;
            _liveAuction = LiveAuction(
              id: payload['auction_id'] as int,
              itemTitle: payload['item_title'] as String? ?? '',
              startingPrice: double.tryParse(payload['starting_price'].toString()) ?? 0,
              currentPrice: double.tryParse(payload['current_price'].toString()) ?? 0,
              minimumIncrement: double.tryParse(payload['minimum_increment'].toString()) ?? 0,
              minimumNextBid: double.tryParse(payload['minimum_next_bid'].toString()) ?? 0,
              bidDeposit: double.tryParse(payload['bid_deposit'].toString()) ?? 0,
              status: 'active',
              endTime: DateTime.parse(payload['end_time'] as String),
              totalBids: 0,
            );
          });
          _startAuctionTicker();
          break;
        case 'auction_bid':
          if (_liveAuction != null && _liveAuction!.id == payload['auction_id']) {
            setState(() => _liveAuction = _liveAuction!.copyWith(
                  currentPrice: double.tryParse(payload['current_price'].toString()),
                  minimumNextBid: double.tryParse(payload['minimum_next_bid'].toString()),
                  totalBids: payload['total_bids'] as int?,
                ));
          }
          break;
        case 'auction_ended':
          if (_liveAuction != null && _liveAuction!.id == payload['auction_id']) {
            _onAuctionEnded(payload);
          }
          break;
        case 'comment_posted':
          setState(() => _comments.add(LiveComment.fromJson(payload)));
          break;
        case 'comment_deleted':
          setState(() => _comments.removeWhere((c) => c.id == payload['comment_id']));
          break;
        case 'stream_ended':
          _onStreamEnded();
          break;
        case 'viewer_banned':
          if (payload['user_id'] == _currentUserId) _onBanned();
          break;
      }
    } catch (_) {
      // ignore malformed events
    }
  }

  /// Soft-kick for a viewer banned mid-stream (see backend broadcast_live_event
  /// call in the bans view) — the server can't force-close this specific
  /// socket, so the client disconnects itself the moment it sees its own
  /// user_id in the event.
  void _onBanned() {
    if (_banned || _streamEnded) return;
    _banned = true;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('تم حظرك'),
        content: const Text('قام صاحب المتجر بحظرك من هذا البث المباشر.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  void _onStreamEnded() {
    if (_streamEnded) return;
    _streamEnded = true;
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('انتهى البث'),
        content: const Text('أنهى صاحب المتجر هذا البث المباشر.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadComments() async {
    try {
      final comments =
          await _service.fetchComments(accessToken: _accessToken, sessionId: widget.sessionId);
      if (mounted) setState(() => _comments.addAll(comments));
    } catch (_) {
      // non-critical
    }
  }

  Future<void> _sendComment(String content) async {
    await _service.postComment(accessToken: _accessToken, sessionId: widget.sessionId, content: content);
  }

  Future<void> _deleteComment(LiveComment comment) async {
    await _service.deleteComment(
        accessToken: _accessToken, sessionId: widget.sessionId, commentId: comment.id);
    setState(() => _comments.removeWhere((c) => c.id == comment.id));
  }

  /// Bans the comment's author from this session only (see backend
  /// LiveSessionBan docstring), then removes the offending comment too —
  /// mirrors LiveBroadcastScreen._banCommentAuthor exactly, only reachable
  /// here when session.isModerator is true.
  Future<void> _banCommentAuthor(LiveComment comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حظر المستخدم؟'),
        content: Text('لن يستطيع ${comment.username} التعليق أو مشاهدة هذا البث بعد الآن.'),
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

    final result = await _service.banViewer(
      accessToken: _accessToken,
      sessionId: widget.sessionId,
      userId: comment.userId,
    );
    if (!mounted) return;
    if (result.success) {
      await _deleteComment(comment);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  void _openViewersSheet() {
    showLiveViewersSheet(
      context,
      sessionId: widget.sessionId,
      accessToken: _accessToken,
      currentUserId: _currentUserId,
    );
  }

  // Product-control actions below are only reachable when session.isModerator
  // is true (see _buildModeratorControls) — the backend grants the exact
  // same powers to a session moderator as to the store owner (see
  // LiveSessionViewSet.catalog/show_item/quick_show/quick_auction, all
  // gated by _can_moderate_live_session), so these mirror
  // LiveBroadcastScreen's versions exactly via the shared sheets/dialogs.

  Future<void> _openCatalogSheet() async {
    await showLiveCatalogSheet(
      context,
      sessionId: widget.sessionId,
      accessToken: _accessToken,
      service: _service,
      onShown: (item) => setState(() => _nowShowing = item),
    );
  }

  Future<void> _openQuickShowDialog() async {
    final result = await showLiveQuickShowDialog(context);
    if (result == null) return;

    final response = await _service.quickShow(
      accessToken: _accessToken,
      sessionId: widget.sessionId,
      title: result.title,
      price: result.price,
      depositAmount: result.deposit,
      quantity: result.quantity,
    );
    if (!mounted) return;
    if (response.success) {
      final session = await _service.fetchLiveSessionDetail(
        accessToken: _accessToken,
        sessionId: widget.sessionId,
      );
      setState(() => _nowShowing = session.currentNowShowing);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response.message)));
    }
  }

  Future<void> _openQuickAuctionDialog() async {
    final result = await showLiveQuickAuctionDialog(context);
    if (result == null) return;

    final response = await _service.quickAuction(
      accessToken: _accessToken,
      sessionId: widget.sessionId,
      title: result.title,
      startingPrice: result.startingPrice,
      minimumIncrement: result.minimumIncrement,
      bidDeposit: result.bidDeposit,
      quantity: result.quantity,
    );
    if (!mounted) return;
    if (response.success && response.auction != null) {
      setState(() {
        _nowShowing = null;
        _liveAuction = response.auction;
      });
      _startAuctionTicker();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response.message)));
    }
  }

  Future<void> _toggleLike() async {
    if (_session == null) return;
    final wasLiked = _session!.isLikedByMe;
    // optimistic update
    setState(() => _session = _session!.copyWith(
          isLikedByMe: !wasLiked,
          likesCount: _session!.likesCount + (wasLiked ? -1 : 1),
        ));
    final result = wasLiked
        ? await _service.unlikeSession(accessToken: _accessToken, sessionId: widget.sessionId)
        : await _service.likeSession(accessToken: _accessToken, sessionId: widget.sessionId);
    if (mounted && _session != null) {
      setState(() => _session = _session!.copyWith(likesCount: result.likesCount));
      context.read<LiveSessionsProvider>().applyLikeUpdate(widget.sessionId, !wasLiked, result.likesCount);
    }
  }

  Future<Uint8List?> _captureFrame() async {
    try {
      final boundary =
          _videoBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;
      return byteData.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _openReserveSheet() async {
    final nowShowing = _nowShowing;
    if (nowShowing == null || !nowShowing.isNowShowing) return;

    if (_engine == null || _remoteUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('لا يوجد بث فيديو نشط حالياً — لا يمكن الحجز بدون لقطة من البث'),
      ));
      return;
    }

    setState(() => _isCapturing = true);
    final screenshotBytes = await _captureFrame();
    if (!mounted) return;
    setState(() => _isCapturing = false);

    if (screenshotBytes == null || screenshotBytes.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تعذّر التقاط لقطة من البث، حاول مجدداً')));
      return;
    }

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ReserveSheet(
        sessionId: widget.sessionId,
        queueItem: nowShowing,
        screenshotBytes: screenshotBytes,
        accessToken: _accessToken,
        service: _service,
      ),
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✅ تم الحجز وخصم العربون من محفظتك'),
        backgroundColor: AppColors.success,
      ));
      _startReserveCooldown();
    }
  }

  /// A short pause between successive reserve taps — each tap reserves
  /// exactly one piece, so this keeps one eager viewer from instantly
  /// buying up all the stock in a rapid-fire tapping burst.
  void _startReserveCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _reserveCooldownSeconds = 5);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _reserveCooldownSeconds--;
        if (_reserveCooldownSeconds <= 0) {
          _reserveCooldownSeconds = 0;
          timer.cancel();
        }
      });
    });
  }

  void _startAuctionTicker() {
    _auctionTicker?.cancel();
    _auctionTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _onAuctionEnded(Map<String, dynamic> payload) {
    _auctionTicker?.cancel();
    final winner = payload['winner_username'] as String?;
    final iWon = winner != null && winner == _currentUsername;
    setState(() => _liveAuction = null);
    if (!mounted) return;

    if (iWon) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('🎉 مبروك، فزت بالمزاد!'),
          content: const Text('أكمل حجزك الآن من صفحة حجوزاتي خلال 48 ساعة.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('لاحقاً')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ReservationsScreen()),
                );
              },
              child: const Text('اذهب إلى حجوزاتي'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(winner != null ? '🔨 انتهى المزاد — الفائز: $winner' : '🔨 انتهى المزاد بدون فائز'),
        backgroundColor: AppColors.secondary,
      ));
    }
  }

  Future<void> _placeBid(double amount) async {
    final auction = _liveAuction;
    if (auction == null) return;
    setState(() => _isBidding = true);
    final result = await AuctionService().placeBid(
      accessToken: _accessToken,
      auctionId: auction.id,
      amount: amount,
    );
    if (!mounted) return;
    setState(() => _isBidding = false);
    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _auctionTicker?.cancel();
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _engine?.leaveChannel();
    _engine?.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(_loadError!, style: const TextStyle(color: Colors.white)),
        ),
      );
    }
    if (_session == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    final session = _session!;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                key: _videoBoundaryKey,
                child: _buildRemoteVideo(),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  _buildTopBar(session),
                  if (_liveAuction != null)
                    _buildAuctionCard()
                  else if (_nowShowing != null)
                    _buildNowShowingCard(),
                  const Spacer(),
                  LiveCommentsPanel(
                    comments: _comments,
                    currentUserId: _currentUserId,
                    isModerator: session.isModerator,
                    onSend: _sendComment,
                    onDelete: _deleteComment,
                    onBan: _banCommentAuthor,
                  ),
                  if (session.isModerator) _buildModeratorControls(),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRemoteVideo() {
    if (_agoraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_agoraError!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
        ),
      );
    }
    if (_engine == null || _remoteUid == null || _channelName == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 12),
            Text('بانتظار بدء البث...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }
    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: _engine!,
        canvas: VideoCanvas(uid: _remoteUid!),
        connection: RtcConnection(channelId: _channelName!),
      ),
    );
  }

  Widget _buildTopBar(LiveSession session) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(session.title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(session.store.name,
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            onPressed: () => shareLink(
              context,
              text: DeepLinkConfig.liveLink(session.id),
              subject: session.title,
            ),
          ),
          session.isModerator
              ? GestureDetector(
                  onTap: _openViewersSheet,
                  child: _StatChip(icon: Icons.visibility, label: '${session.currentViewerCount}'),
                )
              : _StatChip(icon: Icons.visibility, label: '${session.currentViewerCount}'),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _toggleLike,
            child: _StatChip(
              icon: session.isLikedByMe ? Icons.favorite : Icons.favorite_border,
              label: '${session.likesCount}',
              iconColor: session.isLikedByMe ? AppColors.error : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNowShowingCard() {
    final item = _nowShowing!;
    final videoReady = _engine != null && _remoteUid != null;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(item.itemTitle,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  '${formatIqd(item.price)} — عربون ${formatIqd(item.depositAmount)}',
                  style: const TextStyle(color: AppColors.gold, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          item.isSoldOut
              ? const Chip(label: Text('نفدت الكمية'), backgroundColor: AppColors.error)
              : ElevatedButton.icon(
                  onPressed: (_isCapturing || !videoReady || _reserveCooldownSeconds > 0)
                      ? null
                      : _openReserveSheet,
                  icon: _isCapturing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.bookmark_add),
                  label: Text(_reserveCooldownSeconds > 0
                      ? 'انتظر $_reserveCooldownSecondsث'
                      : (videoReady ? 'احجز الآن' : 'بانتظار البث')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: (videoReady && _reserveCooldownSeconds == 0)
                        ? AppColors.error
                        : AppColors.onSurfaceVariant,
                  ),
                ),
        ],
      ),
    );
  }
  Widget _buildAuctionCard() {
    final auction = _liveAuction!;
    final remaining = auction.timeRemaining;
    final minutes = remaining.inMinutes.toString().padLeft(2, '0');
    final seconds = (remaining.inSeconds % 60).toString().padLeft(2, '0');
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.gavel, color: AppColors.gold, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(auction.itemTitle,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              Text('$minutes:$seconds',
                  style: const TextStyle(
                      color: AppColors.gold, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 6),
          Text('السعر الحالي: ${formatIqd(auction.currentPrice)}  •  ${auction.totalBids} مزايدة',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          Text('عربون المشاركة: ${formatIqd(auction.bidDeposit)}',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: (!_isBidding && remaining > Duration.zero)
                ? () => _placeBid(auction.minimumNextBid)
                : null,
            icon: _isBidding
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black87))
                : const Icon(Icons.gavel),
            label: Text('زايد الآن بـ ${formatIqd(auction.minimumNextBid)}'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  /// Only rendered when session.isModerator is true — same three "show a
  /// product" actions as LiveBroadcastScreen's bottom controls, granted to
  /// this viewer because the store owner made them a session moderator.
  Widget _buildModeratorControls() {
    final auctionActive = _liveAuction != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: auctionActive ? null : _openCatalogSheet,
                  icon: const Icon(Icons.storefront),
                  label: const Text('اعرض من المنتجات'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryContainer),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: auctionActive ? null : _openQuickShowDialog,
                  icon: const Icon(Icons.flash_on),
                  label: const Text('عرض سريع'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.secondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: auctionActive ? null : _openQuickAuctionDialog,
              icon: const Icon(Icons.gavel),
              label: const Text('مزاد سريع (دقيقتان)'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  const _StatChip({required this.icon, required this.label, this.iconColor = Colors.white});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ]),
    );
  }
}

/// Confirms quantity, shows the captured screenshot as proof, and submits
/// the reservation (deposit charged immediately from the buyer's wallet).
class _ReserveSheet extends StatefulWidget {
  final int sessionId;
  final LiveSessionItem queueItem;
  final Uint8List screenshotBytes;
  final String accessToken;
  final LiveSessionService service;

  const _ReserveSheet({
    required this.sessionId,
    required this.queueItem,
    required this.screenshotBytes,
    required this.accessToken,
    required this.service,
  });

  @override
  State<_ReserveSheet> createState() => _ReserveSheetState();
}

class _ReserveSheetState extends State<_ReserveSheet> {
  int _quantity = 1;
  bool _isSubmitting = false;
  bool _resolvingLocation = true;
  LocationPickerResult? _delivery;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveDeliveryLocation());
  }

  /// Silently reuses the buyer's saved address (same one-tap-reserve
  /// experience as before delivery addresses were required) — only
  /// interrupts the flow when there is truly no address to fall back to,
  /// and even then skips straight to "add" instead of an empty picker list.
  Future<void> _resolveDeliveryLocation() async {
    final provider = context.read<LocationProvider>();
    await provider.loadMyLocations(widget.accessToken);
    if (!mounted) return;

    if (provider.myLocations.isNotEmpty) {
      setState(() {
        _delivery = LocationPickerResult.fromLocation(provider.myLocations.first);
        _resolvingLocation = false;
      });
      return;
    }

    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddEditLocationScreen()),
    );
    if (!mounted) return;
    setState(() {
      if (added == true && provider.myLocations.isNotEmpty) {
        _delivery = LocationPickerResult.fromLocation(provider.myLocations.first);
      }
      _resolvingLocation = false;
    });
  }

  Future<void> _changeLocation() async {
    final loc = await showLocationPickerSheet(
      context,
      token: widget.accessToken,
      title: 'اختر موقع التسليم',
    );
    if (!mounted || loc == null) return;
    setState(() => _delivery = LocationPickerResult.fromLocation(loc));
  }

  Future<void> _submit() async {
    if (_delivery == null) return;

    setState(() => _isSubmitting = true);
    final result = await widget.service.reserveItem(
      accessToken: widget.accessToken,
      sessionId: widget.sessionId,
      queueItemId: widget.queueItem.id,
      quantity: _quantity,
      screenshotBytes: widget.screenshotBytes,
      deliveryLocationId: _delivery!.locationId,
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result.success) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.queueItem;
    final totalDeposit = item.depositAmount * _quantity;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('تأكيد الحجز', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(
              widget.screenshotBytes,
              height: 140,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 12),
          Text(item.itemTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('${formatIqd(item.price)} للقطعة الواحدة'),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
              ),
              Text('$_quantity', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => setState(() => _quantity++),
              ),
            ],
          ),
          Text('العربون المستحق الآن: ${formatIqd(totalDeposit)}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
          const SizedBox(height: 12),
          if (_resolvingLocation)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Center(
                  child: SizedBox(
                      height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (_delivery != null)
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 16, color: AppColors.onSurfaceVariant),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'التسليم إلى: ${_delivery!.address}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
                  ),
                ),
                TextButton(
                  onPressed: _changeLocation,
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                  child: const Text('تغيير', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: (_isSubmitting || _resolvingLocation || _delivery == null) ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('احجز وادفع العربون'),
          ),
        ],
      ),
    );
  }
}
