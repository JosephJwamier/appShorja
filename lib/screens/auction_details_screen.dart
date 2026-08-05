import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:marketplace_app/widgets/app_network_image.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/api_config.dart';
import '../config/deep_link_config.dart';
import '../models/auction.dart';
import '../models/bid.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../providers/auctions_provider.dart';
import '../services/analytics_service.dart';
import '../services/auction_service.dart'
    show AuctionService, BidsResult, MyBidStatus;
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import '../utils/share_helper.dart';
import 'store_profile_screen.dart' show VisitStoreButton;
import 'reservations_screen.dart';

class AuctionDetailsScreen extends StatefulWidget {
  final Auction auction;
  const AuctionDetailsScreen({super.key, required this.auction});

  @override
  State<AuctionDetailsScreen> createState() => _AuctionDetailsScreenState();
}

class _AuctionDetailsScreenState extends State<AuctionDetailsScreen> {
  late Auction _auction;
  bool _isPlacingBid = false;
  bool _isRefreshing = false;
  bool _isCancelling = false;
  bool _isEndingEarly = false;
  double? _minimumNextBid;
  MyBidStatus? _myStatus;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _isConnected = false;
  Timer? _ticker;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;

  final _bidController = TextEditingController();
  final _pageController = PageController();
  int _currentImage = 0;

  @override
  void initState() {
    super.initState();
    _auction = widget.auction;
    AppAnalytics.viewItem(
      itemId: _auction.item.id.toString(),
      itemName: _auction.item.title,
      contentType: 'auction',
    );
    if (_auction.isActive) {
      _connectWebSocket();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshAuction());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _connectWebSocket() {
    try {
      final url = Uri.parse(ApiConfig.wsUrl('/ws/auction/${_auction.id}/'));
      _channel = WebSocketChannel.connect(url);

      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: (_) {
          if (mounted) setState(() => _isConnected = false);
          _scheduleReconnect();
        },
        onDone: () {
          if (mounted) setState(() => _isConnected = false);
          _scheduleReconnect();
        },
      );

      _reconnectAttempts = 0;
      setState(() => _isConnected = true);
    } catch (_) {
      _scheduleReconnect();
    }
  }

