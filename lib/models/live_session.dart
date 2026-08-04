/// Lightweight ref to the store hosting a live session — mirrors the
/// backend's PublicUserStoreSerializer shape (NOT the full Store model,
/// which expects a nested `user` object this endpoint doesn't send).
class LiveStoreRef {
  final int id;
  final String name;
  final String? logoUrl;
  final String ownerUsername;

  LiveStoreRef({
    required this.id,
    required this.name,
    this.logoUrl,
    required this.ownerUsername,
  });

  factory LiveStoreRef.fromJson(Map<String, dynamic> json) {
    return LiveStoreRef(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      logoUrl: json['logo_url'] as String?,
      ownerUsername: json['owner_username'] as String? ?? '',
    );
  }
}

/// A product queued/shown during a live session, with its live-only
/// price/deposit (independent of any regular catalog listing price).
class LiveSessionItem {
  final int id;
  final int itemId;
  final String itemTitle;
  final String? itemImageUrl;
  final double price;
  final double depositAmount;
  final int order;
  final String status; // queued / now_showing / sold_out / skipped

  LiveSessionItem({
    required this.id,
    required this.itemId,
    required this.itemTitle,
    this.itemImageUrl,
    required this.price,
    required this.depositAmount,
    required this.order,
    required this.status,
  });

  bool get isNowShowing => status == 'now_showing';
  bool get isSoldOut => status == 'sold_out';

  LiveSessionItem copyWith({String? status}) {
    return LiveSessionItem(
      id: id,
      itemId: itemId,
      itemTitle: itemTitle,
      itemImageUrl: itemImageUrl,
      price: price,
      depositAmount: depositAmount,
      order: order,
      status: status ?? this.status,
    );
  }

  factory LiveSessionItem.fromJson(Map<String, dynamic> json) {
    final item = json['item'] as Map<String, dynamic>? ?? const {};
    return LiveSessionItem(
      id: json['id'] as int,
      itemId: item['id'] as int? ?? 0,
      itemTitle: item['name'] as String? ?? '',
      itemImageUrl: item['image'] as String?,
      price: _toDouble(json['price']),
      depositAmount: _toDouble(json['deposit_amount']),
      order: json['order'] as int? ?? 0,
      status: json['status'] as String? ?? 'queued',
    );
  }
}

/// A 2-minute live-broadcast auction (see LiveSessionViewSet.quick_auction) —
/// bidding/settlement are the exact same AuctionListing machinery as any
/// other auction, this is just a lightweight live-overlay view of it.
class LiveAuction {
  final int id;
  final String itemTitle;
  final String? itemImageUrl;
  final double startingPrice;
  final double currentPrice;
  final double minimumIncrement;
  final double minimumNextBid;
  final double bidDeposit;
  final String status; // active / ended
  final DateTime endTime;
  final int totalBids;

  LiveAuction({
    required this.id,
    required this.itemTitle,
    this.itemImageUrl,
    required this.startingPrice,
    required this.currentPrice,
    required this.minimumIncrement,
    required this.minimumNextBid,
    required this.bidDeposit,
    required this.status,
    required this.endTime,
    required this.totalBids,
  });

  Duration get timeRemaining {
    final remaining = endTime.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  LiveAuction copyWith({
    double? currentPrice,
    double? minimumNextBid,
    int? totalBids,
    String? status,
  }) {
    return LiveAuction(
      id: id,
      itemTitle: itemTitle,
      itemImageUrl: itemImageUrl,
      startingPrice: startingPrice,
      currentPrice: currentPrice ?? this.currentPrice,
      minimumIncrement: minimumIncrement,
      minimumNextBid: minimumNextBid ?? this.minimumNextBid,
      bidDeposit: bidDeposit,
      status: status ?? this.status,
      endTime: endTime,
      totalBids: totalBids ?? this.totalBids,
    );
  }

  factory LiveAuction.fromJson(Map<String, dynamic> json) {
    return LiveAuction(
      id: json['id'] as int,
      itemTitle: json['item_title'] as String? ?? '',
      itemImageUrl: json['item_image'] as String?,
      startingPrice: _toDouble(json['starting_price']),
      currentPrice: _toDouble(json['current_price']),
      minimumIncrement: _toDouble(json['minimum_increment']),
      minimumNextBid: _toDouble(json['minimum_next_bid']),
      bidDeposit: _toDouble(json['bid_deposit']),
      status: json['status'] as String? ?? 'active',
      endTime: DateTime.parse(json['end_time'] as String),
      totalBids: json['total_bids'] as int? ?? 0,
    );
  }
}

class LiveSession {
  final int id;
  final LiveStoreRef store;
  final String title;
  final String? description;
  final String? thumbnailUrl;
  final String status; // scheduled / live / ended / cancelled
  final int currentViewerCount;
  final int peakViewerCount;
  final int totalViews;
  final int likesCount;
  final bool isLikedByMe;
  final DateTime? scheduledAt;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final List<LiveSessionItem> queueItems;
  final LiveSessionItem? currentNowShowing;
  final LiveAuction? currentLiveAuction;
  final bool isModerator;

