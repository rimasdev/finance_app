class UserProfile {
  UserProfile({
    required this.id,
    required this.email,
    required this.name,
    required this.currency,
    required this.timezone,
    required this.monthStartDay,
    this.withdrawalToCash = false,
    this.cashAccountId,
  });

  final String id;
  final String email;
  final String name;
  final String currency;
  final String timezone;
  final int monthStartDay;
  final bool withdrawalToCash;
  final String? cashAccountId;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as String,
    email: json['email'] as String,
    name: json['name'] as String,
    currency: json['currency'] as String? ?? 'LKR',
    timezone: json['timezone'] as String? ?? 'Asia/Colombo',
    monthStartDay: json['month_start_day'] as int? ?? 1,
    withdrawalToCash: json['withdrawal_to_cash'] as bool? ?? false,
    cashAccountId: json['cash_account_id'] as String?,
  );
}

class AccountModel {
  AccountModel({
    required this.id,
    required this.name,
    required this.type,
    required this.purpose,
    required this.bankName,
    required this.last4,
    this.cardLast4s = const [],
    required this.smsSender,
    required this.openingBalance,
    required this.balance,
    required this.automationsEnabled,
    this.preferred = false,
    this.includeInNet = true,
  });

  final String id;
  final String name;
  final String type;
  final String purpose;
  final String bankName;
  final String last4;
  final List<String> cardLast4s;
  final String smsSender;
  final double openingBalance;
  final double balance;
  final bool automationsEnabled;
  final bool preferred;
  final bool includeInNet;

  bool get isBusiness => purpose == 'business';

  factory AccountModel.fromJson(Map<String, dynamic> json) => AccountModel(
    id: json['id'] as String,
    name: json['name'] as String,
    type: json['type'] as String,
    purpose: json['purpose'] as String? ?? 'personal',
    bankName: json['bank_name'] as String? ?? '',
    last4: json['last4'] as String? ?? '',
    cardLast4s: [
      for (final part in json['card_last4s'] as List? ?? []) part.toString(),
    ],
    smsSender: json['sms_sender'] as String? ?? '',
    openingBalance: (json['opening_balance'] as num?)?.toDouble() ?? 0,
    balance: (json['balance'] as num?)?.toDouble() ?? 0,
    automationsEnabled: json['automations_enabled'] as bool? ?? true,
    preferred: json['preferred'] as bool? ?? false,
    includeInNet: json['include_in_net'] as bool? ?? true,
  );
}

class CategoryModel {
  CategoryModel({
    required this.id,
    required this.name,
    required this.kind,
    required this.icon,
    required this.color,
    this.parentId,
    this.scope = 'personal',
    required this.transactionCount,
  });

  final String id;
  final String name;
  final String kind;
  final String icon;
  final String color;
  final String? parentId;
  final String scope;
  final int transactionCount;

  factory CategoryModel.fromJson(Map<String, dynamic> json) => CategoryModel(
    id: json['id'] as String,
    name: json['name'] as String,
    kind: json['kind'] as String,
    icon: json['icon'] as String? ?? 'other',
    color: json['color'] as String? ?? '#9CA3AF',
    parentId: json['parent_id'] as String?,
    scope: json['scope'] as String? ?? 'personal',
    transactionCount: json['transaction_count'] as int? ?? 0,
  );

  CategoryModel copyWith({String? parentId, bool clearParent = false}) {
    return CategoryModel(
      id: id,
      name: name,
      kind: kind,
      icon: icon,
      color: color,
      parentId: clearParent ? null : (parentId ?? this.parentId),
      scope: scope,
      transactionCount: transactionCount,
    );
  }
}

class PayeeModel {
  PayeeModel({required this.id, required this.name, required this.detail, required this.label});

  final String id;
  final String name;
  final String detail;
  final String label;

  factory PayeeModel.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String? ?? '';
    final detail = json['detail'] as String? ?? '';
    final label = json['label'] as String? ?? (detail.isEmpty ? name : '$name · $detail');
    return PayeeModel(id: json['id'] as String, name: name, detail: detail, label: label);
  }
}

