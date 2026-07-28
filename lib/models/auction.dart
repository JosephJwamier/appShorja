import 'bid.dart';
import 'product.dart';
import 'user.dart';

class Auction {
  final int id;
  final Product item;
  final double startingPrice;
  final double currentPrice;
  final double minimumIncrement;
  final double bidDeposit;
  final DateTime startTime;
  final DateTime endTime;
  final String status;
  final User? winner;
  final List<Bid> bids;
  final int bidCount;
  final int timeRemaining;

  Auction({
    required this.id,
    required this.item,
    required this.startingPrice,
    required this.currentPrice,
    required this.minimumIncrement,
    required this.bidDeposit,
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.winner,
    required this.bids,
    required this.bidCount,
    required this.timeRemaining,
  });

  bool get isUpcoming => status == 'upcoming';
  bool get isActive => status == 'active' && timeRemaining > 0;
  bool get isEnded => status == 'ended' || (status == 'active' && timeRemaining <= 0);

  factory Auction.fromJson(Map<String, dynamic> json) {
    final itemData = json['item'] as Map<String, dynamic>;
    final bidsList = (json['bids'] as List<dynamic>?) ?? [];

    return Auction(
      id: json['id'] as int,
      item: Product.fromJson(itemData),
      startingPrice: double.parse(json['starting_price'] as String),
      currentPrice: double.parse(json['current_price'] as String),
      minimumIncrement: double.parse(json['minimum_increment'] as String),
      bidDeposit: double.parse(json['bid_deposit'] as String),
      startTime: DateTime.parse(json['start_time'] as String),
      endTime: DateTime.parse(json['end_time'] as String),
      status: json['status'] as String? ?? 'unknown',
      winner: json['winner'] != null
          ? User.fromJson(json['winner'] as Map<String, dynamic>)
          : null,
      bids: bidsList
          .map((b) => Bid.fromJson(b as Map<String, dynamic>))
          .toList(),
      bidCount: json['bid_count'] as int? ?? 0,
      timeRemaining: json['time_remaining'] as int? ?? 0,
    );
  }

  factory Auction.fromDetailJson(Map<String, dynamic> json) => Auction.fromJson(json);
  Auction copyWith({
  int? id,
  Product? item,
  double? startingPrice,
  double? currentPrice,
  double? minimumIncrement,
  double? bidDeposit,
  DateTime? startTime,
  DateTime? endTime,
  String? status,
  User? winner,
  List<Bid>? bids,
  int? bidCount,
  int? timeRemaining,
}) {
  return Auction(
    id: id ?? this.id,
    item: item ?? this.item,
    startingPrice: startingPrice ?? this.startingPrice,
    currentPrice: currentPrice ?? this.currentPrice,
    minimumIncrement: minimumIncrement ?? this.minimumIncrement,
    bidDeposit: bidDeposit ?? this.bidDeposit,
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
    status: status ?? this.status,
    winner: winner ?? this.winner,
    bids: bids ?? this.bids,
    bidCount: bidCount ?? this.bidCount,
    timeRemaining: timeRemaining ?? this.timeRemaining,
  );
}
}