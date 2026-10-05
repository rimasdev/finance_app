import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../banks.dart';
import '../format.dart';
import '../fx.dart';
import '../icons.dart';
import '../models.dart';
import '../store.dart';
import '../subscriptions.dart';
import '../theme.dart';
import '../widgets.dart';
import 'payee_screen.dart';

class _CategoryGroup {
  _CategoryGroup(this.parent, this.children);

  final CategoryModel parent;
  final List<CategoryModel> children;
}

List<_CategoryGroup> _categoryGroups(Iterable<CategoryModel> categories) {
  final list = categories.toList();
  final known = {for (final category in list) category.id};
  final children = <String, List<CategoryModel>>{};
  final parents = <CategoryModel>[];
  for (final category in list) {
    final parentId = category.parentId;
    if (parentId != null && parentId.isNotEmpty && known.contains(parentId)) {
      children.putIfAbsent(parentId, () => []).add(category);
    } else {
      parents.add(category);
    }
  }
  return [
    for (final parent in parents) _CategoryGroup(parent, children[parent.id] ?? const []),
  ];
}

class TransactionFormScreen extends StatefulWidget {
  const TransactionFormScreen({super.key, this.existing});

  final TxnModel? existing;

  @override
  State<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends State<TransactionFormScreen> {
  final _amount = TextEditingController();
  final _settled = TextEditingController();
  final _merchant = TextEditingController();
  String _currency = 'LKR';
  double? _fxAmount;
  String _recurringId = '';
  var _settledTouched = false;
  String _location = '';
  final _note = TextEditingController();
  final _tag = TextEditingController();
  final _charge = TextEditingController();
  String _direction = 'expense';
  String? _accountId;
  String? _transferId;
  String? _categoryId;
  bool _business = false;
  bool _hidden = false;
  bool _details = false;
  final List<String> _tags = [];
  String _paymentType = 'Cash';
  String _warranty = '';
  String _clearStatus = 'cleared';
  String _place = '';
  String _photo = '';
  String? _repeatKind;
  String? _provider;
  int _installments = 12;
  DateTime _when = DateTime.now();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing == null) return;
    _direction =
        existing.direction == 'income' || existing.direction == 'transfer'
        ? existing.direction
        : 'expense';
    _currency = existing.currency.isEmpty ? 'LKR' : existing.currency;
    _fxAmount = existing.fxAmount;
    _recurringId = existing.recurringId;
    if (_currency != 'LKR' && existing.fxAmount != null) {
      _amount.text = groupedAmount(existing.fxAmount!);
      _settled.text = groupedAmount(existing.amount);
    } else {
      _amount.text = groupedAmount(existing.amount);
    }
    _location = existing.merchant;
    _merchant.text = existing.merchant;
    _note.text = existing.note;
    _tags.addAll(existing.tags);
    _paymentType = existing.paymentType;
    _warranty = existing.warranty;
    _clearStatus = existing.clearStatus;
    _place = existing.place;
    _photo = existing.photo;
    if (existing.bankCharge > 0) {
      _charge.text = existing.bankCharge.toStringAsFixed(2);
    }
    _accountId = existing.accountId;
    _transferId = existing.transferAccountId;
    _categoryId = existing.categoryId;
    _hidden = existing.hidden;
    _business = existing.scope == 'business';
    _details = existing.hidden || existing.scope == 'business';
    _when = existing.occurredAt;
  }

  void _preferCash(FolioStore store) {
    final cash = [
      for (final account in store.accounts)
        if (account.type == 'cash' && account.id != _accountId) account,
    ];
    final preferred = store.me?.cashAccountId;
    if (preferred != null && cash.any((account) => account.id == preferred)) {
      _transferId = preferred;
      return;
    }
    if (_transferId != null &&
        cash.any((account) => account.id == _transferId)) {
      return;
    }
    _transferId = cash.firstOrNull?.id;
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    setState(() => _busy = true);
    try {
      await context.read<FolioStore>().deleteTransaction(existing.id);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _settled.dispose();
    _merchant.dispose();
    _note.dispose();
    _tag.dispose();
    _charge.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final store = context.read<FolioStore>();
    final face = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    final foreign = _currency != 'LKR' && (_fxAmount != null || widget.existing != null);
    final settled = double.tryParse(_settled.text.trim().replaceAll(',', ''));
    final amount = foreign ? settled : face;
    final description = (_merchant.text.trim().isNotEmpty ? _merchant.text : _location).trim();
    final charge =
        double.tryParse(_charge.text.trim().replaceAll(',', '')) ?? 0;
    if (_accountId == null || face == null || face <= 0) {
      showError(context, Exception('Add an amount and an account'));
      return;
    }
    if (foreign && (amount == null || amount <= 0)) {
      showError(context, Exception('Add the rupee amount taken from the account'));
      return;
    }
    if (_repeatKind != null && description.isEmpty) {
      showError(context, Exception('Add a location for this repeat'));
      return;
    }
    if (_direction == 'transfer' &&
        (_transferId == null || _transferId == _accountId)) {
      showError(context, Exception('Pick a different account to transfer to'));
      return;
    }
    if (_direction != 'transfer' && (_categoryId == null || _categoryId!.isEmpty)) {
      showError(context, Exception('Choose a category'));
      return;
    }
    if (charge < 0) {
      showError(context, Exception('Bank charges cannot be negative'));
      return;
    }
    final body = {
      'account_id': _accountId,
      'direction': _direction,
      'amount': amount,
      if (foreign) 'fx_amount': face,
      'merchant': _direction == 'transfer' && description.isEmpty
          ? 'Transfer'
          : description,
      'note': _note.text.trim(),
      'tags': _tags.join(', '),
      'payment_type': _paymentType,
      'warranty': _warranty,
      'clear_status': _clearStatus,
      'place': _place,
      'photo': _photo,
      'occurred_at': _when.toUtc().toIso8601String(),
      'scope': _business ? 'business' : 'personal',
      'hidden': _hidden,
      'category_id': _direction == 'transfer' ? null : _categoryId,
      if (_direction == 'transfer') 'transfer_account_id': _transferId,
      if (_direction == 'transfer') 'bank_charge': charge,
    };
    setState(() => _busy = true);
    try {
      final existing = widget.existing;
      if (existing == null) {
        await store.createTransaction(body);
        if (_repeatKind != null && _direction != 'transfer') {
          final next = DateTime(_when.year, _when.month + 1, _when.day);
          final provider = _repeatKind == 'subscription' ? '' : (_provider ?? '');
          await store.createRecurring({
            'kind': _repeatKind,
            'name': body['merchant'],
            'provider': provider,
            'currency': 'LKR',
            'amount': amount,
            'account_id': _accountId,
            'interval': 'monthly',
            'next_on': next.toIso8601String().substring(0, 10),
            'note': recurringFxNote(provider: provider),
            if (_repeatKind == 'installment') 'installments_total': _installments,
          });
        }
      } else {
        await store.updateTransaction(existing.id, body);
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _addTag([String? preset]) {
    final tag = (preset ?? _tag.text).trim();
    if (tag.isEmpty || _tags.length >= 8) return;
    if (_tags.any((item) => item.toLowerCase() == tag.toLowerCase())) {
      if (preset == null) _tag.clear();
      return;
    }
    _tags.add(tag);
    if (preset == null) _tag.clear();
  }

  List<String> _knownTags(FolioStore store) {
    final seen = <String>{};
    final tags = <String>[];
    void add(String raw) {
      final tag = raw.trim();
      if (tag.isEmpty || !seen.add(tag.toLowerCase())) return;
      tags.add(tag);
    }
    for (final day in store.timeline?.days ?? const <TimelineDay>[]) {
      for (final txn in day.items) {
        for (final tag in txn.tags) {
          add(tag);
        }
      }
    }
    for (final txn in store.review) {
      for (final tag in txn.tags) {
        add(tag);
      }
    }
    return tags;
  }

  String _iconForCategory(String name) {
    final key = name.toLowerCase();
    if (key.contains('grocer')) return 'groceries';
    if (key.contains('spice')) return 'spices';
    if (key.contains('shop')) return 'shopping';
    if (key.contains('dining') || key.contains('food')) return 'dining';
    return 'other';
  }

  BudgetModel? _budgetFor(FolioStore store, String? categoryId) {
    if (categoryId == null) return null;
    final own = store.budgets.where((budget) => budget.categoryId == categoryId).firstOrNull;
    if (own != null) return own;
    final category = store.categories.where((item) => item.id == categoryId).firstOrNull;
    final parentId = category?.parentId;
    if (parentId == null) return null;
    return store.budgets.where((budget) => budget.categoryId == parentId).firstOrNull;
  }

  Future<void> _addCategory(String kind) async {
    final created = await showDialog<String>(
      context: context,
      builder: (context) => const _TextPrompt(title: 'New category', hint: 'Groceries, Spices, Shopping'),
    );
    if (created == null || created.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      final store = context.read<FolioStore>();
      await store.createCategory(created, kind, icon: _iconForCategory(created));
      final match = store.categories
          .where((category) => category.kind == kind && category.name.toLowerCase() == created.toLowerCase())
          .firstOrNull;
      if (match != null && mounted) setState(() => _categoryId = match.id);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickRepeat() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: FolioColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Repeat type',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              for (final entry in const [
                ('repeat', 'Repeat', Icons.event_repeat),
                ('installment', 'Installment', Icons.receipt_long_outlined),
                ('subscription', 'Subscription', Icons.subscriptions_outlined),
              ]) ...[
                const SizedBox(height: 8),
                FolioCard(
                  onTap: () => Navigator.pop(context, entry.$1),
                  child: Row(
                    children: [
                      Icon(entry.$3, color: FolioColors.green),
                      const SizedBox(width: 12),
                      Text(
                        entry.$2,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
              if (_repeatKind != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context, ''),
                  child: const Text('Remove repeat'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (!mounted || picked == null) return;
    if (picked.isEmpty) {
      setState(() {
        _repeatKind = null;
        _provider = null;
      });
      return;
    }
    var count = _installments;
    String? provider;
    if (picked == 'installment') {
      final controller = TextEditingController(text: '$_installments');
      final entered = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: FolioColors.card,
          title: const Text('How many payments?'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: '12'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      final parsed = int.tryParse(entered ?? '');
      if (parsed == null || parsed < 1) return;
      count = parsed;
    }
    if (!mounted) return;
    if (picked == 'repeat' || picked == 'installment') {
      provider = await pickInstallmentPayment(context);
      if (!mounted || provider == null || provider.isEmpty) return;
    }
    setState(() {
      _repeatKind = picked;
      _installments = count;
      _provider = provider;
    });
  }

  Future<void> _pickSubscription(FolioStore store) async {
    final existing = widget.existing;
    if (existing == null) return;
    final plans = store.recurring.where((item) => item.active).toList();
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: FolioColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            const Text('Subscription', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Not linked'),
              onTap: () => Navigator.pop(context, ''),
            ),
            for (final item in plans)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.name),
                subtitle: Text(item.currency == 'LKR' ? money(item.amount) : foreignAmount(item.currency, item.amount)),
                onTap: () => Navigator.pop(context, item.id),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    try {
      await store.linkTransactionRecurring(existing.id, picked.isEmpty ? null : picked);
      if (mounted) setState(() => _recurringId = picked);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _pickAccount(FolioStore store, {required bool destination}) async {
    final choices = [
      for (final account in store.accounts)
        if (!destination || account.id != _accountId) account,
    ];
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: FolioColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            Text(
              destination
                  ? 'To account'
                  : _direction == 'transfer'
                  ? 'From account'
                  : 'Account',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            for (final account in choices) ...[
              FolioCard(
                onTap: () => Navigator.pop(context, account.id),
                child: Row(
                  children: [
                    IconBubble(
                      icon: accountIcon(account.type),
                      color: const Color(0xFF8E8E98),
                      size: 40,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(account.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(
                            account.isBusiness ? 'Business' : 'Personal',
                            style: const TextStyle(color: FolioColors.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Text(money(account.balance), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
    if (!mounted || picked == null) return;
    setState(() {
      if (destination) {
        _transferId = picked;
      } else {
        _accountId = picked;
        if (_transferId == picked) _transferId = null;
        final account = store.accounts.where((item) => item.id == picked).firstOrNull;
        if (account != null) _business = account.isBusiness;
        if (_direction == 'transfer') _preferCash(store);
      }
    });
  }

  Future<void> _openDateTray() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: FolioColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Date', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              CalendarDatePicker(
                initialDate: _when,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 1)),
                onDateChanged: (date) {
                  setState(() {
                    _when = DateTime(date.year, date.month, date.day, _when.hour, _when.minute);
                  });
                },
              ),
              TextButton(
                onPressed: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(_when),
                  );
                  if (time == null || !mounted) return;
                  setState(() {
                    _when = DateTime(_when.year, _when.month, _when.day, time.hour, time.minute);
                  });
                },
                child: Text(stamp(_when)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openCategoryTray(FolioStore store, String kind) async {
    final categories = store.categories.where((category) => category.kind == kind).toList();
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: FolioColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => _CategorySheet(
        categories: categories,
        selectedId: _categoryId,
        budget: _budgetFor(store, _categoryId),
      ),
    );
    if (!mounted || picked == null) return;
    if (picked == '__add__') {
      await _addCategory(kind);
      return;
    }
    setState(() => _categoryId = picked);
  }

  Future<void> _openNoteTray() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: FolioColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Note', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              autofocus: true,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(hintText: 'Note'),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  String get _whenLabel {
    final now = DateTime.now();
    final today = now.year == _when.year && now.month == _when.month && now.day == _when.day;
    if (today) return 'Today, ${clock(_when)}';
    return stamp(_when);
  }

  String get _statusLabel => switch (_clearStatus) {
    'reconciled' => 'Reconciled',
    'uncleared' => 'Uncleared',
    _ => 'Cleared',
  };

  Future<void> _openLabels(FolioStore store) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => _LabelsPage(
          tags: _tags,
          known: _knownTags(store),
          onCreate: _addTag,
          onRemove: (name) {
            _tags.removeWhere((item) => item.toLowerCase() == name.toLowerCase());
          },
        ),
      ),
    );
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _openPayee(FolioStore store) async {
    final picked = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => PayeePickerScreen(store: store, current: _merchant.text.trim())),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _location = picked;
      _merchant.text = picked;
    });
  }

  Future<void> _openPaymentType() async {
    final picked = await _pickLine('Payment type', const ['Cash', 'Card', 'Bank transfer', 'Online'], _paymentType);
    if (picked != null) setState(() => _paymentType = picked);
  }

  Future<void> _openWarranty() async {
    final current = _warranty.isEmpty ? 'None' : _warranty;
    final picked = await _pickLine('Warranty', const ['None', '6 months', '1 year', '2 years', '3 years'], current);
    if (picked != null) setState(() => _warranty = picked == 'None' ? '' : picked);
  }

  Future<void> _openStatus() async {
    final picked = await _pickLine('Status', const ['Reconciled', 'Cleared', 'Uncleared'], _statusLabel);
    if (picked == null) return;
    setState(() {
      _clearStatus = switch (picked) {
        'Reconciled' => 'reconciled',
        'Uncleared' => 'uncleared',
        _ => 'cleared',
      };
    });
  }

  Future<String?> _pickLine(String title, List<String> options, String selected) {
    return Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            title: Text(title),
          ),
          body: ListView(
            children: [
              for (final option in options)
                ListTile(
                  title: Text(option),
                  trailing: option == selected
                      ? const Icon(Icons.check_rounded, color: Color(0xFF7EB6FF))
                      : null,
                  onTap: () => Navigator.pop(context, option),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openPlace() async {
    final saved = await showDialog<String>(
      context: context,
      builder: (context) => _TextPrompt(title: 'Location', hint: 'Place, optional', initial: _place, action: 'Save'),
    );
    if (saved == null || !mounted) return;
    setState(() => _place = saved);
  }

  Future<void> _attachPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 80);
    if (picked == null || !mounted) return;
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/receipts');
    if (!folder.existsSync()) folder.createSync(recursive: true);
    final dest = File('${folder.path}/${DateTime.now().millisecondsSinceEpoch}.jpg');
    await File(picked.path).copy(dest.path);
    if (!mounted) return;
    setState(() => _photo = dest.path);
  }

  String get _repeatLabel {
    final payment = _provider == null || _provider!.isEmpty ? '' : ' · $_provider';
    return switch (_repeatKind) {
      'installment' => 'Installment$payment',
      'subscription' => 'Subscription',
      'repeat' => 'Repeat$payment',
      _ => 'Recurring',
    };
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FolioStore>();
    final editing = widget.existing != null;
    final foreign = _currency != 'LKR' && _fxAmount != null;
    final kind = _direction == 'income' ? 'income' : 'expense';
    final categoryBudget = _budgetFor(store, _categoryId);
    final typedAmount = double.tryParse(_amount.text.trim().replaceAll(',', '')) ?? 0;
    final leftAfter = categoryBudget == null || _direction != 'expense' || editing
        ? null
        : categoryBudget.remaining - typedAmount;
    final account = store.accounts.where((item) => item.id == _accountId).firstOrNull;
    final destination = store.accounts.where((item) => item.id == _transferId).firstOrNull;
    final category = store.categories.where((item) => item.id == _categoryId).firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit transaction' : 'Add transaction'),
        actions: [
          if (editing)
            IconButton(
              onPressed: _busy ? null : _delete,
              icon: const Icon(Icons.delete_outline, color: FolioColors.red),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          ChoiceChipRow(
            labels: const ['Expense', 'Income', 'Transfer'],
            selected: _direction == 'income'
                ? 1
                : _direction == 'transfer'
                ? 2
                : 0,
            onSelect: (index) => setState(() {
              _direction = ['expense', 'income', 'transfer'][index];
              _categoryId = null;
              if (_direction == 'transfer') _preferCash(store);
            }),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _amount,
            autofocus: !editing,
            onChanged: (value) {
              if (foreign && !_settledTouched) {
                final face = double.tryParse(value.replaceAll(',', ''));
                final rate = store.rates?.lkrPer(_currency);
                if (face != null && rate != null) _settled.text = groupedAmount(face * rate);
              }
              setState(() {});
            },
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [ThousandsInputFormatter()],
            style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: foreign ? '$_currency 0' : 'Rs. 0',
              hintStyle: const TextStyle(fontSize: 44, fontWeight: FontWeight.w700, color: FolioColors.text),
              filled: true,
              fillColor: FolioColors.card,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
            ),
          ),
          if (foreign) ...[
            const SizedBox(height: 6),
            Text(
              _currency,
              textAlign: TextAlign.center,
              style: const TextStyle(color: FolioColors.muted, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _settled,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: const [ThousandsInputFormatter()],
              onChanged: (_) => _settledTouched = true,
              decoration: const InputDecoration(
                labelText: 'Deducted in rupees',
                hintText: 'Rs. 0',
              ),
            ),
          ],
          if (_direction == 'transfer') ...[
            const SizedBox(height: 8),
            TextField(
              controller: _merchant,
              onChanged: (value) => _location = value,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'Description, optional',
                fillColor: Colors.transparent,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
          const SizedBox(height: 18),
          const _SectionLabel('General'),
          if (store.accounts.isEmpty)
            const Text(
              'Add an account first.',
              style: TextStyle(color: FolioColors.muted),
            )
          else
            _PayList(
              children: [
                if (_direction == 'transfer') ...[
                  _PayRow(
                    tooltip: 'From account',
                    icon: Icons.account_balance_wallet_rounded,
                    color: const Color(0xFF8ED4B0),
                    label: 'From account',
                    value: account?.name ?? 'Choose',
                    filled: account != null,
                    onTap: () => _pickAccount(store, destination: false),
                  ),
                  _PayRow(
                    tooltip: 'To account',
                    icon: Icons.savings_rounded,
                    color: const Color(0xFF7EB6FF),
                    label: 'To account',
                    value: destination?.name ?? 'Choose',
                    filled: destination != null,
                    onTap: () => _pickAccount(store, destination: true),
                  ),
                ] else
                  _PayRow(
                    tooltip: 'Account',
                    icon: Icons.help_outline_rounded,
                    color: const Color(0xFF9B9BA6),
                    label: 'Account',
                    value: account?.name ?? 'Required',
                    filled: account != null,
                    valueColor: account == null ? FolioColors.red : null,
                    onTap: () => _pickAccount(store, destination: false),
                  ),
                if (editing && _direction == 'expense')
                  _PayRow(
                    tooltip: 'Subscription',
                    icon: Icons.event_repeat_rounded,
                    color: const Color(0xFF8ED4B0),
                    label: 'Subscription',
                    value: store.recurring.where((item) => item.id == _recurringId).firstOrNull?.name ?? 'Not linked',
                    filled: _recurringId.isNotEmpty,
                    onTap: () => _pickSubscription(store),
                  ),
                if (_direction != 'transfer')
                  _PayRow(
                    tooltip: 'Category',
                    icon: category == null ? Icons.help_outline_rounded : iconFor(category.icon),
                    color: category == null ? const Color(0xFF9B9BA6) : colorFromHex(category.color),
                    label: 'Category',
                    value: category?.name ?? 'Required',
                    filled: category != null,
                    valueColor: category == null ? FolioColors.red : null,
                    onTap: () => _openCategoryTray(store, kind),
                  ),
                _PayRow(
                  tooltip: 'Date and time',
                  icon: Icons.calendar_today_rounded,
                  color: const Color(0xFFE7C27A),
                  label: 'Date & Time',
                  value: _whenLabel,
                  filled: true,
                  onTap: _openDateTray,
                ),
                _PayRow(
                  tooltip: 'Labels',
                  icon: Icons.sell_outlined,
                  color: const Color(0xFF9B9BA6),
                  label: 'Labels',
                  value: _tags.isEmpty ? '' : _tags.join(', '),
                  filled: _tags.isNotEmpty,
                  onTap: () => _openLabels(store),
                ),
              ],
            ),
          const SizedBox(height: 18),
          const _SectionLabel('More detail'),
          if (store.accounts.isNotEmpty)
            _PayList(
              children: [
                _PayRow(
                  tooltip: 'Note',
                  icon: Icons.edit_outlined,
                  color: const Color(0xFF9B9BA6),
                  label: 'Note',
                  value: _note.text.trim().isEmpty ? '' : _note.text.trim(),
                  filled: _note.text.trim().isNotEmpty,
                  onTap: _openNoteTray,
                ),
                if (_direction != 'transfer')
                  _PayRow(
                    tooltip: 'Payee',
                    icon: Icons.person_outline_rounded,
                    color: const Color(0xFF9B9BA6),
                    label: 'Payee',
                    value: _merchant.text.trim(),
                    filled: _merchant.text.trim().isNotEmpty,
                    onTap: () => _openPayee(store),
                  ),
                if (_direction != 'transfer')
                  _PayRow(
                    tooltip: 'Payment type',
                    icon: Icons.credit_card_rounded,
                    color: const Color(0xFF9B9BA6),
                    label: 'Payment type',
                    value: _paymentType,
                    filled: true,
                    onTap: _openPaymentType,
                  ),
                if (_direction != 'transfer')
                  _PayRow(
                    tooltip: 'Warranty',
                    icon: Icons.shield_outlined,
                    color: const Color(0xFF9B9BA6),
                    label: 'Warranty',
                    value: _warranty.isEmpty ? 'None' : _warranty,
                    filled: true,
                    onTap: _openWarranty,
                  ),
                if (_direction != 'transfer')
                  _PayRow(
                    tooltip: 'Status',
                    icon: Icons.hourglass_bottom_rounded,
                    color: const Color(0xFF9B9BA6),
                    label: 'Status',
                    value: _statusLabel,
                    filled: true,
                    onTap: _openStatus,
                  ),
                if (_direction != 'transfer')
                  _PayRow(
                    tooltip: 'Location',
                    icon: Icons.location_on_rounded,
                    color: const Color(0xFF3B82F6),
                    label: _place.isEmpty ? 'Add location' : 'Location',
                    labelColor: _place.isEmpty ? const Color(0xFF3B82F6) : null,
                    value: _place,
                    filled: _place.isNotEmpty,
                    onTap: _openPlace,
                  ),
                if (_direction != 'transfer')
                  _PayRow(
                    tooltip: 'Photo',
                    icon: Icons.photo_camera_outlined,
                    color: const Color(0xFF3B82F6),
                    label: _photo.isEmpty ? 'Attach photo' : 'Photo',
                    labelColor: _photo.isEmpty ? const Color(0xFF3B82F6) : null,
                    value: _photo.isEmpty ? '' : 'Attached',
                    filled: _photo.isNotEmpty,
                    onTap: _attachPhoto,
                  ),
                if (widget.existing == null && _direction != 'transfer')
                  _PayRow(
                    tooltip: _repeatLabel,
                    icon: Icons.event_repeat_rounded,
                    color: const Color(0xFF7EB6FF),
                    label: 'Repeat',
                    value: _repeatKind == null ? 'Off' : _repeatLabel,
                    filled: _repeatKind != null,
                    onTap: _pickRepeat,
                  ),
              ],
            ),
          if (_direction != 'transfer' && categoryBudget != null) ...[
            const SizedBox(height: 8),
            Text(
              leftAfter == null
                  ? '${money(categoryBudget.remaining)} left of ${money(categoryBudget.limitAmount)}'
                  : '${money(leftAfter)} left after this · ${money(categoryBudget.limitAmount)} budget',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: (leftAfter ?? categoryBudget.remaining) < 0 ? FolioColors.red : FolioColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (_direction == 'transfer' && store.accounts.isNotEmpty) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _charge,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Bank charges',
                hintText: 'Optional',
              ),
            ),
          ],
          if (_repeatKind != null) ...[
            const SizedBox(height: 8),
            Text(
              _repeatKind == 'installment'
                  ? 'Also saved as $_installments monthly ${_provider ?? ''} installments for this payee, starting next month.'
                  : _repeatKind == 'subscription'
                  ? 'Also saved as a monthly subscription, starting next month.'
                  : 'Also saved as a monthly ${_provider ?? ''} repeat for this payee, starting next month.',
              style: const TextStyle(color: FolioColors.muted, fontSize: 13),
            ),
          ],
          TextButton(
            onPressed: () => setState(() => _details = !_details),
            child: Text(_details ? 'Hide details' : 'Show details'),
          ),
          if (_details) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hide transaction'),
              subtitle: const Text(
                'Hidden from spending and the timeline. The account balance still includes it.',
              ),
              value: _hidden,
              activeThumbColor: FolioColors.green,
              onChanged: (value) => setState(() => _hidden = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Business transaction'),
              value: _business,
              activeThumbColor: FolioColors.green,
              onChanged: (value) => setState(() => _business = value),
            ),
          ],
          const SizedBox(height: 16),
          PrimaryButton(
            label: editing ? 'Save changes' : 'Add transaction',
            busy: _busy,
            onPressed: store.accounts.isEmpty ? null : _save,
          ),
          if (store.accounts.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Add an account first.',
                style: TextStyle(color: FolioColors.muted),
              ),
            ),
        ],
      ),
    );
  }
}

class _PayList extends StatelessWidget {
  const _PayList({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = children.whereType<Widget>().toList();
    return Container(
      decoration: BoxDecoration(
        color: FolioColors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, thickness: 1, indent: 68, color: FolioColors.bg),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: FolioColors.muted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _PayRow extends StatelessWidget {
  const _PayRow({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.filled,
    required this.onTap,
    this.valueColor,
    this.labelColor,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final bool filled;
  final VoidCallback onTap;
  final Color? valueColor;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 22, color: color),
              ),
              const SizedBox(width: 14),
              Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: labelColor)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: valueColor ?? (filled ? FolioColors.text : FolioColors.muted),
                    fontWeight: filled ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: FolioColors.muted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.icon,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color.withValues(alpha: 0.22) : FolioColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: selected ? 0.28 : 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: selected ? FolioColors.text : FolioColors.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showSmsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: FolioColors.card,
    builder: (context) =>
        const Padding(padding: EdgeInsets.only(bottom: 12), child: _SmsSheet()),
  );
}

class _SmsSheet extends StatefulWidget {
  const _SmsSheet();

  @override
  State<_SmsSheet> createState() => _SmsSheetState();
}

class _SmsSheetState extends State<_SmsSheet> {
  final _body = TextEditingController();
  SriLankaBank? _bank;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _body.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.isEmpty) return;
    setState(() => _body.text = text);
  }

  Future<void> _save() async {
    if (_body.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final result = await context.read<FolioStore>().ingestSms(
        _body.text,
        sender: _bank?.sender ?? '',
      );
      if (!mounted) return;
      final status = result['status'] as String? ?? '';
      Navigator.pop(context);
      final message = switch (status) {
        'posted' => 'Added from the bank message.',
        'needs_review' => 'Saved. Pick an account for it from the dashboard.',
        'duplicate' => 'That message is already in Takings.',
        _ => 'This does not look like a bank debit or credit.',
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text(
              'Add from SMS',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
            ),
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text(
              'Paste a bank SMS and we will log it for you.',
              style: TextStyle(color: FolioColors.muted),
            ),
          ),
          const SizedBox(height: 16),
          _SmsPasteBox(controller: _body, onPaste: _paste),
          const SizedBox(height: 12),
          _BankChoice(
            bank: _bank,
            onTap: () async {
              final picked = await showBankPicker(context);
              if (picked == null || !mounted) return;
              setState(() => _bank = picked);
            },
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Add transaction',
            busy: _busy,
            onPressed: _body.text.trim().isEmpty ? null : _save,
          ),
        ],
      ),
    );
  }
}

Future<void> showSetupTest(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _SetupTestDialog(),
  );
}

class _SetupTestDialog extends StatefulWidget {
  const _SetupTestDialog();

  @override
  State<_SetupTestDialog> createState() => _SetupTestDialogState();
}

class _SetupTestDialogState extends State<_SetupTestDialog> {
  bool _busy = false;
  String? _result;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      final result = await context.read<FolioStore>().previewSms(
        'Rs. 100.00 debited. Info: TEST SHOP',
        sender: 'COMBANK',
      );
      final name = result['account_name'] as String? ?? '';
      setState(() {
        _result = name.isEmpty
            ? 'The sample was read, but no account matched. Set a preferred account for that bank.'
            : 'The sample would be filed on $name.';
      });
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: FolioColors.card,
      title: const Text('Test your setup'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Takings checks a sample bank message against your accounts. It stays in the app and is not sent as a text.',
            style: TextStyle(color: FolioColors.muted, height: 1.4),
          ),
          if (_result != null) ...[const SizedBox(height: 12), Text(_result!)],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        TextButton(
          onPressed: _busy ? null : _run,
          child: Text(_busy ? 'Checking' : 'Check setup'),
        ),
      ],
    );
  }
}

class _SmsPasteBox extends StatelessWidget {
  const _SmsPasteBox({required this.controller, required this.onPaste});

  final TextEditingController controller;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        TextField(
          controller: controller,
          minLines: 5,
          maxLines: 7,
          decoration: const InputDecoration(
            hintText: 'Paste your bank SMS here',
            contentPadding: EdgeInsets.fromLTRB(16, 16, 16, 56),
          ),
        ),
        Positioned(
          right: 10,
          bottom: 10,
          child: OutlinedButton.icon(
            onPressed: onPaste,
            icon: const Icon(Icons.content_paste_outlined, size: 16),
            label: const Text('Paste'),
            style: OutlinedButton.styleFrom(
              foregroundColor: FolioColors.green,
              side: const BorderSide(color: FolioColors.green),
              visualDensity: VisualDensity.compact,
              shape: const StadiumBorder(),
            ),
          ),
        ),
      ],
    );
  }
}