class TxnModel {
  TxnModel({
    required this.id,
    required this.accountId,
    required this.accountName,
    required this.transferAccountId,
    required this.transferAccountName,
    required this.categoryId,
    required this.categoryName,
    required this.categoryIcon,
    required this.categoryColor,
    required this.direction,
    required this.amount,
    this.currency = 'LKR',
    this.fxAmount,
    this.bankCharge = 0,
    required this.merchant,
    required this.note,
    this.tags = const [],
    this.paymentType = 'Cash',
    this.warranty = '',
    this.clearStatus = 'cleared',
    this.place = '',
    this.photo = '',
    required this.occurredAt,
    required this.scope,
    required this.source,
    required this.status,
    this.hidden = false,
    this.cardLast4 = '',
    this.recurringId = '',
  });

  final String id;
  final String? accountId;
  final String accountName;
  final String? transferAccountId;
  final String transferAccountName;
  final String? categoryId;
  final String categoryName;
  final String categoryIcon;
  final String categoryColor;
  final String direction;
  final double amount;
  final String currency;
  final double? fxAmount;
  final double bankCharge;
  final String merchant;
  final String note;
  final List<String> tags;
  final String paymentType;
  final String warranty;
  final String clearStatus;
  final String place;
  final String photo;
  final DateTime occurredAt;
  final String scope;
  final String source;
  final String status;
  final bool hidden;
  final String cardLast4;
  final String recurringId;

  bool get isBusiness => scope == 'business';

  String get title {
    if (merchant.trim().isNotEmpty) return merchant;
    if (categoryName.trim().isNotEmpty) return categoryName;
    if (direction == 'income') return 'Income';
    if (direction == 'transfer') return 'Transfer';
    return 'Expense';
  }

  factory TxnModel.fromJson(Map<String, dynamic> json) => TxnModel(
    id: json['id'] as String,
    accountId: json['account_id'] as String?,
    accountName: json['account_name'] as String? ?? '',
    transferAccountId: json['transfer_account_id'] as String?,
    transferAccountName: json['transfer_account_name'] as String? ?? '',
    categoryId: json['category_id'] as String?,
    categoryName: json['category_name'] as String? ?? '',
    categoryIcon: json['category_icon'] as String? ?? 'other',
    categoryColor: json['category_color'] as String? ?? '#9CA3AF',
    direction: json['direction'] as String,
    amount: (json['amount'] as num).toDouble(),
    currency: (json['currency'] as String? ?? 'LKR').toUpperCase(),
    fxAmount: (json['fx_amount'] as num?)?.toDouble(),
    bankCharge: (json['bank_charge'] as num?)?.toDouble() ?? 0,
    merchant: json['merchant'] as String? ?? '',
    note: json['note'] as String? ?? '',
    tags: [
      for (final tag in (json['tags'] as String? ?? '').split(','))
        if (tag.trim().isNotEmpty) tag.trim(),
    ],
    paymentType: json['payment_type'] as String? ?? 'Cash',
    warranty: json['warranty'] as String? ?? '',
    clearStatus: json['clear_status'] as String? ?? 'cleared',
    place: json['place'] as String? ?? '',
    photo: json['photo'] as String? ?? '',
    occurredAt: DateTime.parse(json['occurred_at'] as String).toLocal(),
    scope: json['scope'] as String? ?? 'personal',
    source: json['source'] as String? ?? 'manual',
    status: json['status'] as String? ?? 'posted',
    hidden: json['hidden'] as bool? ?? false,
    cardLast4: json['card_last4'] as String? ?? '',
    recurringId: json['recurring_id'] as String? ?? '',
  );
}

class Spender {
  Spender({
    this.categoryId,
    required this.name,
    required this.icon,
    required this.color,
    required this.amount,
  });

  final String? categoryId;
  final String name;
  final String icon;
  final String color;
  final double amount;

  factory Spender.fromJson(Map<String, dynamic> json) => Spender(
    categoryId: json['category_id'] as String?,
    name: json['name'] as String,
    icon: json['icon'] as String? ?? 'other',
    color: json['color'] as String? ?? '#9CA3AF',
    amount: (json['amount'] as num).toDouble(),
  );
}

class DashboardData {
  DashboardData({
    required this.name,
    required this.spentToday,
    required this.accounts,
    required this.topSpenders,
    required this.reviewCount,
    this.smsCount = 0,
  });

  final String name;
  final double spentToday;
  final List<AccountModel> accounts;
  final List<Spender> topSpenders;
  final int reviewCount;
  final int smsCount;

