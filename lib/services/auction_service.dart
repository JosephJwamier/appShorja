import 'dart:convert';
import '../models/auction.dart';
import '../models/bid.dart';
import '../models/filter_params.dart';
import 'api_client.dart';

class AuctionService {
  final _client = ApiClient.instance;

  Future<({List<Auction> auctions, bool hasMore})> fetchAuctions({
    required String accessToken,
    int page = 1,
    String? search,
    String? status,
    bool activeOnly = false,
    FilterParams filters = FilterParams.empty,
  }) async {
    final queryParams = <String, String>{'page': page.toString()};
    queryParams.addAll(filters.toAuctionQueryParams());
    if (search != null && search.isNotEmpty) queryParams['search'] = search;
    if (status != null && status.isNotEmpty) queryParams['status'] = status;
    if (activeOnly) queryParams['active_only'] = 'true';

    final response = await _client
        .get('/auctions/?${Uri(queryParameters: queryParams).query}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>;
      return (
        auctions: results
            .map((item) => Auction.fromJson(item as Map<String, dynamic>))
            .toList(),
        hasMore: data['next'] != null,
      );
    } else {
      throw Exception('فشل جلب المزادات');
    }
  }

  Future<List<Auction>> fetchAuctionsByStoreUsername({
    required String accessToken,
    required String username,
  }) async {
    final response = await _client.get(
      '/auctions/?${Uri(queryParameters: {'seller_username_exact': username}).query}',
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final results = (body['results'] ?? body['data'] ?? []) as List<dynamic>;
      return results
          .map((item) => Auction.fromJson(item as Map<String, dynamic>))
          .toList();
    }
    throw Exception('فشل جلب مزادات المتجر');
  }

  Future<List<Auction>> fetchMyAuctions({
    required String accessToken,
  }) async {
    final response = await _client.get('/auctions/my_auctions/');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>;
      return results
          .map((item) => Auction.fromJson(item as Map<String, dynamic>))
          .toList();
    } else {
      throw Exception('فشل جلب مزاداتك');
    }
  }

  Future<({bool success, String message})> placeBid({
    required String accessToken,
    required int auctionId,
    required double amount,
  }) async {
    final response = await _client.post(
      '/auctions/$auctionId/place_bid/',
      body: {'amount': amount},
    );

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final success = data['success'] as bool? ?? false;
      final message =
          data['message'] as String? ??
          (success ? 'تمت المزايدة' : 'فشلت المزايدة');
      return (success: success, message: message);
    } catch (_) {
      return (success: false, message: 'استجابة غير متوقّعة من الخادم');
    }
  }

  Future<Auction> fetchAuctionDetails({
    required String accessToken,
    required int auctionId,
  }) async {
    final response = await _client.get('/auctions/$auctionId/');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return Auction.fromDetailJson(data);
    } else {
      throw Exception('فشل جلب تفاصيل المزاد');
    }
  }

  /// GET /api/auctions/{id}/my_status/
  /// Returns the current user's bidding status in the auction.
  Future<MyBidStatus> fetchMyStatus({
    required String accessToken,
    required int auctionId,
  }) async {
    final response = await _client.get('/auctions/$auctionId/my_status/');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return MyBidStatus.fromJson(data);
    } else {
      throw Exception('فشل جلب حالة المزايدة');
    }
  }

  /// POST /api/auctions/{id}/end_early/
  Future<({bool success, String message})> endAuctionEarly({
    required String accessToken,
    required int auctionId,
  }) async {
    final response = await _client.post('/auctions/$auctionId/end_early/');

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final success = response.statusCode == 200 &&
          (data['success'] as bool? ?? false);
      final message = data['message'] as String? ??
          (success ? 'تم إنهاء المزاد مبكراً' : 'فشل إنهاء المزاد');
      return (success: success, message: message);
    } catch (_) {
      return (success: false, message: 'استجابة غير متوقّعة من الخادم');
    }
  }

  /// POST /api/auctions/{id}/cancel/
  Future<({bool success, String message})> cancelAuction({
    required String accessToken,
    required int auctionId,
  }) async {
    final response = await _client.post('/auctions/$auctionId/cancel/');

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final success = response.statusCode == 200 &&
          (data['success'] as bool? ?? false);
      final message = data['message'] as String? ??
          (success ? 'تم إلغاء المزاد' : 'فشل إلغاء المزاد');
      return (success: success, message: message);
    } catch (_) {
      return (success: false, message: 'استجابة غير متوقّعة من الخادم');
    }
  }

  /// GET /api/auctions/{id}/bids/
  /// Returns bids list + current_price + minimum_next_bid from the server.
  Future<BidsResult> fetchBids({
    required String accessToken,
    required int auctionId,
  }) async {
    final response = await _client.get('/auctions/$auctionId/bids/');

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final rawList = body['data'] as List<dynamic>;
      return BidsResult(
        bids: rawList
            .map((b) => Bid.fromJson(b as Map<String, dynamic>))
            .toList(),
        totalBids: body['total_bids'] as int? ?? rawList.length,
        currentPrice: double.parse(body['current_price'] as String),
        minimumNextBid: double.parse(body['minimum_next_bid'] as String),
      );
    } else if (response.statusCode == 401) {
      throw Exception('الجلسة منتهية، سجّل دخولاً من جديد');
    } else {
      throw Exception('فشل جلب المزايدات');
    }
  }
}

class BidsResult {
  final List<Bid> bids;
  final int totalBids;
  final double currentPrice;
  final double minimumNextBid;

  const BidsResult({
    required this.bids,
    required this.totalBids,
    required this.currentPrice,
    required this.minimumNextBid,
  });
}

class MyBidStatus {
  final bool hasBid;
  final bool isWinning;
  final double? yourHighestBid;
  final double currentPrice;
  final double minimumNextBid;
  final int totalBids;
  final double? amountBehind;

  const MyBidStatus({
    required this.hasBid,
    required this.isWinning,
    required this.yourHighestBid,
    required this.currentPrice,
    required this.minimumNextBid,
    required this.totalBids,
    required this.amountBehind,
  });

  factory MyBidStatus.fromJson(Map<String, dynamic> json) {
    double? parseAmount(dynamic v) =>
        v == null ? null : double.tryParse(v.toString());

    return MyBidStatus(
      hasBid: json['has_bid'] as bool? ?? false,
      isWinning: json['is_winning'] as bool? ?? false,
      yourHighestBid: parseAmount(json['your_highest_bid']),
      currentPrice: parseAmount(json['current_price']) ?? 0,
      minimumNextBid: parseAmount(json['minimum_next_bid']) ?? 0,
      totalBids: json['total_bids'] as int? ?? 0,
      amountBehind: parseAmount(json['amount_behind']),
    );
  }
}