class _BankChoice extends StatelessWidget {
  const _BankChoice({required this.bank, required this.onTap});

  final SriLankaBank? bank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: FolioColors.card,
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: bank == null
            ? const CircleAvatar(
                backgroundColor: FolioColors.cardHigh,
                child: Icon(
                  Icons.account_balance,
                  color: FolioColors.muted,
                  size: 20,
                ),
              )
            : BankMark(bank: bank!, size: 40),
        title: const Text(
          'Bank',
          style: TextStyle(color: FolioColors.muted, fontSize: 12),
        ),
        subtitle: Text(
          bank?.name ?? 'Select your bank',
          style: const TextStyle(
            color: FolioColors.text,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        trailing: const Icon(Icons.expand_more, color: FolioColors.muted),
        onTap: onTap,
      ),
    );
  }
}

class SmsScreen extends StatefulWidget {
  const SmsScreen({super.key, this.initialText = ''});
  final String initialText;

  @override
  State<SmsScreen> createState() => _SmsScreenState();
}

class _SmsScreenState extends State<SmsScreen> {
  late final TextEditingController _body = TextEditingController(
    text: widget.initialText,
  );
  SriLankaBank? _bank;
  bool _busy = false;
  String? _result;

  @override
  void initState() {
    super.initState();
    _body.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_body.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final result = await context.read<FolioStore>().ingestSms(
        _body.text,
        sender: _bank?.sender ?? '',
      );
      final status = result['status'] as String? ?? '';
      final txn = result['transaction'] as Map<String, dynamic>?;
      setState(() {
        _result = switch (status) {
          'posted' =>
            'Added ${txn?['merchant'] ?? 'transaction'} to ${txn?['account_name'] ?? 'an account'}.',
          'needs_review' => 'Saved. Pick an account for it from the dashboard.',
          'duplicate' => 'That message is already in Takings.',
          _ => 'This does not look like a bank debit or credit.',
        };
      });
      if (status == 'posted' || status == 'needs_review') _body.clear();
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bank SMS')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Paste a bank SMS and we will log it for you.',
            style: TextStyle(color: FolioColors.muted, height: 1.4),
          ),
          const SizedBox(height: 12),
          _SmsPasteBox(
            controller: _body,
            onPaste: () async {
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              final text = data?.text ?? '';
              if (text.isEmpty) return;
              setState(() => _body.text = text);
            },
          ),
          const SizedBox(height: 12),
          _BankChoice(
            bank: _bank,
            onTap: () async {
              final picked = await showBankPicker(context);
              if (picked == null || !mounted) return;
              setState(() => _bank = picked);
            },
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Add transaction',
            busy: _busy,
            onPressed: _body.text.trim().isEmpty ? null : _save,
          ),
          if (_result != null) ...[
            const SizedBox(height: 16),
            FolioCard(child: Text(_result!)),
          ],
        ],
      ),
    );
  }
}