  factory DashboardData.fromJson(Map<String, dynamic> json) => DashboardData(
    name: json['name'] as String? ?? '',
    spentToday: (json['spent_today'] as num?)?.toDouble() ?? 0,
    accounts: [
      for (final row in json['accounts'] as List? ?? [])
        AccountModel.fromJson(row as Map<String, dynamic>),
    ],
    topSpenders: [
      for (final row in json['top_spenders'] as List? ?? [])
        Spender.fromJson(row as Map<String, dynamic>),
    ],
    reviewCount: json['review_count'] as int? ?? 0,
    smsCount: json['sms_count'] as int? ?? 0,
  );
}

class Slice {
  Slice({
    this.categoryId,
    required this.name,
    required this.icon,
    required this.color,
    required this.amount,
    required this.percent,
    this.children = const [],
  });

  final String? categoryId;
  final String name;
  final String icon;
  final String color;
  final double amount;
  final double percent;
  final List<Slice> children;

  factory Slice.fromJson(Map<String, dynamic> json) => Slice(
    categoryId: json['category_id'] as String?,
    name: json['name'] as String,
    icon: json['icon'] as String? ?? 'other',
    color: json['color'] as String? ?? '#9CA3AF',
    amount: (json['amount'] as num).toDouble(),
    percent: (json['percent'] as num).toDouble(),
    children: [
      for (final row in json['children'] as List? ?? [])
        Slice.fromJson(row as Map<String, dynamic>),
    ],
  );
}

class InsightsData {
  InsightsData({
    required this.label,
    required this.from,
    required this.to,
    required this.total,
    required this.slices,
  });

  final String label;
  final DateTime from;
  final DateTime to;
  final double total;
  final List<Slice> slices;

  factory InsightsData.fromJson(Map<String, dynamic> json) => InsightsData(
    label: json['label'] as String? ?? '',
    from: DateTime.parse(json['from'] as String),
    to: DateTime.parse(json['to'] as String),
    total: (json['total'] as num?)?.toDouble() ?? 0,
    slices: [
      for (final row in json['slices'] as List? ?? [])
        Slice.fromJson(row as Map<String, dynamic>),
    ],
  );
}

class TimelineDay {
  TimelineDay({required this.date, required this.total, required this.items});

  final DateTime date;
  final double total;
  final List<TxnModel> items;

  factory TimelineDay.fromJson(Map<String, dynamic> json) => TimelineDay(
    date: DateTime.parse(json['date'] as String),
    total: (json['total'] as num).toDouble(),
    items: [
      for (final row in json['items'] as List? ?? [])
        TxnModel.fromJson(row as Map<String, dynamic>),
    ],
  );
}

class TimelineData {
  TimelineData({
    required this.label,
    required this.from,
    required this.to,
    required this.income,
    required this.expenses,
    required this.net,
    required this.days,
  });

  final String label;
  final DateTime from;
  final DateTime to;
  final double income;
  final double expenses;
  final double net;
  final List<TimelineDay> days;

  factory TimelineData.fromJson(Map<String, dynamic> json) => TimelineData(
    label: json['label'] as String? ?? '',
    from: DateTime.parse(json['from'] as String),
    to: DateTime.parse(json['to'] as String),
    income: (json['income'] as num?)?.toDouble() ?? 0,
    expenses: (json['expenses'] as num?)?.toDouble() ?? 0,
    net: (json['net'] as num?)?.toDouble() ?? 0,
    days: [
      for (final row in json['days'] as List? ?? [])
        TimelineDay.fromJson(row as Map<String, dynamic>),
    ],
  );
}

String recurringFxNote({String provider = '', String currency = 'LKR'}) {
  final payment = provider.trim().replaceAll('|', '/');
  final code = currency.trim().toUpperCase();
  if (payment.isEmpty && (code.isEmpty || code == 'LKR')) return '';
  return 'fx:$payment|${code.isEmpty ? 'LKR' : code}';
}

class RecurringModel {
  RecurringModel({
    required this.id,
    required this.kind,
    required this.name,
    required this.provider,
    required this.currency,
    required this.amount,
    required this.accountId,
    required this.accountName,
    required this.interval,
    required this.nextOn,
    required this.installmentsTotal,
    required this.installmentsDone,
    required this.active,
    required this.note,
  });

  final String id;
  final String kind;
  final String name;
  final String provider;
  final String currency;
  final double amount;
  final String? accountId;
  final String accountName;
  final String interval;
  final String nextOn;
  final int? installmentsTotal;
  final int installmentsDone;
  final bool active;
  final String note;

