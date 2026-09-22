// دفتر الحساب — mirrors the `ledger` app on the server.

double _d(dynamic v) => v == null ? 0 : (double.tryParse(v.toString()) ?? 0);
double? _dn(dynamic v) => v == null ? null : double.tryParse(v.toString());
int _i(dynamic v) => v == null ? 0 : (int.tryParse(v.toString()) ?? 0);

/// Entry kinds, with the Arabic the merchant sees. Order matters: it's the
/// order the quick-entry sheet lists them in.
enum LedgerKind {
  saleCash('sale_cash', 'بيعة نقدية', true),
  saleCredit('sale_credit', 'بيع بالدين', true),
  saleApp('sale_app', 'بيع عبر التطبيق', true),
  paymentIn('payment_in', 'تسديد من زبون', true),
  expense('expense', 'مصروف', false),
  purchase('purchase', 'شراء بالدين', false),
  paymentOut('payment_out', 'تسديد لمورّد', false);

  final String value;
  final String label;
  /// Money coming in (true) or going out (false) — drives colour/sign.
  final bool isIn;
  const LedgerKind(this.value, this.label, this.isIn);

  static LedgerKind fromValue(String v) =>
      LedgerKind.values.firstWhere((k) => k.value == v, orElse: () => LedgerKind.saleCash);

  bool get isSale => this == saleCash || this == saleCredit || this == saleApp;

  /// Which contact kind this entry needs, or null when none.
  ContactKind? get contactKind => switch (this) {
        saleCredit || paymentIn => ContactKind.customer,
        purchase || paymentOut => ContactKind.supplier,
        _ => null,
      };

  /// Kinds the merchant may write by hand.
  static const manual = [saleCash, saleCredit, paymentIn, expense, purchase, paymentOut];
}

enum ContactKind {
  customer('customer', 'زبون'),
  supplier('supplier', 'مورّد');

  final String value;
  final String label;
  const ContactKind(this.value, this.label);
  static ContactKind fromValue(String v) =>
      v == 'supplier' ? ContactKind.supplier : ContactKind.customer;
}

const expenseCategories = <String, String>{
  'rent': 'إيجار',
  'power': 'كهرباء ومولّدة',
  'salaries': 'رواتب',
  'transport': 'نقل وتوصيل',
  'goods': 'شراء بضاعة',
  'other': 'أخرى',
};

class LedgerContact {
  final int id;
  final ContactKind kind;
  final String name;
  final String phone;
  final String notes;
  final bool isArchived;
  /// Positive = open amount on this contact (they owe me / I owe them).
  final double balance;

  const LedgerContact({
    required this.id,
    required this.kind,
    required this.name,
    this.phone = '',
    this.notes = '',
    this.isArchived = false,
    this.balance = 0,
  });

  factory LedgerContact.fromJson(Map<String, dynamic> j) => LedgerContact(
        id: _i(j['id']),
        kind: ContactKind.fromValue(j['kind']?.toString() ?? 'customer'),
        name: j['name']?.toString() ?? '',
        phone: j['phone']?.toString() ?? '',
        notes: j['notes']?.toString() ?? '',
        isArchived: j['is_archived'] == true,
        balance: _d(j['balance']),
      );
}

class LedgerEntry {
  final int id;
  final LedgerKind kind;
  final double amount;
  final int? contactId;
  final String? contactName;
  final String note;
  final DateTime occurredAt;
  final String expenseCategory;
  final int? itemId;
  final String? itemTitle;
  final int? variantId;
  final String? variantLabel;
  final int? quantity;
  final double? costAmount;
  final String? receiptUrl;
  final bool fromApp;
  final int? reservationId;
  final bool isVoid;
  final String voidReason;

  const LedgerEntry({
    required this.id,
    required this.kind,
    required this.amount,
    required this.occurredAt,
    this.contactId,
    this.contactName,
    this.note = '',
    this.expenseCategory = '',
    this.itemId,
    this.itemTitle,
    this.variantId,
    this.variantLabel,
    this.quantity,
    this.costAmount,
    this.receiptUrl,
    this.fromApp = false,
    this.reservationId,
    this.isVoid = false,
    this.voidReason = '',
  });