class ReviewScreen extends StatelessWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FolioStore>();
    return Scaffold(
      appBar: AppBar(title: const Text('Needs an account')),
      body: store.review.isEmpty
          ? const EmptyBlock(
              icon: Icons.check_circle_outline,
              title: 'All caught up',
              body: 'Every bank message is filed.',
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final txn in store.review) ...[
                  _ReviewCard(txn: txn),
                  const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }
}

class _ReviewCard extends StatefulWidget {
  const _ReviewCard({required this.txn});
  final TxnModel txn;

  @override
  State<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<_ReviewCard> {
  String? _accountId;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FolioStore>();
    _accountId ??= store.accounts.firstOrNull?.id;
    return FolioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.txn.title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            moneyLabel(widget.txn),
            style: const TextStyle(color: FolioColors.muted),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _accountId,
            dropdownColor: FolioColors.card,
            items: [
              for (final account in store.accounts)
                DropdownMenuItem(value: account.id, child: Text(account.name)),
            ],
            onChanged: (value) => setState(() => _accountId = value),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        await store.deleteTransaction(widget.txn.id);
                      },
                child: const Text(
                  'Ignore',
                  style: TextStyle(color: FolioColors.muted),
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _busy || _accountId == null
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        try {
                          await store.assignTransaction(
                            widget.txn.id,
                            _accountId!,
                            widget.txn.categoryId,
                          );
                        } catch (error) {
                          if (context.mounted) showError(context, error);
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                child: const Text('File it'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String moneyLabel(TxnModel txn) {
    final sign = txn.direction == 'income' ? 'In' : 'Out';
    return '$sign · ${postedAmount(amount: txn.amount, currency: txn.currency, fxAmount: txn.fxAmount)}';
  }
}

String groupedAmount(double amount) {
  final plain = amount == amount.roundToDouble()
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2);
  return ThousandsInputFormatter.group(plain);
}

class ThousandsInputFormatter extends TextInputFormatter {
  const ThousandsInputFormatter();

  static String group(String raw) {
    final cleaned = raw.replaceAll(',', '');
    final dot = cleaned.indexOf('.');
    final whole = dot == -1 ? cleaned : cleaned.substring(0, dot);
    final fraction = dot == -1 ? '' : cleaned.substring(dot);
    if (whole.length <= 3) return '$whole$fraction';
    final buffer = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      final remaining = whole.length - i;
      if (i > 0 && remaining % 3 == 0) buffer.write(',');
      buffer.write(whole[i]);
    }
    return '$buffer$fraction';
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final raw = newValue.text.replaceAll(',', '');
    if (raw.isEmpty) return const TextEditingValue(text: '');
    if (!RegExp(r'^\d*\.?\d{0,2}$').hasMatch(raw)) return oldValue;
    final text = group(raw);
    final digitsBefore = newValue.text
        .substring(0, newValue.selection.end.clamp(0, newValue.text.length))
        .replaceAll(',', '')
        .length;
    var seen = 0;
    var offset = text.length;
    for (var i = 0; i < text.length; i++) {
      if (text[i] == ',') continue;
      seen++;
      if (seen >= digitsBefore) {
        offset = i + 1;
        break;
      }
    }
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset.clamp(0, text.length)),
    );
  }
}

