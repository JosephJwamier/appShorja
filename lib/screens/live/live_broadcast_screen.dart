import 'dart:async';
import 'dart:convert';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../config/api_config.dart';
import '../../models/live_comment.dart';
import '../../models/live_session.dart';
import '../../providers/auth_provider.dart';
import '../../services/auction_service.dart';
import '../../services/live_session_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/formatters.dart';
import '../../widgets/live/live_comments_panel.dart';
import '../../widgets/live/live_viewers_sheet.dart';

/// Store owner's live-broadcast control screen: publishes the camera feed
/// to Agora, and controls the session (catalog picker / quick-show /
/// end) over REST while a WebSocket relays viewer count, comments, and
/// reservation events in real time. Same WS pattern as StoreChatScreen
/// (?token= query param, raw WebSocketChannel owned by this State).
class LiveBroadcastScreen extends StatefulWidget {
  final int sessionId;
  const LiveBroadcastScreen({super.key, required this.sessionId});

  @override
  State<LiveBroadcastScreen> createState() => _LiveBroadcastScreenState();
}

class _LiveBroadcastScreenState extends State<LiveBroadcastScreen> {
  final _service = LiveSessionService();

  LiveSession? _session;
  LiveSessionItem? _nowShowing;
  String? _loadError;

  RtcEngine? _engine;
  bool _agoraJoined = false;
  String? _agoraError;
  int _localUid = 0;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;

  final List<LiveComment> _comments = [];
  bool _isEnding = false;

  LiveAuction? _liveAuction;
  Timer? _auctionTicker;
  bool _isEndingAuction = false;

  String get _accessToken => context.read<AuthProvider>().accessToken!;
  int? get _currentUserId => context.read<AuthProvider>().user?.id;

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
    final statuses = await [Permission.camera, Permission.microphone].request();
    final granted = (statuses[Permission.camera]?.isGranted ?? false) &&
        (statuses[Permission.microphone]?.isGranted ?? false);
    if (!granted) {
      if (mounted) setState(() => _agoraError = 'يجب السماح بالوصول إلى الكاميرا والميكروفون لبدء البث');
      return;
    }

