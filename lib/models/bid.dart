import 'user.dart';

class Bid {
  final int id;
  final User bidder;
  final double amount;
  final bool depositPaid;
  final bool isWinning;
  final DateTime createdAt;

  Bid({
    required this.id,
    required this.bidder,
    required this.amount,
    required this.depositPaid,
    required this.isWinning,
    required this.createdAt,
  });

  factory Bid.fromJson(Map<String, dynamic> json) {
    return Bid(
      id: json['id'] as int,
      bidder: User.fromJson(json['bidder'] as Map<String, dynamic>),
      amount: double.parse(json['amount'] as String),
      depositPaid: json['deposit_paid'] as bool? ?? false,
      isWinning: json['is_winning'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
  Bid copyWith({
  int? id,
  User? bidder,
  double? amount,
  bool? depositPaid,
  bool? isWinning,
  DateTime? createdAt,
}) {
  return Bid(
    id: id ?? this.id,
    bidder: bidder ?? this.bidder,
    amount: amount ?? this.amount,
    depositPaid: depositPaid ?? this.depositPaid,
    isWinning: isWinning ?? this.isWinning,
    createdAt: createdAt ?? this.createdAt,
  );
}
}