class _CategorySheet extends StatefulWidget {
  const _CategorySheet({required this.categories, required this.selectedId, required this.budget});

  final List<CategoryModel> categories;
  final String? selectedId;
  final BudgetModel? budget;

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<_CategoryGroup> get _visible {
    final query = _query.text.trim().toLowerCase();
    final groups = <_CategoryGroup>[];
    for (final group in _categoryGroups(widget.categories)) {
      if (query.isEmpty) {
        groups.add(group);
        continue;
      }
      final parentHit = group.parent.name.toLowerCase().contains(query);
      final children = [
        for (final child in group.children)
          if (parentHit || child.name.toLowerCase().contains(query)) child,
      ];
      if (parentHit || children.isNotEmpty) groups.add(_CategoryGroup(group.parent, children));
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final budget = widget.budget;
    final groups = _visible;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.78,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: FolioColors.line, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('Category', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _query,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Search categories',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            if (budget != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(
                  '${money(budget.remaining)} left of ${money(budget.limitAmount)}',
                  style: TextStyle(
                    color: budget.remaining < 0 ? FolioColors.red : FolioColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  for (final group in groups) ...[
                    if (group.children.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                        child: Text(
                          group.parent.name,
                          style: const TextStyle(color: FolioColors.muted, fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ),
                    _CategoryRow(
                      icon: iconFor(group.parent.icon),
                      label: group.parent.name,
                      color: colorFromHex(group.parent.color),
                      selected: group.parent.id == widget.selectedId,
                      onTap: () => Navigator.pop(context, group.parent.id),
                    ),
                    for (final child in group.children) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(left: 18),
                        child: _CategoryRow(
                          icon: iconFor(child.icon),
                          label: child.name,
                          color: colorFromHex(child.color),
                          selected: child.id == widget.selectedId,
                          onTap: () => Navigator.pop(context, child.id),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                  if (groups.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No categories match', style: TextStyle(color: FolioColors.muted)),
                    ),
                  _CategoryRow(
                    icon: Icons.add_rounded,
                    label: 'Add a category',
                    color: FolioColors.muted,
                    selected: false,
                    onTap: () => Navigator.pop(context, '__add__'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextPrompt extends StatefulWidget {
  const _TextPrompt({
    required this.title,
    required this.hint,
    this.initial = '',
    this.action = 'Add',
    this.keyboard,
  });

  final String title;
  final String hint;
  final String initial;
  final String action;
  final TextInputType? keyboard;

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  late final TextEditingController _field = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: FolioColors.card,
      title: Text(widget.title),
      content: TextField(
        controller: _field,
        autofocus: true,
        keyboardType: widget.keyboard,
        textCapitalization: widget.keyboard == null ? TextCapitalization.words : TextCapitalization.none,
        decoration: InputDecoration(hintText: widget.hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, _field.text.trim()), child: Text(widget.action)),
      ],
    );
  }
}

class _LabelsPage extends StatefulWidget {
  const _LabelsPage({
    required this.tags,
    required this.known,
    required this.onCreate,
    required this.onRemove,
  });

  final List<String> tags;
  final List<String> known;
  final ValueChanged<String> onCreate;
  final ValueChanged<String> onRemove;

  @override
  State<_LabelsPage> createState() => _LabelsPageState();
}

class _LabelsPageState extends State<_LabelsPage> {
  Future<void> _create() async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _TextPrompt(title: 'New label', hint: 'Rice, chicken…'),
    );
    if (!mounted || name == null || name.isEmpty) return;
    widget.onCreate(name);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final all = <String>[
      ...widget.tags,
      for (final tag in widget.known)
        if (!widget.tags.any((item) => item.toLowerCase() == tag.toLowerCase())) tag,
    ];
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () {
            FocusManager.instance.primaryFocus?.unfocus();
            Navigator.pop(context);
          },
        ),
        title: const Text('Labels'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: 'Add label',
              onPressed: _create,
              icon: const Icon(Icons.add_circle, color: Color(0xFF3B82F6), size: 28),
            ),
          ),
        ],
      ),
      body: all.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 36),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sell_rounded, size: 72, color: FolioColors.muted),
                    SizedBox(height: 16),
                    Text('Labels', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                    SizedBox(height: 8),
                    Text(
                      'Use Labels to organize your records better. Start with (+) to create first one.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: FolioColors.muted, height: 1.4),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              children: [
                for (final tag in all)
                  ListTile(
                    title: Text(tag),
                    trailing: widget.tags.any((item) => item.toLowerCase() == tag.toLowerCase())
                        ? const Icon(Icons.check_rounded, color: Color(0xFF7EB6FF))
                        : null,
                    onTap: () {
                      final selected = widget.tags.any((item) => item.toLowerCase() == tag.toLowerCase());
                      if (selected) {
                        widget.onRemove(tag);
                      } else {
                        widget.onCreate(tag);
                      }
                      setState(() {});
                    },
                  ),
              ],
            ),
    );
  }
}
