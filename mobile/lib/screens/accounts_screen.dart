import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../banks.dart';
import '../format.dart';
import '../icons.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<FolioStore>().accounts.where((account) {
      if (_filter == 'business') return account.isBusiness;
      if (_filter == 'all') return true;
      return account.type == _filter;
    }).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('My accounts'),
        actions: [
          IconButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountFormScreen())),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          ChoiceChipRow(
            labels: const ['All', 'Bank', 'Debit', 'Credit', 'Cash', 'Business'],
            selected: ['all', 'bank', 'debit_card', 'credit_card', 'cash', 'business'].indexOf(_filter),
            onSelect: (index) => setState(() {
              _filter = ['all', 'bank', 'debit_card', 'credit_card', 'cash', 'business'][index];
            }),
          ),
          const SizedBox(height: 16),
          if (accounts.isEmpty)
            const EmptyBlock(
              icon: Icons.account_balance_outlined,
              title: 'No accounts here',
              body: 'Add a cash wallet, a bank account, or a card. The last 4 digits are how SMS gets matched.',
            )
          else
            for (final account in accounts) ...[
              _AccountRow(account: account),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.account});
  final AccountModel account;

  @override
  Widget build(BuildContext context) {
    return FolioCard(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AccountFormScreen(existing: account)),
      ),
      child: Row(
        children: [
          IconBubble(icon: accountIcon(account.type), color: const Color(0xFF7EB6FF)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(account.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  [
                    accountTypeLabel(account.type),
                    if (account.last4.isNotEmpty) account.last4,
                    if (account.bankName.isNotEmpty) account.bankName,
                    if (account.isBusiness) 'Business',
                  ].join(' · '),
                  style: const TextStyle(color: FolioColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(money(account.balance), style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class AccountFormScreen extends StatefulWidget {
  const AccountFormScreen({super.key, this.existing});
  final AccountModel? existing;

  @override
  State<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends State<AccountFormScreen> {
  late final TextEditingController _name;
  late final TextEditingController _balance;
  late final TextEditingController _bank;
  late final TextEditingController _last4;
  late final TextEditingController _sender;
  late String _type;
  late String _purpose;
  late bool _auto;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _type = existing?.type ?? 'bank';
    _purpose = existing?.purpose ?? 'personal';
    _auto = existing?.automationsEnabled ?? true;
    _name = TextEditingController(text: existing?.name ?? '');
    final opening = existing == null
        ? 0.0
        : existing.type == 'credit_card'
            ? existing.openingBalance.abs()
            : existing.openingBalance;
    _balance = TextEditingController(text: opening == 0 ? '' : opening.toStringAsFixed(2));
    _bank = TextEditingController(text: existing?.bankName ?? '');
    _last4 = TextEditingController(text: existing?.last4 ?? '');
    _sender = TextEditingController(text: existing?.smsSender ?? '');
    _name.addListener(() {
      if (mounted) setState(() {});
    });
    if (existing == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _needsBank && _bank.text.isEmpty) _pickBank();
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    _bank.dispose();
    _last4.dispose();
    _sender.dispose();
    super.dispose();
  }

  bool get _needsBank => _type != 'cash';

  Future<void> _pickType() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: FolioColors.bg,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Select account type', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            for (final entry in const [
              ('cash', 'Cash account', 'Track cash and wallet expenses'),
              ('bank', 'Bank account', 'Track bank account transactions'),
              ('debit_card', 'Debit card', 'Track a debit card and its SMS'),
              ('credit_card', 'Credit card', 'Track card spending and payments'),
            ])
              ListTile(
                selected: _type == entry.$1,
                title: Text(entry.$2),
                subtitle: Text(entry.$3),
                onTap: () => Navigator.pop(context, entry.$1),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _type = picked);
  }

  Future<void> _pickBank() async {
    final picked = await showModalBottomSheet<SriLankaBank>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1C),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (context) => const _BankPickerSheet(),
    );
    if (picked == null) return;
    setState(() {
      _bank.text = picked.name;
      _sender.text = picked.sender;
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final raw = double.tryParse(_balance.text.trim().replaceAll(',', '')) ?? 0;
    final opening = _type == 'credit_card' ? -raw.abs() : raw;
    final body = {
      'name': name,
      'type': _type,
      'purpose': _purpose,
      'bank_name': _needsBank ? _bank.text.trim() : '',
      'last4': _needsBank ? _last4.text.trim() : '',
      'sms_sender': _needsBank ? _sender.text.trim() : '',
      'opening_balance': opening,
      'automations_enabled': _needsBank && _auto,
    };
    setState(() => _busy = true);
    try {
      final store = context.read<FolioStore>();
      if (widget.existing == null) {
        await store.createAccount(body);
      } else {
        await store.updateAccount(widget.existing!.id, body);
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    setState(() => _busy = true);
    try {
      await context.read<FolioStore>().deleteAccount(existing.id);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit account' : 'Add new account')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          TextField(
            controller: _balance,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: 'Rs. 0',
              prefixText: _balance.text.isEmpty ? null : 'Rs. ',
              fillColor: Colors.transparent,
            ),
          ),
          Text(
            _type == 'credit_card' ? 'Amount owed' : 'Opening balance',
            textAlign: TextAlign.center,
            style: const TextStyle(color: FolioColors.muted),
          ),
          const SizedBox(height: 20),
          TextField(controller: _name, decoration: const InputDecoration(hintText: 'Account name')),
          const SizedBox(height: 10),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            tileColor: FolioColors.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Text('Account type', style: TextStyle(color: FolioColors.muted, fontSize: 12)),
            subtitle: Text(accountTypeLabel(_type)),
            trailing: const Icon(Icons.expand_more),
            onTap: _pickType,
          ),
          const SizedBox(height: 10),
          ChoiceChipRow(
            labels: const ['Personal', 'Business'],
            selected: _purpose == 'business' ? 1 : 0,
            onSelect: (index) => setState(() => _purpose = index == 1 ? 'business' : 'personal'),
          ),
          if (_needsBank) ...[
            const SizedBox(height: 10),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              tileColor: FolioColors.card,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              title: Text(
                _bank.text.trim().isEmpty ? 'Select bank' : _bank.text.trim(),
                style: TextStyle(color: _bank.text.trim().isEmpty ? FolioColors.muted : FolioColors.text, fontSize: 16),
              ),
              subtitle: _sender.text.trim().isEmpty ? null : Text(_sender.text.trim(), style: const TextStyle(color: FolioColors.muted, fontSize: 12)),
              trailing: const Icon(Icons.expand_more, color: FolioColors.muted),
              onTap: _pickBank,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _last4,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'Last 4 digits of account or card'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _sender,
              decoration: const InputDecoration(hintText: 'SMS sender'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto-track this account'),
              subtitle: const Text('New bank messages for these digits are added on their own.'),
              value: _auto,
              activeThumbColor: FolioColors.green,
              onChanged: (value) => setState(() => _auto = value),
            ),
          ],
          const SizedBox(height: 20),
          PrimaryButton(label: editing ? 'Save' : 'Create account', busy: _busy, onPressed: _name.text.trim().isEmpty ? null : _save),
          if (editing) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: _busy ? null : _delete, child: const Text('Delete account', style: TextStyle(color: FolioColors.red))),
          ],
        ],
      ),
    );
  }
}

class _BankPickerSheet extends StatefulWidget {
  const _BankPickerSheet();

  @override
  State<_BankPickerSheet> createState() => _BankPickerSheetState();
}

class _BankPickerSheetState extends State<_BankPickerSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final banks = sriLankaBanks.where((bank) {
      if (query.isEmpty) return true;
      return bank.name.toLowerCase().contains(query) || bank.sender.toLowerCase().contains(query);
    }).toList();
    final height = MediaQuery.sizeOf(context).height * 0.72;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: FolioColors.line, borderRadius: BorderRadius.circular(4))),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Select Bank', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Search bank...',
                  prefixIcon: Icon(Icons.search, color: FolioColors.muted),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: banks.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final bank = banks[index];
                  return Material(
                    color: const Color(0xFF242428),
                    borderRadius: BorderRadius.circular(16),
                    child: ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      leading: Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: bank.color, borderRadius: BorderRadius.circular(12)),
                        child: Text(bank.initials, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                      ),
                      title: Text(bank.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(bank.sender, style: const TextStyle(color: FolioColors.muted, fontSize: 12)),
                      onTap: () => Navigator.pop(context, bank),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
