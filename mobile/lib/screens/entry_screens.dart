import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    setState(() {
      _tags.add(tag);
      if (preset == null) _tag.clear();
    });
  }

  List<String> _shopNames(FolioStore store) {
    final seen = <String>{};
    final names = <String>[];
    void add(String raw) {
      final name = raw.trim();
      if (name.isEmpty || name.toLowerCase() == 'transfer') return;
      if (!seen.add(name.toLowerCase())) return;
      names.add(name);
    }
    for (final day in store.timeline?.days ?? const <TimelineDay>[]) {
      for (final txn in day.items) {
        add(txn.merchant);
      }
    }
    for (final txn in store.review) {
      add(txn.merchant);
    }
    return names;
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
    final name = TextEditingController();
    final created = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FolioColors.card,
        title: const Text('New category'),
        content: TextField(
          controller: name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Groceries, Spices, Shopping'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, name.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    name.dispose();
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: FolioColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        final height = MediaQuery.sizeOf(context).height * 0.62;
        final budget = _budgetFor(store, _categoryId);
        return SizedBox(
          height: height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: FolioColors.line,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Text('Category', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              if (budget != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
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
                    for (final category in categories) ...[
                      _CategoryRow(
                        icon: iconFor(category.icon),
                        label: category.name,
                        color: colorFromHex(category.color),
                        selected: category.id == _categoryId,
                        onTap: () {
                          setState(() {
                            _categoryId = _categoryId == category.id ? null : category.id;
                          });
                          Navigator.pop(context);
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                    _CategoryRow(
                      icon: Icons.add_rounded,
                      label: 'Add a category',
                      color: FolioColors.muted,
                      selected: false,
                      onTap: _busy
                          ? () {}
                          : () async {
                              Navigator.pop(context);
                              await _addCategory(kind);
                            },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openTagTray(FolioStore store) async {
    final knownTags = _knownTags(store);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: FolioColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: StatefulBuilder(
          builder: (context, setSheet) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tag', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                if (_tags.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in _tags)
                        InputChip(
                          label: Text(tag),
                          backgroundColor: const Color(0xFF3A3C44),
                          side: BorderSide.none,
                          onDeleted: () {
                            setState(() => _tags.remove(tag));
                            setSheet(() {});
                          },
                        ),
                    ],
                  ),
                if (knownTags.any((tag) => !_tags.any((item) => item.toLowerCase() == tag.toLowerCase()))) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in knownTags)
                        if (!_tags.any((item) => item.toLowerCase() == tag.toLowerCase()))
                          _PlainTag(
                            label: tag,
                            selected: false,
                            onTap: () {
                              _addTag(tag);
                              setSheet(() {});
                            },
                          ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                TextField(
                  controller: _tag,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    _addTag();
                    setSheet(() {});
                  },
                  decoration: InputDecoration(
                    hintText: 'Create a tag',
                    suffixIcon: IconButton(
                      onPressed: () {
                        _addTag();
                        setSheet(() {});
                      },
                      icon: const Icon(Icons.add),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
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
    if (_accountId == null && store.accounts.isNotEmpty) {
      _accountId = store.accounts.first.id;
      _business = store.accounts.first.isBusiness;
    }
    final editing = widget.existing != null;
    final foreign = _currency != 'LKR' && _fxAmount != null;
    final kind = _direction == 'income' ? 'income' : 'expense';
    final categoryBudget = _budgetFor(store, _categoryId);
    final typedAmount = double.tryParse(_amount.text.trim().replaceAll(',', '')) ?? 0;
    final leftAfter = categoryBudget == null || _direction != 'expense' || editing
        ? null
        : categoryBudget.remaining - typedAmount;
    final shops = _direction == 'transfer' ? const <String>[] : _shopNames(store);
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
          const SizedBox(height: 8),
          TextField(
            controller: _merchant,
            onChanged: (value) => _location = value,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: _direction == 'transfer' ? 'Description, optional' : 'Location, optional',
              fillColor: Colors.transparent,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          if (shops.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: shops.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final shop = shops[index];
                  final selected = shop.toLowerCase() == _merchant.text.trim().toLowerCase();
                  return _PlainTag(
                    label: shop,
                    selected: selected,
                    onTap: () => setState(() {
                      _location = shop;
                      _merchant.text = shop;
                    }),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 18),
          if (store.accounts.isEmpty)
            const Text(
              'Add an account first.',
              style: TextStyle(color: FolioColors.muted),
            )
          else
            _PayList(
              children: [
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
                    icon: category == null ? Icons.category_rounded : iconFor(category.icon),
                    color: category == null ? const Color(0xFFC5D7F6) : colorFromHex(category.color),
                    label: 'Category',
                    value: category?.name ?? 'Choose',
                    filled: category != null,
                    onTap: () => _openCategoryTray(store, kind),
                  ),
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
                    icon: Icons.account_balance_wallet_rounded,
                    color: const Color(0xFF8ED4B0),
                    label: 'Account',
                    value: account?.name ?? 'Choose',
                    filled: account != null,
                    onTap: () => _pickAccount(store, destination: false),
                  ),
                _PayRow(
                  tooltip: 'Date',
                  icon: Icons.calendar_today_rounded,
                  color: const Color(0xFFE7C27A),
                  label: 'Date',
                  value: stamp(_when),
                  filled: true,
                  onTap: _openDateTray,
                ),
                _PayRow(
                  tooltip: 'Tag',
                  icon: Icons.sell_rounded,
                  color: const Color(0xFFF0A0A0),
                  label: 'Tag',
                  value: _tags.isEmpty ? 'None' : _tags.join(', '),
                  filled: _tags.isNotEmpty,
                  onTap: () => _openTagTray(store),
                ),
                _PayRow(
                  tooltip: 'Note',
                  icon: Icons.sticky_note_2_rounded,
                  color: const Color(0xFFC4B5FD),
                  label: 'Note',
                  value: _note.text.trim().isEmpty ? 'Add' : _note.text.trim(),
                  filled: _note.text.trim().isNotEmpty,
                  onTap: _openNoteTray,
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
                  ? 'Also saved as $_installments monthly ${_provider ?? ''} installments for this shop, starting next month.'
                  : _repeatKind == 'subscription'
                  ? 'Also saved as a monthly subscription, starting next month.'
                  : 'Also saved as a monthly ${_provider ?? ''} repeat for this shop, starting next month.',
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

class _PlainTag extends StatelessWidget {
  const _PlainTag({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF3A3C44) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? FolioColors.text : FolioColors.muted,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
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

class _PayRow extends StatelessWidget {
  const _PayRow({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.filled,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
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
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: filled ? FolioColors.text : FolioColors.muted,
                    fontWeight: filled ? FontWeight.w600 : FontWeight.w500,
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
