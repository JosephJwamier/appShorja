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

/// One movement of money with a direction and a from → to pair — the shape
/// the server builds in `services/wallet_activity.py`.
enum FlowDirection { inward, outward, hold, release, pending, failed }

FlowDirection _direction(String raw) {
  switch (raw) {
    case 'in':
      return FlowDirection.inward;
    case 'out':
      return FlowDirection.outward;
    case 'hold':
      return FlowDirection.hold;
    case 'release':
      return FlowDirection.release;
    case 'failed':
      return FlowDirection.failed;
    default:
      return FlowDirection.pending;
  }
}

class MoneyFlowEntry {
  final String id;
  final String kind;
  final FlowDirection direction;
  final double amount;
  final String status;
  final String title;
  final String from;
  final String to;
  final DateTime occurredAt;
  final String? refType;
  final String? refId;
  final String note;

  const MoneyFlowEntry({
    required this.id,
    required this.kind,
    required this.direction,
    required this.amount,
    required this.status,
    required this.title,
    required this.from,
    required this.to,
    required this.occurredAt,
    this.refType,
    this.refId,
    this.note = '',
  });

  /// Whether this entry ever touches the balance — pending/failed top-ups
  /// are shown for context, not counted.
  bool get counts =>
      direction == FlowDirection.inward || direction == FlowDirection.outward;

  factory MoneyFlowEntry.fromJson(Map<String, dynamic> json) => MoneyFlowEntry(
        id: json['id'].toString(),
        kind: json['kind']?.toString() ?? '',
        direction: _direction(json['direction']?.toString() ?? ''),
        amount: double.tryParse(json['amount'].toString()) ?? 0,
        status: json['status']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        from: json['from']?.toString() ?? '',
        to: json['to']?.toString() ?? '',
        occurredAt: DateTime.tryParse(json['occurred_at']?.toString() ?? '') ?? DateTime.now(),
        refType: json['ref_type']?.toString(),
        refId: json['ref_id']?.toString(),
        note: json['note']?.toString() ?? '',
      );
}

/// The wallet's numbers plus the money in flight around it.
class WalletActivity {
  final double balance;
  final double heldBalance;
  final double availableBalance;

  /// Paid by me for reservations, not yet handed to the seller.
  final double paidWaiting;

  /// Earned as a seller, not yet released to my balance.
  final double earningsWaiting;

  /// Earned as a representative, not yet released.
  final double commissionsWaiting;

  /// Card top-ups the gateway hasn't settled — what the refresh re-asks about.
  final int pendingTopups;
  final List<MoneyFlowEntry> entries;

  const WalletActivity({
    required this.balance,
    required this.heldBalance,
    required this.availableBalance,
    required this.paidWaiting,
    required this.earningsWaiting,
    required this.commissionsWaiting,
    required this.pendingTopups,
    required this.entries,
  });

  factory WalletActivity.fromJson(Map<String, dynamic> json) {
    double toDouble(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;
    final escrow = json['escrow'] as Map<String, dynamic>? ?? const {};
    return WalletActivity(
      balance: toDouble(json['balance']),
      heldBalance: toDouble(json['held_balance']),
      availableBalance: toDouble(json['available_balance']),
      paidWaiting: toDouble(escrow['paid_waiting']),
      earningsWaiting: toDouble(escrow['earnings_waiting']),
      commissionsWaiting: toDouble(escrow['commissions_waiting']),
      pendingTopups: (json['pending_topups'] as num?)?.toInt() ?? 0,
      entries: (json['entries'] as List<dynamic>? ?? const [])
          .map((e) => MoneyFlowEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Outcome of the manual re-sync of unfinished top-ups.
class SyncResult {
  final int checked, settled, stillPending, failed, errors;
  const SyncResult({
    required this.checked,
    required this.settled,
    required this.stillPending,
    required this.failed,
    required this.errors,
  });

  factory SyncResult.fromJson(Map<String, dynamic> json) => SyncResult(
        checked: (json['checked'] as num?)?.toInt() ?? 0,
        settled: (json['settled'] as num?)?.toInt() ?? 0,
        stillPending: (json['still_pending'] as num?)?.toInt() ?? 0,
        failed: (json['failed'] as num?)?.toInt() ?? 0,
        errors: (json['errors'] as num?)?.toInt() ?? 0,
      );

  /// One line for the snackbar after the arrow stops spinning.
  String get message {
    if (checked == 0) return 'تم التحديث — لا عمليات معلّقة';
    final parts = <String>[];
    if (settled > 0) parts.add('اكتملت $settled');
    if (stillPending > 0) parts.add('ما زالت $stillPending بانتظار البوابة');
    if (failed > 0) parts.add('فشلت $failed');
    if (errors > 0) parts.add('تعذّر الاتصال بالبوابة لـ$errors');
    return 'تم التحديث — ${parts.join('، ')}';
  }
}