  factory RecurringModel.fromJson(Map<String, dynamic> json) {
    final rawNote = json['note'] as String? ?? '';
    var provider = (json['provider'] as String? ?? '').trim();
    var currency = (json['currency'] as String? ?? '').trim().toUpperCase();
    var note = rawNote;
    if (rawNote.startsWith('fx:')) {
      final parts = rawNote.substring(3).split('|');
      if (provider.isEmpty && parts.isNotEmpty) provider = parts.first.trim();
      if ((currency.isEmpty || currency == 'LKR') && parts.length > 1) {
        final coded = parts[1].trim().toUpperCase();
        if (coded.isNotEmpty) currency = coded;
      }
      note = '';
    }
    if (currency.isEmpty) currency = 'LKR';
    return RecurringModel(
      id: json['id'] as String,
      kind: json['kind'] as String? ?? 'repeat',
      name: json['name'] as String? ?? '',
      provider: provider,
      currency: currency,
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      accountId: json['account_id'] as String?,
      accountName: json['account_name'] as String? ?? '',
      interval: json['interval'] as String? ?? 'monthly',
      nextOn: json['next_on'] as String? ?? '',
      installmentsTotal: json['installments_total'] as int?,
      installmentsDone: json['installments_done'] as int? ?? 0,
      active: json['active'] as bool? ?? true,
      note: note,
    );
  }
}

class BudgetModel {
  BudgetModel({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.categoryName,
    required this.categoryIcon,
    required this.categoryColor,
    required this.accountId,
    required this.accountName,
    required this.limitAmount,
    required this.spent,
    required this.remaining,
  });

  final String id;
  final String name;
  final String? categoryId;
  final String categoryName;
  final String categoryIcon;
  final String categoryColor;
  final String? accountId;
  final String accountName;
  final double limitAmount;
  final double spent;
  final double remaining;

  factory BudgetModel.fromJson(Map<String, dynamic> json) => BudgetModel(
    id: json['id'] as String,
    name: json['name'] as String,
    categoryId: json['category_id'] as String?,
    categoryName: json['category_name'] as String? ?? 'All categories',
    categoryIcon: json['category_icon'] as String? ?? 'other',
    categoryColor: json['category_color'] as String? ?? '#9CA3AF',
    accountId: json['account_id'] as String?,
    accountName: json['account_name'] as String? ?? 'All accounts',
    limitAmount: (json['limit_amount'] as num).toDouble(),
    spent: (json['spent'] as num?)?.toDouble() ?? 0,
    remaining: (json['remaining'] as num?)?.toDouble() ?? 0,
  );
}

class LoanModel {
  LoanModel({
    required this.id,
    required this.kind,
    required this.partyKind,
    required this.partyName,
    required this.counterpartyAccountId,
    required this.counterpartyAccountName,
    required this.accountId,
    required this.accountName,
    required this.amount,
    required this.repaid,
    required this.remaining,
    required this.dueOn,
    required this.note,
    required this.settled,
  });

  final String id;
  final String kind;
  final String partyKind;
  final String partyName;
  final String? counterpartyAccountId;
  final String counterpartyAccountName;
  final String accountId;
  final String accountName;
  final double amount;
  final double repaid;
  final double remaining;
  final String dueOn;
  final String note;
  final bool settled;

  bool get isLend => kind == 'lend';

  factory LoanModel.fromJson(Map<String, dynamic> json) => LoanModel(
    id: json['id'] as String,
    kind: json['kind'] as String? ?? 'lend',
    partyKind: json['party_kind'] as String? ?? 'person',
    partyName: json['party_name'] as String? ?? '',
    counterpartyAccountId: json['counterparty_account_id'] as String?,
    counterpartyAccountName: json['counterparty_account_name'] as String? ?? '',
    accountId: json['account_id'] as String? ?? '',
    accountName: json['account_name'] as String? ?? '',
    amount: (json['amount'] as num?)?.toDouble() ?? 0,
    repaid: (json['repaid'] as num?)?.toDouble() ?? 0,
    remaining: (json['remaining'] as num?)?.toDouble() ?? 0,
    dueOn: json['due_on'] as String? ?? '',
    note: json['note'] as String? ?? '',
    settled: json['settled'] as bool? ?? false,
  );
}