    try {
      final joinToken = await _service.fetchJoinToken(
        accessToken: _accessToken,
        sessionId: widget.sessionId,
        role: 'publisher',
      );
      _localUid = joinToken.uid;

      final engine = createAgoraRtcEngine();
      await engine.initialize(RtcEngineContext(appId: joinToken.appId));
      await engine.enableVideo();
      engine.registerEventHandler(RtcEngineEventHandler(
        onJoinChannelSuccess: (connection, elapsed) {
          if (mounted) setState(() => _agoraJoined = true);
        },
        onError: (err, msg) {
          if (mounted) setState(() => _agoraError = 'تعذّر الاتصال بخادم البث: $msg');
        },
      ));
      await engine.startPreview();
      await engine.joinChannel(
        token: joinToken.token,
        channelId: joinToken.channelName,
        uid: joinToken.uid,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );
      _engine = engine;
    } catch (e) {
      if (mounted) setState(() => _agoraError = 'تعذّر بدء الكاميرا: $e');
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
        onDone: _scheduleReconnect,
      );
      _reconnectAttempts = 0;
    } catch (_) {
      // REST controls still work without the live feed — just retry quietly.
      _scheduleReconnect();
    }
  }

  /// A dropped connection is common on mobile networks — without this the
  /// viewer count/comments feed just goes silent until the owner leaves and
  /// reopens the screen. Backs off up to 30s so a genuinely offline device
  /// isn't hammered with reconnect attempts.
  void _scheduleReconnect() {
    if (!mounted) return;
    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    final delaySeconds = [2, 4, 8, 16, 30][
        (_reconnectAttempts - 1).clamp(0, 4)];
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (mounted) _connectWebSocket();
    });
  }

  void _handleWsMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      final payload = data['data'] as Map<String, dynamic>? ?? {};

      switch (data['type']) {
        case 'viewer_count':
          if (_session != null) {
            setState(() => _session = _session!.copyWith(
                  currentViewerCount: payload['current_viewer_count'] as int? ?? 0,
                ));
          }
          break;
        case 'like_update':
          if (_session != null) {
            setState(() => _session = _session!.copyWith(likesCount: payload['likes_count'] as int? ?? 0));
          }
          break;
        case 'item_reserved':
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('🙋 ${payload['buyer_username']} حجز المنتج المعروض'),
            backgroundColor: AppColors.success,
          ));
          break;
        case 'item_sold_out':
          setState(() => _nowShowing = _nowShowing?.copyWith(status: 'sold_out'));
          break;
        case 'comment_posted':
          setState(() => _comments.add(LiveComment.fromJson(payload)));
          break;
        case 'comment_deleted':
          setState(() => _comments.removeWhere((c) => c.id == payload['comment_id']));
          break;
        case 'auction_started':
          // The backend demotes any now-showing fixed item the moment an
          // auction starts — reflect that locally too so both never show at once.
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
            _auctionTicker?.cancel();
            final winner = payload['winner_username'] as String?;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(winner != null ? '🔨 انتهى المزاد — الفائز: $winner' : '🔨 انتهى المزاد بدون فائز'),
              backgroundColor: AppColors.secondary,
            ));
            setState(() => _liveAuction = null);
          }
          break;
      }
    } catch (_) {
      // ignore malformed events
    }
  }

  void _startAuctionTicker() {
    _auctionTicker?.cancel();
    _auctionTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadComments() async {
    try {
      final comments = await _service.fetchComments(
        accessToken: _accessToken,
        sessionId: widget.sessionId,
      );
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
      accessToken: _accessToken,
      sessionId: widget.sessionId,
      commentId: comment.id,
    );
    setState(() => _comments.removeWhere((c) => c.id == comment.id));
  }

  /// Bans the comment's author from this session only (see backend
  /// LiveSessionBan docstring), then removes the offending comment too.
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

  Future<void> _openCatalogSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _CatalogSheet(
        sessionId: widget.sessionId,
        accessToken: _accessToken,
        service: _service,
        onShown: (item) => setState(() => _nowShowing = item),
      ),
    );
  }

  Future<void> _openQuickShowDialog() async {
    final result = await showDialog<_QuickShowInput>(
      context: context,
      builder: (_) => const _QuickShowDialog(),
    );
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
    final result = await showDialog<_QuickAuctionInput>(
      context: context,
      builder: (_) => const _QuickAuctionDialog(),
    );
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

  Future<void> _endAuctionNow() async {
    final auction = _liveAuction;
    if (auction == null) return;
    setState(() => _isEndingAuction = true);
    final result = await AuctionService().endAuctionEarly(
      accessToken: _accessToken,
      auctionId: auction.id,
    );
    if (!mounted) return;
    setState(() => _isEndingAuction = false);
    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
    }
    // On success, the auction_ended WS event (broadcast by the backend)
    // clears _liveAuction and shows the result — nothing more to do here.
  }

  Future<void> _endSession() async {
    setState(() => _isEnding = true);
    final result = await _service.endSession(accessToken: _accessToken, sessionId: widget.sessionId);
    if (!mounted) return;
    setState(() => _isEnding = false);
    if (result.success) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _auctionTicker?.cancel();
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final confirmed = await _confirmEndOnBack();
        if (confirmed && mounted) await _endSession();
      },
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Positioned.fill(child: _buildLocalPreview()),
              SafeArea(
                child: Column(
                  children: [
                    _buildTopBar(),
                    if (_liveAuction != null)
                      _buildAuctionBanner()
                    else if (_nowShowing != null)
                      _buildNowShowingBanner(),
                    const Spacer(),
                    LiveCommentsPanel(
                      comments: _comments,
                      currentUserId: _currentUserId,
                      isModerator: true,
                      onSend: _sendComment,
                      onDelete: _deleteComment,
                      onBan: _banCommentAuthor,
                    ),
                    _buildBottomControls(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmEndOnBack() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إنهاء البث؟'),
        content: const Text('سيتم إنهاء البث المباشر لجميع المشاهدين.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('تراجع')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إنهاء', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _buildLocalPreview() {
    if (_agoraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_agoraError!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
        ),
      );
    }
    if (_engine == null || !_agoraJoined) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: _engine!,
        canvas: VideoCanvas(uid: _localUid),
      ),
    );
  }

  Widget _buildTopBar() {
    final session = _session!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: _isEnding ? null : () async {
              final confirmed = await _confirmEndOnBack();
              if (confirmed) await _endSession();
            },
            icon: const Icon(Icons.stop_circle, color: Colors.white),
            label: const Text('إنهاء', style: TextStyle(color: Colors.white)),
            style: TextButton.styleFrom(backgroundColor: AppColors.error.withValues(alpha: 0.85)),
          ),
          const Spacer(),
          _StatChip(icon: Icons.favorite, label: '${session.likesCount}'),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _openViewersSheet,
            child: _StatChip(icon: Icons.visibility, label: '${session.currentViewerCount}'),
          ),
          const SizedBox(width: 6),
          const _LiveDot(),
        ],
      ),
    );
  }

  Widget _buildNowShowingBanner() {
    final item = _nowShowing!;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            item.isSoldOut ? Icons.block : Icons.campaign,
            color: item.isSoldOut ? AppColors.error : AppColors.gold,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.isSoldOut
                  ? '${item.itemTitle} — نفدت الكمية'
                  : '${item.itemTitle} — ${formatIqd(item.price)} (عربون ${formatIqd(item.depositAmount)})',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuctionBanner() {
    final auction = _liveAuction!;
    final remaining = auction.timeRemaining;
    final minutes = remaining.inMinutes.toString().padLeft(2, '0');
    final seconds = (remaining.inSeconds % 60).toString().padLeft(2, '0');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.gavel, color: Colors.black87),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${auction.itemTitle} — السعر الحالي ${formatIqd(auction.currentPrice)}',
                  style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '$minutes:$seconds — ${auction.totalBids} مزايدة — عربون ${formatIqd(auction.bidDeposit)}',
                  style: const TextStyle(color: Colors.black87, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _isEndingAuction ? null : _endAuctionNow,
            style: TextButton.styleFrom(backgroundColor: Colors.black87),
            child: _isEndingAuction
                ? const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('إنهاء الآن', style: TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    final auctionActive = _liveAuction != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: auctionActive ? null : _openCatalogSheet,
                  icon: const Icon(Icons.storefront),
                  label: const Text('اعرض من منتجاتي'),
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

class _LiveDot extends StatelessWidget {
  const _LiveDot();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(6)),
      child: const Text('مباشر', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatChip({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: Colors.white),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ]),
    );
  }
}

