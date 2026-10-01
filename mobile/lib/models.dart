class UserProfile {
  UserProfile({
    required this.id,
    required this.email,
    required this.name,
    required this.currency,
    required this.timezone,
    required this.monthStartDay,
  });

  final String id;
  final String email;
  final String name;
  final String currency;
  final String timezone;
  final int monthStartDay;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        email: json['email'] as String,
        name: json['name'] as String,
        currency: json['currency'] as String? ?? 'LKR',
        timezone: json['timezone'] as String? ?? 'Asia/Colombo',
        monthStartDay: json['month_start_day'] as int? ?? 1,
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
    required this.smsSender,
    required this.openingBalance,
    required this.balance,
    required this.automationsEnabled,
  });

  final String id;
  final String name;
  final String type;
  final String purpose;
  final String bankName;
  final String last4;
  final String smsSender;
  final double openingBalance;
  final double balance;
  final bool automationsEnabled;

  bool get isBusiness => purpose == 'business';

  factory AccountModel.fromJson(Map<String, dynamic> json) => AccountModel(
        id: json['id'] as String,
        name: json['name'] as String,
        type: json['type'] as String,
        purpose: json['purpose'] as String? ?? 'personal',
        bankName: json['bank_name'] as String? ?? '',
        last4: json['last4'] as String? ?? '',
        smsSender: json['sms_sender'] as String? ?? '',
        openingBalance: (json['opening_balance'] as num?)?.toDouble() ?? 0,
        balance: (json['balance'] as num?)?.toDouble() ?? 0,
        automationsEnabled: json['automations_enabled'] as bool? ?? true,
      );
}

class CategoryModel {
  CategoryModel({
    required this.id,
    required this.name,
    required this.kind,
    required this.icon,
    required this.color,
    required this.transactionCount,
  });

  final String id;
  final String name;
  final String kind;
  final String icon;
  final String color;
  final int transactionCount;

  factory CategoryModel.fromJson(Map<String, dynamic> json) => CategoryModel(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: json['kind'] as String,
        icon: json['icon'] as String? ?? 'other',
        color: json['color'] as String? ?? '#9CA3AF',
        transactionCount: json['transaction_count'] as int? ?? 0,
      );
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
    required this.merchant,
    required this.note,
    required this.occurredAt,
    required this.scope,
    required this.source,
    required this.status,
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
  final String merchant;
  final String note;
  final DateTime occurredAt;
  final String scope;
  final String source;
  final String status;

  bool get isBusiness => scope == 'business';

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
        merchant: json['merchant'] as String? ?? '',
        note: json['note'] as String? ?? '',
        occurredAt: DateTime.parse(json['occurred_at'] as String).toLocal(),
        scope: json['scope'] as String? ?? 'personal',
        source: json['source'] as String? ?? 'manual',
        status: json['status'] as String? ?? 'posted',
      );
}

class Spender {
  Spender({
    required this.name,
    required this.icon,
    required this.color,
    required this.amount,
  });

  final String name;
  final String icon;
  final String color;
  final double amount;

  factory Spender.fromJson(Map<String, dynamic> json) => Spender(
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
  });

  final String name;
  final double spentToday;
  final List<AccountModel> accounts;
  final List<Spender> topSpenders;
  final int reviewCount;

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
      );
}

class Slice {
  Slice({
    required this.name,
    required this.icon,
    required this.color,
    required this.amount,
    required this.percent,
  });

  final String name;
  final String icon;
  final String color;
  final double amount;
  final double percent;

  factory Slice.fromJson(Map<String, dynamic> json) => Slice(
        name: json['name'] as String,
        icon: json['icon'] as String? ?? 'other',
        color: json['color'] as String? ?? '#9CA3AF',
        amount: (json['amount'] as num).toDouble(),
        percent: (json['percent'] as num).toDouble(),
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