  factory LedgerEntry.fromJson(Map<String, dynamic> j) => LedgerEntry(
        id: _i(j['id']),
        kind: LedgerKind.fromValue(j['kind']?.toString() ?? ''),
        amount: _d(j['amount']),
        contactId: j['contact'] == null ? null : _i(j['contact']),
        contactName: j['contact_name']?.toString(),
        note: j['note']?.toString() ?? '',
        occurredAt: DateTime.tryParse(j['occurred_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
        expenseCategory: j['expense_category']?.toString() ?? '',
        itemId: j['item'] == null ? null : _i(j['item']),
        itemTitle: j['item_title']?.toString(),
        variantId: j['variant'] == null ? null : _i(j['variant']),
        variantLabel: j['variant_label']?.toString(),
        quantity: j['quantity'] == null ? null : _i(j['quantity']),
        costAmount: _dn(j['cost_amount']),
        receiptUrl: j['receipt_url']?.toString(),
        fromApp: j['source'] == 'app',
        reservationId: j['reservation'] == null ? null : _i(j['reservation']),
        isVoid: j['is_void'] == true,
        voidReason: j['void_reason']?.toString() ?? '',
      );

  /// One line the list can show under the amount.
  String get subtitle {
    final parts = <String>[];
    if (contactName != null && contactName!.isNotEmpty) parts.add(contactName!);
    if (itemTitle != null && itemTitle!.isNotEmpty) {
      var s = itemTitle!;
      if (variantLabel != null && variantLabel!.isNotEmpty) s += ' — $variantLabel';
      if (quantity != null && quantity! > 1) s += ' ×$quantity';
      parts.add(s);
    }
    if (kind == LedgerKind.expense && expenseCategory.isNotEmpty) {
      parts.add(expenseCategories[expenseCategory] ?? expenseCategory);
    }
    if (note.isNotEmpty) parts.add(note);
    return parts.join(' · ');
  }
}

class DailyPoint {
  final DateTime day;
  final double local;
  final double app;
  final double out;
  const DailyPoint({required this.day, required this.local, required this.app, required this.out});
  double get sales => local + app;

  factory DailyPoint.fromJson(Map<String, dynamic> j) => DailyPoint(
        day: DateTime.tryParse(j['day']?.toString() ?? '') ?? DateTime.now(),
        local: _d(j['local']),
        app: _d(j['app']),
        out: _d(j['out']),
      );
}

class LedgerSummary {
  final DateTime start;
  final DateTime end;
  final double revenue;
  final double salesCash;
  final double salesCredit;
  final double salesApp;
  final int salesCount;
  final double paymentsIn;
  final double expenses;
  final double purchases;
  final double paymentsOut;
  final double net;
  final double cashIn;
  final double cashOut;
  final double costOfSales;
  final double costedRevenue;
  /// null when no sale in the period had a known cost.
  final double? grossProfit;
  final Map<String, double> expensesByCategory;
  final List<DailyPoint> daily;

  const LedgerSummary({
    required this.start,
    required this.end,
    required this.revenue,
    required this.salesCash,
    required this.salesCredit,
    required this.salesApp,
    required this.salesCount,
    required this.paymentsIn,
    required this.expenses,
    required this.purchases,
    required this.paymentsOut,
    required this.net,
    required this.cashIn,
    required this.cashOut,
    required this.costOfSales,
    required this.costedRevenue,
    required this.grossProfit,
    required this.expensesByCategory,
    required this.daily,
  });

  factory LedgerSummary.fromJson(Map<String, dynamic> j) => LedgerSummary(
        start: DateTime.tryParse(j['start']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
        end: DateTime.tryParse(j['end']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
        revenue: _d(j['revenue']),
        salesCash: _d(j['sales_cash']),
        salesCredit: _d(j['sales_credit']),
        salesApp: _d(j['sales_app']),
        salesCount: _i(j['sales_count']),
        paymentsIn: _d(j['payments_in']),
        expenses: _d(j['expenses']),
        purchases: _d(j['purchases']),
        paymentsOut: _d(j['payments_out']),
        net: _d(j['net']),
        cashIn: _d(j['cash_in']),
        cashOut: _d(j['cash_out']),
        costOfSales: _d(j['cost_of_sales']),
        costedRevenue: _d(j['costed_revenue']),
        grossProfit: _dn(j['gross_profit']),
        expensesByCategory: {
          for (final c in (j['expenses_by_category'] as List<dynamic>? ?? const []))
            (c['expense_category']?.toString() ?? 'other'): _d(c['total']),
        },
        daily: (j['daily'] as List<dynamic>? ?? const [])
            .map((e) => DailyPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class LowStockVariant {
  final int variantId;
  final int itemId;
  final String itemTitle;
  final String label;
  final int quantity;
  const LowStockVariant({
    required this.variantId,
    required this.itemId,
    required this.itemTitle,
    required this.label,
    required this.quantity,
  });
  factory LowStockVariant.fromJson(Map<String, dynamic> j) => LowStockVariant(
        variantId: _i(j['id']),
        itemId: _i(j['item_id']),
        itemTitle: j['item_title']?.toString() ?? '',
        label: j['label']?.toString() ?? '',
        quantity: _i(j['quantity']),
      );
}

class TopItem {
  final int itemId;
  final String title;
  final int units;
  final double total;
  const TopItem({required this.itemId, required this.title, required this.units, required this.total});
  factory TopItem.fromJson(Map<String, dynamic> j) => TopItem(
        itemId: _i(j['item_id']),
        title: j['item__title']?.toString() ?? '',
        units: _i(j['units']),
        total: _d(j['total']),
      );
}

class StoreDashboard {
  final String periodKey;
  final LedgerSummary summary;
  final double previousRevenue;
  final double previousExpenses;
  final double previousNet;
  final int previousSalesCount;
  final double receivables;
  final double payables;
  final int debtorsCount;
  final List<LedgerContact> topDebtors;
  final List<LedgerContact> topCreditors;
  final int activeItems;
  final int soldOutItems;
  final List<LowStockVariant> lowStock;
  final int pendingOrders;
  final int awaitingHandover;
  final int followers;
  final double rating;
  final List<TopItem> topItems;

  const StoreDashboard({
    required this.periodKey,
    required this.summary,
    required this.previousRevenue,
    required this.previousExpenses,
    required this.previousNet,
    required this.previousSalesCount,
    required this.receivables,
    required this.payables,
    required this.debtorsCount,
    required this.topDebtors,
    required this.topCreditors,
    required this.activeItems,
    required this.soldOutItems,
    required this.lowStock,
    required this.pendingOrders,
    required this.awaitingHandover,
    required this.followers,
    required this.rating,
    required this.topItems,
  });

  factory StoreDashboard.fromJson(Map<String, dynamic> j) {
    final prev = j['previous'] as Map<String, dynamic>? ?? const {};
    final bal = j['balances'] as Map<String, dynamic>? ?? const {};
    final stock = j['stock'] as Map<String, dynamic>? ?? const {};
    final orders = j['orders'] as Map<String, dynamic>? ?? const {};
    return StoreDashboard(
      periodKey: (j['period'] as Map<String, dynamic>?)?['key']?.toString() ?? 'month',
      summary: LedgerSummary.fromJson(j['summary'] as Map<String, dynamic>),
      previousRevenue: _d(prev['revenue']),
      previousExpenses: _d(prev['expenses']),
      previousNet: _d(prev['net']),
      previousSalesCount: _i(prev['sales_count']),
      receivables: _d(bal['receivables']),
      payables: _d(bal['payables']),
      debtorsCount: _i(bal['debtors_count']),
      topDebtors: (bal['top_debtors'] as List<dynamic>? ?? const [])
          .map((e) => LedgerContact.fromJson(e as Map<String, dynamic>))
          .toList(),
      topCreditors: (bal['top_creditors'] as List<dynamic>? ?? const [])
          .map((e) => LedgerContact.fromJson(e as Map<String, dynamic>))
          .toList(),
      activeItems: _i(stock['active_items']),
      soldOutItems: _i(stock['sold_out_items']),
      lowStock: (stock['low_stock'] as List<dynamic>? ?? const [])
          .map((e) => LowStockVariant.fromJson(e as Map<String, dynamic>))
          .toList(),
      pendingOrders: _i(orders['pending']),
      awaitingHandover: _i(orders['awaiting_handover']),
      followers: _i(j['followers']),
      rating: _d(j['rating']),
      topItems: (j['top_items'] as List<dynamic>? ?? const [])
          .map((e) => TopItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class StatementRow {
  final LedgerEntry entry;
  final double runningBalance;
  const StatementRow({required this.entry, required this.runningBalance});
  factory StatementRow.fromJson(Map<String, dynamic> j) => StatementRow(
        entry: LedgerEntry.fromJson(j['entry'] as Map<String, dynamic>),
        runningBalance: _d(j['running_balance']),
      );
}

class ContactStatement {
  final LedgerContact contact;
  final double balance;
  final List<StatementRow> rows;
  const ContactStatement({required this.contact, required this.balance, required this.rows});
  factory ContactStatement.fromJson(Map<String, dynamic> j) => ContactStatement(
        contact: LedgerContact.fromJson(j['contact'] as Map<String, dynamic>),
        balance: _d(j['balance']),
        rows: (j['rows'] as List<dynamic>? ?? const [])
            .map((e) => StatementRow.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