/// Bottom sheet listing the owner's own showable items — one tap shows
/// whichever one they pick, price/deposit pulled automatically.
class _CatalogSheet extends StatefulWidget {
  final int sessionId;
  final String accessToken;
  final LiveSessionService service;
  final ValueChanged<LiveSessionItem> onShown;

  const _CatalogSheet({
    required this.sessionId,
    required this.accessToken,
    required this.service,
    required this.onShown,
  });

  @override
  State<_CatalogSheet> createState() => _CatalogSheetState();
}

class _CatalogSheetState extends State<_CatalogSheet> {
  List<LiveCatalogEntry>? _entries;
  String? _error;
  int? _showingItemId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final entries = await widget.service.fetchCatalog(
        accessToken: widget.accessToken,
        sessionId: widget.sessionId,
      );
      if (mounted) setState(() => _entries = entries);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _show(LiveCatalogEntry entry) async {
    setState(() => _showingItemId = entry.itemId);
    final result = await widget.service.showItem(
      accessToken: widget.accessToken,
      sessionId: widget.sessionId,
      itemId: entry.itemId,
    );
    if (!mounted) return;
    setState(() => _showingItemId = null);

    if (result.success) {
      final session = await widget.service.fetchLiveSessionDetail(
        accessToken: widget.accessToken,
        sessionId: widget.sessionId,
      );
      if (session.currentNowShowing != null) widget.onShown(session.currentNowShowing!);
      if (mounted) Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        if (_error != null) {
          return Center(child: Text(_error!));
        }
        if (_entries == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_entries!.isEmpty) {
          return const Center(child: Text('لا توجد منتجات في متجرك بعد'));
        }
        return ListView.builder(
          controller: scrollController,
          padding: const EdgeInsets.all(12),
          itemCount: _entries!.length,
          itemBuilder: (context, index) {
            final entry = _entries![index];
            final busy = _showingItemId == entry.itemId;
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: entry.imageUrl != null
                    ? CircleAvatar(backgroundImage: NetworkImage(entry.imageUrl!))
                    : const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
                title: Text(entry.title, textAlign: TextAlign.right),
                subtitle: Text(
                  entry.suggestedPrice != null
                      ? '${formatIqd(entry.suggestedPrice!)} — الكمية ${entry.quantity}'
                      : 'بدون سعر مُدرج — الكمية ${entry.quantity}',
                  textAlign: TextAlign.right,
                ),
                trailing: busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : ElevatedButton(
                        onPressed: entry.sessionStatus == 'now_showing' ? null : () => _show(entry),
                        child: Text(entry.sessionStatus == 'now_showing' ? 'معروض الآن' : 'اعرض'),
                      ),
              ),
            );
          },
        );
      },
    );
  }
}