  LiveSession({
    required this.id,
    required this.store,
    required this.title,
    this.description,
    this.thumbnailUrl,
    required this.status,
    required this.currentViewerCount,
    required this.peakViewerCount,
    required this.totalViews,
    required this.likesCount,
    required this.isLikedByMe,
    this.scheduledAt,
    this.startedAt,
    this.endedAt,
    this.queueItems = const [],
    this.currentNowShowing,
    this.currentLiveAuction,
    this.isModerator = false,
  });

  bool get isLive => status == 'live';

  LiveSession copyWith({
    int? currentViewerCount,
    int? likesCount,
    bool? isLikedByMe,
    String? status,
    LiveSessionItem? currentNowShowing,
    List<LiveSessionItem>? queueItems,
    LiveAuction? currentLiveAuction,
    bool clearLiveAuction = false,
  }) {
    return LiveSession(
      id: id,
      store: store,
      title: title,
      description: description,
      thumbnailUrl: thumbnailUrl,
      status: status ?? this.status,
      currentViewerCount: currentViewerCount ?? this.currentViewerCount,
      peakViewerCount: peakViewerCount,
      totalViews: totalViews,
      likesCount: likesCount ?? this.likesCount,
      isLikedByMe: isLikedByMe ?? this.isLikedByMe,
      scheduledAt: scheduledAt,
      startedAt: startedAt,
      endedAt: endedAt,
      queueItems: queueItems ?? this.queueItems,
      currentNowShowing: currentNowShowing ?? this.currentNowShowing,
      currentLiveAuction:
          clearLiveAuction ? null : (currentLiveAuction ?? this.currentLiveAuction),
      isModerator: isModerator,
    );
  }

  factory LiveSession.fromJson(Map<String, dynamic> json) {
    final queueItemsJson = json['queue_items'] as List<dynamic>?;
    final nowShowingJson = json['current_now_showing'] as Map<String, dynamic>?;
    final liveAuctionJson = json['current_live_auction'] as Map<String, dynamic>?;

    return LiveSession(
      id: json['id'] as int,
      store: LiveStoreRef.fromJson(json['store'] as Map<String, dynamic>),
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      thumbnailUrl: json['thumbnail'] as String?,
      status: json['status'] as String? ?? 'scheduled',
      currentViewerCount: json['current_viewer_count'] as int? ?? 0,
      peakViewerCount: json['peak_viewer_count'] as int? ?? 0,
      totalViews: json['total_views'] as int? ?? 0,
      likesCount: json['likes_count'] as int? ?? 0,
      isLikedByMe: json['is_liked_by_me'] as bool? ?? false,
      scheduledAt: json['scheduled_at'] != null
          ? DateTime.tryParse(json['scheduled_at'] as String)
          : null,
      startedAt: json['started_at'] != null
          ? DateTime.tryParse(json['started_at'] as String)
          : null,
      endedAt: json['ended_at'] != null
          ? DateTime.tryParse(json['ended_at'] as String)
          : null,
      queueItems: (queueItemsJson ?? const [])
          .map((e) => LiveSessionItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      currentNowShowing: nowShowingJson != null
          ? LiveSessionItem.fromJson(nowShowingJson)
          : null,
      currentLiveAuction: liveAuctionJson != null
          ? LiveAuction.fromJson(liveAuctionJson)
          : null,
      isModerator: json['is_moderator'] as bool? ?? false,
    );
  }
}

/// One entry from GET /live-sessions/{id}/catalog/ — the store owner's own
/// items, pre-annotated with a suggested price/deposit so showing one live
/// is a single tap with nothing to type.
class LiveCatalogEntry {
  final int itemId;
  final String title;
  final String? imageUrl;
  final int quantity;
  final double? suggestedPrice;
  final double? suggestedDepositAmount;
  final String sessionStatus; // not_shown / queued / now_showing / sold_out
  final int? queueItemId;

  LiveCatalogEntry({
    required this.itemId,
    required this.title,
    this.imageUrl,
    required this.quantity,
    this.suggestedPrice,
    this.suggestedDepositAmount,
    required this.sessionStatus,
    this.queueItemId,
  });

  factory LiveCatalogEntry.fromJson(Map<String, dynamic> json) {
    return LiveCatalogEntry(
      itemId: json['item_id'] as int,
      title: json['title'] as String? ?? '',
      imageUrl: json['image'] as String?,
      quantity: json['quantity'] as int? ?? 0,
      suggestedPrice: json['suggested_price'] != null
          ? _toDouble(json['suggested_price'])
          : null,
      suggestedDepositAmount: json['suggested_deposit_amount'] != null
          ? _toDouble(json['suggested_deposit_amount'])
          : null,
      sessionStatus: json['session_status'] as String? ?? 'not_shown',
      queueItemId: json['queue_item_id'] as int?,
    );
  }
}

/// Agora RTC join credentials from POST /live-sessions/{id}/join-token/.
class LiveJoinToken {
  final String appId;
  final String channelName;
  final String token;
  final int uid;

  LiveJoinToken({
    required this.appId,
    required this.channelName,
    required this.token,
    required this.uid,
  });

  factory LiveJoinToken.fromJson(Map<String, dynamic> json) {
    return LiveJoinToken(
      appId: json['app_id'] as String,
      channelName: json['channel_name'] as String,
      token: json['token'] as String,
      uid: json['uid'] as int? ?? 0,
    );
  }
}

double _toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}