  /// A dropped connection is common on mobile networks — without this the
  /// live price/bid feed just goes silent until the user manually leaves
  /// and reopens the screen. Backs off up to 30s so a genuinely offline
  /// device isn't hammered with reconnect attempts.
  void _scheduleReconnect() {
    if (!mounted || !_auction.isActive) return;
    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    final delaySeconds = [
      2,
      4,
      8,
      16,
      30,
    ][(_reconnectAttempts - 1).clamp(0, 4)];
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (mounted && !_isConnected) _connectWebSocket();
    });
  }

  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;

      if (data['type'] == 'auction_update' && data['event'] == 'new_bid') {
        final bidData = data['data'] as Map<String, dynamic>;
        final bidAmount = double.parse(bidData['bid_amount'].toString());
        final bidderUsername = bidData['bidder_username'] as String;

        // منع التكرار مع مزايدتنا التفاؤليّة
        if (_auction.bids.isNotEmpty) {
          final latest = _auction.bids.first;
          if (latest.bidder.username == bidderUsername &&
              (latest.amount - bidAmount).abs() < 0.01) {
            return;
          }
        }

        final newBid = Bid(
          id: -DateTime.now().millisecondsSinceEpoch,
          bidder: User(id: -1, username: bidderUsername, email: '', phone: ''),
          amount: bidAmount,
          depositPaid: false,
          isWinning: true,
          createdAt: DateTime.now(),
        );

        final previousBids = _auction.bids
            .map((b) => b.copyWith(isWinning: false))
            .toList();

        setState(() {
          _auction = _auction.copyWith(
            currentPrice: bidAmount,
            bids: [newBid, ...previousBids],
            bidCount: _auction.bidCount + 1,
          );
          _minimumNextBid = bidAmount + _auction.minimumIncrement;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            content: Text(
              'مزايدة جديدة من $bidderUsername بمبلغ ${formatIqd(bidAmount)}',
            ),
            backgroundColor: AppColors.secondary,
          ),
        );

        // تحديث حالة المزايد بعد وصول مزايدة جديدة
        Future.delayed(const Duration(milliseconds: 400), _fetchMyStatus);
      }
    } catch (_) {
      // تجاهل الرسائل غير المفهومة
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _bidController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _refreshAuction() async {
    setState(() => _isRefreshing = true);

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final service = AuctionService();

    try {
      final results = await Future.wait([
        service.fetchAuctionDetails(
          accessToken: auth.accessToken!,
          auctionId: _auction.id,
        ),
        service.fetchBids(
          accessToken: auth.accessToken!,
          auctionId: _auction.id,
        ),
      ]);

      if (!mounted) return;
      final fresh = results[0] as Auction;
      final bidsResult = results[1] as BidsResult;

      setState(() {
        _auction = fresh.copyWith(
          currentPrice: bidsResult.currentPrice,
          bidCount: bidsResult.totalBids,
          bids: bidsResult.bids,
        );
        _minimumNextBid = bidsResult.minimumNextBid;
        _isRefreshing = false;
      });
      _fetchMyStatus();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isRefreshing = false);
    }
  }

  Future<void> _fetchMyStatus() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    try {
      final status = await AuctionService().fetchMyStatus(
        accessToken: auth.accessToken!,
        auctionId: _auction.id,
      );
      if (!mounted) return;
      setState(() => _myStatus = status);
    } catch (_) {}
  }

  Future<void> _endAuctionEarly() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إنهاء المزاد مبكراً'),
        content: const Text(
          'هل تريد إنهاء المزاد الآن؟ سيُعلَن الفائز الحالي فائزاً بالمزاد.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تراجع'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryContainer,
            ),
            child: const Text('إنهاء الآن'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isEndingEarly = true);

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final result = await AuctionService().endAuctionEarly(
      accessToken: auth.accessToken!,
      auctionId: _auction.id,
    );

    if (!mounted) return;
    setState(() => _isEndingEarly = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? AppColors.primary : AppColors.error,
      ),
    );

    if (result.success) Navigator.pop(context);
  }

  Future<void> _cancelAuction() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء المزاد'),
        content: const Text(
          'هل أنت متأكد من إلغاء هذا المزاد؟ لا يمكن التراجع عن هذا الإجراء.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تراجع'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('إلغاء المزاد'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isCancelling = true);

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final result = await AuctionService().cancelAuction(
      accessToken: auth.accessToken!,
      auctionId: _auction.id,
    );

    if (!mounted) return;
    setState(() => _isCancelling = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? AppColors.primary : AppColors.error,
      ),
    );

    if (result.success) Navigator.pop(context);
  }

  String _formatBidTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inDays > 0) return 'منذ ${diff.inDays} يوم';
    if (diff.inHours > 0) return 'منذ ${diff.inHours} ساعة';
    if (diff.inMinutes > 0) return 'منذ ${diff.inMinutes} دقيقة';
    return 'الآن';
  }

  // أجزاء العدّاد الثلاثة (ساعة:دقيقة:ثانية) للمزاد النشط أو القادم
  ({int h, int m, int s})? _countdownParts() {
    final now = DateTime.now();
    int total;
    if (_auction.isUpcoming) {
      total = _auction.startTime.difference(now).inSeconds;
    } else if (_auction.isActive) {
      total = _auction.endTime.difference(now).inSeconds;
    } else {
      return null;
    }
    if (total < 0) total = 0;
    return (h: total ~/ 3600, m: (total % 3600) ~/ 60, s: total % 60);
  }

  Future<void> _placeBidFromBar() async {
    if (_isPlacingBid) return;
    final calculatedMin = _auction.currentPrice + _auction.minimumIncrement;
    final minimumBid =
        _minimumNextBid != null && _minimumNextBid! > calculatedMin
        ? _minimumNextBid!
        : calculatedMin;
    final typed = _bidController.text.trim();
    final double amount;
    if (typed.isEmpty) {
      // حقل فارغ → نزايد بأدنى مبلغ ممكن تلقائياً
      amount = minimumBid;
    } else {
      final value = double.tryParse(typed);
      if (value == null || value < minimumBid) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'المبلغ يجب أن يكون ${formatIqd(minimumBid)} أو أكثر',
            ),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      amount = value;
    }
    await _placeBid(amount);
    _bidController.clear();
  }

  Future<void> _placeBid(double amount) async {
    if (_isPlacingBid) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.user == null) return;

    // Optimistic update BEFORE the network request so that when the server
    // broadcasts a WebSocket event for this same bid, the guard in
    // _handleMessage sees it already at bids.first and skips the duplicate.
    final rollbackAuction = _auction;
    setState(() {
      _isPlacingBid = true;
      _auction = _withNewBid(amount, auth.user!);
    });

    final service = AuctionService();

    try {
      final result = await service.placeBid(
        accessToken: auth.accessToken!,
        auctionId: rollbackAuction.id,
        amount: amount,
      );

      if (!mounted) return;

      if (!result.success) {
        setState(() {
          _auction = rollbackAuction;
          _isPlacingBid = false;
        });
        // جلب بيانات محدّثة حتى يعرف المستخدم الحد الأدنى الصحيح
        _refreshAuction();
      } else {
        setState(() {
          _isPlacingBid = false;
          // تحديث الحد الأدنى مباشرةً بدون انتظار WebSocket أو refresh
          _minimumNextBid = amount + rollbackAuction.minimumIncrement;
        });
        if (mounted) {
          Provider.of<AuctionsProvider>(
            context,
            listen: false,
          ).loadAuctions(accessToken: auth.accessToken!);
          _fetchMyStatus();
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.success ? AppColors.primary : AppColors.error,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _auction = rollbackAuction;
        _isPlacingBid = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  Auction _withNewBid(double amount, User bidder) {
    final newBid = Bid(
      id: -DateTime.now().millisecondsSinceEpoch,
      bidder: bidder,
      amount: amount,
      depositPaid: false,
      isWinning: true,
      createdAt: DateTime.now(),
    );

    final previousBids = _auction.bids
        .map((b) => b.copyWith(isWinning: false))
        .toList();

    return _auction.copyWith(
      currentPrice: amount,
      bids: [newBid, ...previousBids],
      bidCount: _auction.bidCount + 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = _auction.item;
    final images = item.imageUrls;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final isOwner =
        auth.user != null &&
        item.owner.id != 0 &&
        auth.user!.id == item.owner.id;
    final calcMin = _auction.currentPrice + _auction.minimumIncrement;
    final minNextBid = _minimumNextBid != null && _minimumNextBid! > calcMin
        ? _minimumNextBid!
        : calcMin;
    final countdown = _countdownParts();
    final showBidBar = _auction.isActive && !isOwner;

    // الفائز: من حقل winner في API أو أعلى bid isWinning
    final winnerUser =
        _auction.winner ??
        _auction.bids.where((b) => b.isWinning).firstOrNull?.bidder;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        // شريط علويّ زجاجيّ
        appBar: AppBar(
          backgroundColor: AppColors.surface.withValues(alpha: 0.85),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            color: AppColors.onSurfaceVariant,
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'المزاد المباشر',
            style: TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          actions: [
            if (_isRefreshing)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.refresh, color: AppColors.primary),
                tooltip: 'تحديث',
                onPressed: _refreshAuction,
              ),
            IconButton(
              icon: const Icon(Icons.share, color: AppColors.primary),
              onPressed: () => shareLink(
                context,
                text: DeepLinkConfig.auctionLink(_auction.id),
                subject: _auction.item.title,
              ),
            ),
          ],
        ),
        body: ListView(
          padding: EdgeInsets.zero,
          children: [
            const SizedBox(height: 16),

            // صندوق العدّاد التنازليّ الذهبيّ
            if (countdown != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _CountdownBox(
                  hours: countdown.h,
                  minutes: countdown.m,
                  seconds: countdown.s,
                  label: _auction.isUpcoming
                      ? 'يبدأ المزاد خلال:'
                      : 'ينتهي المزاد خلال:',
                  connected: _isConnected,
                ),
              ),

            // بانر حالة المزايد — يظهر فقط للمزايدين (ليس المالك)
            if (!isOwner && _myStatus != null && _auction.isActive) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _BidStatusBanner(status: _myStatus!),
              ),
            ],

            // بطاقة الفائز — تظهر فقط عند انتهاء المزاد
            if (_auction.isEnded && winnerUser != null) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _WinnerCard(
                  username: winnerUser.username,
                  amount: _auction.currentPrice,
                  isMe: auth.user != null && auth.user!.id == winnerUser.id,
                ),
              ),
            ],

            const SizedBox(height: 24),

            // معرض الصور المربّع
            _ImageGallery(
              images: images,
              controller: _pageController,
              currentIndex: _currentImage,
              onChanged: (i) => setState(() => _currentImage = i),
            ),

            const SizedBox(height: 24),

            // العنوان + شارة الحالة
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.onSurface,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusBadge(auction: _auction),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // أعلى مزايدة حالية
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                textBaseline: TextBaseline.alphabetic,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                children: [
                  const Text(
                    'أعلى مزايدة حالية: ',
                    style: TextStyle(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    formatIqd(_auction.currentPrice),
                    style: const TextStyle(
                      color: AppColors.primaryContainer,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // بطاقة البائع
            if (item.owner.username.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _SellerCard(
                  sellerName: item.owner.username,
                  sellerUsername: item.owner.username,
                ),
              ),

            // أزرار المالك — إنهاء مبكر وإلغاء
            if (isOwner && (_auction.isActive || _auction.isUpcoming))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  children: [
                    // إنهاء مبكر — فقط للمزادات النشطة
                    if (_auction.isActive) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isEndingEarly ? null : _endAuctionEarly,
                          icon: _isEndingEarly
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primaryContainer,
                                  ),
                                )
                              : const Icon(Icons.timer_off_outlined, size: 18),
                          label: Text(
                            _isEndingEarly ? 'جاري...' : 'إنهاء مبكر',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primaryContainer,
                            side: const BorderSide(
                              color: AppColors.primaryContainer,
                            ),
                            minimumSize: const Size(0, 48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isCancelling ? null : _cancelAuction,
                        icon: _isCancelling
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.error,
                                ),
                              )
                            : const Icon(Icons.cancel_outlined, size: 18),
                        label: Text(_isCancelling ? 'جاري...' : 'إلغاء المزاد'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // وصف المنتج
            if (item.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'وصف المنتج',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      item.description,
                      style: const TextStyle(
                        color: AppColors.onSurfaceVariant,
                        fontSize: 15,
                        height: 1.7,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 32),

            // سجلّ المزايدات
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'سجل المزايدات',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                    ),
                  ),
                  Text(
                    '${_auction.bidCount} مزايدة',
                    style: const TextStyle(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            if (_auction.bids.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'لا توجد مزايدات بعد',
                    style: TextStyle(color: AppColors.onSurfaceVariant),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: _auction.bids
                      .map(
                        (bid) =>
                            _BidTile(bid: bid, timeFormatter: _formatBidTime),
                      )
                      .toList(),
                ),
              ),

            // مساحة سفليّة حتى لا يغطّي شريط المزايدة آخر عنصر
            SizedBox(height: showBidBar ? 120 : 32),
          ],
        ),

        // الشريط السفليّ الثابت للمزايدة
        bottomNavigationBar: showBidBar ? _buildBidBar(minNextBid) : null,
      ),
    );
  }

  Widget _buildBidBar(double minNextBid) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(
            color: AppColors.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // حقل المبلغ مع لاحقة "IQD"
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: TextField(
                    controller: _bidController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText: 'المبلغ',
                      suffixText: 'IQD',
                      filled: true,
                      fillColor: AppColors.surfaceContainer,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppColors.primaryContainer,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // زر "زايد الآن" المتدرّج
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _isPlacingBid ? null : _placeBidFromBar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryContainer,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isPlacingBid
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'زايد الآن',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            SizedBox(width: 6),
                            Icon(Icons.gavel, size: 18),
                          ],
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'أقل مزايدة قادمة مطلوبة: ${formatIqd(minNextBid)}',
            style: const TextStyle(
              color: AppColors.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// صندوق العدّاد التنازليّ بأرقام ذهبيّة
class _CountdownBox extends StatelessWidget {
  final int hours;
  final int minutes;
  final int seconds;
  final String label;
  final bool connected;
  const _CountdownBox({
    required this.hours,
    required this.minutes,
    required this.seconds,
    required this.label,
    required this.connected,
  });

  static const _gold = Color(0xFFF7C948);

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (connected) ...[
                const Icon(Icons.circle, size: 8, color: Colors.green),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _unit(_two(hours), 'ساعة'),
              _sep(),
              _unit(_two(minutes), 'دقيقة'),
              _sep(),
              _unit(_two(seconds), 'ثانية'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _unit(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: _gold,
            fontSize: 32,
            fontWeight: FontWeight.bold,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _sep() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        ':',
        style: TextStyle(
          color: _gold,
          fontSize: 32,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// معرض الصور المربّع مع مؤشّرات نقطيّة
class _ImageGallery extends StatelessWidget {
  final List<String> images;
  final PageController controller;
  final int currentIndex;
  final ValueChanged<int> onChanged;
  const _ImageGallery({
    required this.images,
    required this.controller,
    required this.currentIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final size = width < 600 ? width - 32 : 500.0;

    if (images.isEmpty) {
      return Center(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.image,
            size: 80,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      );
    }

    return Column(
      children: [
        Center(
          child: SizedBox(
            width: size,
            height: size,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: PageView.builder(
                controller: controller,
                onPageChanged: onChanged,
                itemCount: images.length,
                itemBuilder: (_, i) => AppNetworkImage(
                  images[i],
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    color: AppColors.surfaceContainer,
                    child: const Icon(Icons.broken_image, size: 80),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (images.length > 1) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              images.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == currentIndex ? 8 : 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == currentIndex
                      ? AppColors.primary
                      : AppColors.outlineVariant,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// شارة الحالة: نشط/قادم/منتهي
class _StatusBadge extends StatelessWidget {
  final Auction auction;
  const _StatusBadge({required this.auction});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    final IconData icon;

    if (auction.isActive) {
      color = AppColors.primary;
      label = 'مباشر';
      icon = Icons.gavel;
    } else if (auction.isUpcoming) {
      color = AppColors.secondary;
      label = 'قادم';
      icon = Icons.schedule;
    } else {
      color = AppColors.onSurfaceVariant;
      label = 'منتهي';
      icon = Icons.lock_clock;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// بطاقة البائع
class _SellerCard extends StatelessWidget {
  final String sellerName;
  final String sellerUsername;
  const _SellerCard({required this.sellerName, required this.sellerUsername});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: AppColors.secondaryContainer,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.storefront,
              color: AppColors.secondary,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              sellerName.isNotEmpty ? sellerName : 'بائع خاص',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.onSurface,
              ),
            ),
          ),
          VisitStoreButton(ownerUsername: sellerUsername),
        ],
      ),
    );
  }
}

// بانر حالة المزايد: يتصدر / تجاوزه أحد / لم يزايد بعد
class _BidStatusBanner extends StatelessWidget {
  final MyBidStatus status;
  const _BidStatusBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color border;
    final Color textColor;
    final IconData icon;
    final String title;
    final String subtitle;

    if (!status.hasBid) {
      bg = const Color(0xFFE3F2FD);
      border = const Color(0xFF90CAF9);
      textColor = const Color(0xFF1565C0);
      icon = Icons.visibility_outlined;
      title = 'لم تزايد بعد';
      subtitle = 'أدنى مزايدة: ${formatIqd(status.minimumNextBid)}';
    } else if (status.isWinning) {
      bg = const Color(0xFFE8F5E9);
      border = const Color(0xFF81C784);
      textColor = const Color(0xFF2E7D32);
      icon = Icons.emoji_events_outlined;
      title = 'أنت تتصدر المزاد!';
      subtitle = 'مزايدتك: ${formatIqd(status.yourHighestBid!)}';
    } else {
      bg = const Color(0xFFFFEBEE);
      border = const Color(0xFFEF9A9A);
      textColor = const Color(0xFFC62828);
      icon = Icons.trending_down;
      final behind = status.amountBehind != null
          ? formatIqd(status.amountBehind!)
          : formatIqd(status.currentPrice - status.yourHighestBid!);
      title = 'تجاوزك أحد!';
      subtitle =
          'مزايدتك ${formatIqd(status.yourHighestBid!)} · متأخر بـ $behind';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: textColor.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// بطاقة الفائز — تظهر عند انتهاء المزاد
class _WinnerCard extends StatelessWidget {
  final String username;
  final double amount;
  final bool isMe;
  const _WinnerCard({
    required this.username,
    required this.amount,
    this.isMe = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF8E1), Color(0xFFFFF3CD)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFF7C948).withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Color(0xFFF7C948),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.emoji_events,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'الفائز بالمزاد',
                      style: TextStyle(fontSize: 12, color: Color(0xFF8D6E00)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      username,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF5D4000),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'بمبلغ',
                    style: TextStyle(fontSize: 11, color: Color(0xFF8D6E00)),
                  ),
                  Text(
                    formatIqd(amount),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF5D4000),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (isMe) ...[
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ReservationsScreen()),
                );
              },
              icon: const Icon(Icons.receipt_long, size: 18),
              label: const Text('أكمل حجزك الآن — اختر طريقة الدفع'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF7C948),
                foregroundColor: const Color(0xFF5D4000),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// بطاقة مزايدة في السجلّ — الفائز يبرز بخلفية بيضاء واسم برتقاليّ
class _BidTile extends StatelessWidget {
  final Bid bid;
  final String Function(DateTime) timeFormatter;
  const _BidTile({required this.bid, required this.timeFormatter});

  @override
  Widget build(BuildContext context) {
    final isWinning = bid.isWinning;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isWinning
            ? AppColors.surfaceContainerLowest
            : AppColors.surfaceContainerLowest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(
            alpha: isWinning ? 0.25 : 0.1,
          ),
        ),
        boxShadow: isWinning
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              bid.bidder.username.isNotEmpty
                  ? bid.bidder.username[0].toUpperCase()
                  : '?',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isWinning ? AppColors.primary : AppColors.secondary,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      bid.bidder.username,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isWinning
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: AppColors.onSurface,
                      ),
                    ),
                    Text(
                      formatIqd(bid.amount),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isWinning
                            ? AppColors.primaryContainer
                            : AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  timeFormatter(bid.createdAt),
                  style: const TextStyle(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