class _QuickShowInput {
  final String title;
  final double price;
  final double deposit;
  final int quantity;
  _QuickShowInput(this.title, this.price, this.deposit, this.quantity);
}

/// "Show something never added to the app before" — title/price/deposit
/// only, a backing Item is created automatically by the backend.
class _QuickShowDialog extends StatefulWidget {
  const _QuickShowDialog();

  @override
  State<_QuickShowDialog> createState() => _QuickShowDialogState();
}

class _QuickShowDialogState extends State<_QuickShowDialog> {
  final _titleController = TextEditingController();
  final _priceController = TextEditingController();
  final _depositController = TextEditingController();
  int _quantity = 1;

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _depositController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('عرض سريع'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'لمنتج غير مُضاف للتطبيق من قبل — فقط اكتب الاسم والسعر والعربون',
              style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(labelText: 'اسم المنتج'),
            ),
            TextField(
              controller: _priceController,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'السعر'),
            ),
            TextField(
              controller: _depositController,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'العربون'),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('الكمية المتوفرة'),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                    ),
                    Text('$_quantity', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => setState(() => _quantity++),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              final title = _titleController.text.trim();
              final price = double.tryParse(_priceController.text.trim());
              final deposit = double.tryParse(_depositController.text.trim());
              if (title.isEmpty || price == null || deposit == null) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('أكمل جميع الحقول بشكل صحيح')));
                return;
              }
              Navigator.pop(context, _QuickShowInput(title, price, deposit, _quantity));
            },
            child: const Text('اعرض الآن'),
          ),
        ],
      ),
    );
  }
}

class _QuickAuctionInput {
  final String title;
  final double startingPrice;
  final double minimumIncrement;
  final double bidDeposit;
  final int quantity;
  _QuickAuctionInput(
      this.title, this.startingPrice, this.minimumIncrement, this.bidDeposit, this.quantity);
}

/// A 2-minute live auction — same one-tap spirit as quick-show, but viewers
/// bid instead of instantly reserving. Winner gets a pending Reservation to
/// complete, exactly like any other auction.
class _QuickAuctionDialog extends StatefulWidget {
  const _QuickAuctionDialog();

  @override
  State<_QuickAuctionDialog> createState() => _QuickAuctionDialogState();
}

class _QuickAuctionDialogState extends State<_QuickAuctionDialog> {
  final _titleController = TextEditingController();
  final _priceController = TextEditingController();
  final _incrementController = TextEditingController(text: '5');
  final _depositController = TextEditingController();
  int _quantity = 1;

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _incrementController.dispose();
    _depositController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('مزاد سريع (دقيقتان)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'يبدأ المزاد فوراً لمدة دقيقتين — المشاهدون يزايدون بدلاً من الحجز المباشر',
                style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titleController,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(labelText: 'اسم المنتج'),
              ),
              TextField(
                controller: _priceController,
                textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'سعر الافتتاح'),
              ),
              TextField(
                controller: _incrementController,
                textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'الحد الأدنى لزيادة كل مزايدة'),
              ),
              TextField(
                controller: _depositController,
                textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'عربون المشاركة بالمزايدة'),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('الكمية المتوفرة'),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                      ),
                      Text('$_quantity', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => setState(() => _quantity++),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              final title = _titleController.text.trim();
              final price = double.tryParse(_priceController.text.trim());
              final increment = double.tryParse(_incrementController.text.trim());
              final deposit = double.tryParse(_depositController.text.trim());
              if (title.isEmpty || price == null || increment == null || deposit == null) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('أكمل جميع الحقول بشكل صحيح')));
                return;
              }
              Navigator.pop(context, _QuickAuctionInput(title, price, increment, deposit, _quantity));
            },
            child: const Text('ابدأ المزاد'),
          ),
        ],
      ),
    );
  }
}
