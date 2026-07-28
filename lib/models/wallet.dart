class Wallet {
  final double balance;
  final double heldBalance;
  final double availableBalance;
  final DateTime updatedAt;

  const Wallet({
    required this.balance,
    required this.heldBalance,
    required this.availableBalance,
    required this.updatedAt,
  });

  factory Wallet.fromJson(Map<String, dynamic> json) => Wallet(
        balance: double.parse(json['balance'].toString()),
        heldBalance: double.parse(json['held_balance'].toString()),
        availableBalance: double.parse(json['available_balance'].toString()),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}

class Deposit {
  final int id;
  final double amount;
  final String status;
  final String cardLast4;
  final String reference;
  final DateTime createdAt;
  final DateTime? completedAt;

  const Deposit({
    required this.id,
    required this.amount,
    required this.status,
    required this.cardLast4,
    required this.reference,
    required this.createdAt,
    this.completedAt,
  });

  factory Deposit.fromJson(Map<String, dynamic> json) => Deposit(
        id: json['id'] as int,
        amount: double.parse(json['amount'].toString()),
        status: json['status'] as String,
        cardLast4: json['card_last4'] as String,
        reference: json['reference'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        completedAt: json['completed_at'] != null
            ? DateTime.parse(json['completed_at'] as String)
            : null,
      );
}
