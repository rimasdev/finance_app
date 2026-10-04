import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../account_art.dart';
import '../account_art_file.dart';
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
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AccountFormScreen()),
            ),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: ChoiceChipRow(
              labels: const [
                'All',
                'Bank',
                'Debit',
                'Credit',
                'Cash',
                'Business',
              ],
              selected: [
                'all',
                'bank',
                'debit_card',
                'credit_card',
                'cash',
                'business',
              ].indexOf(_filter),
              onSelect: (index) => setState(() {
                _filter = [
                  'all',
                  'bank',
                  'debit_card',
                  'credit_card',
                  'cash',
                  'business',
                ][index];
              }),
            ),
          ),
          const SizedBox(height: 16),
          const _UnlinkedCards(),
          Expanded(
            child: accounts.isEmpty
                ? ListView(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      EmptyBlock(
                        icon: Icons.account_balance_outlined,
                        title: 'No accounts here',
                        body: 'Add a cash wallet, a bank account, or a card. The last 4 digits are how SMS gets matched.',
                      ),
                    ],
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    buildDefaultDragHandles: false,
                    itemCount: accounts.length,
                    onReorder: (oldIndex, newIndex) async {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final visible = [...accounts];
                      final moved = visible.removeAt(oldIndex);
                      visible.insert(newIndex, moved);
                      final visibleIds = visible
                          .map((account) => account.id)
                          .toList();
                      final full = context
                          .read<FolioStore>()
                          .accounts
                          .map((account) => account.id)
                          .toList();
                      var cursor = 0;
                      final next = [
                        for (final id in full)
                          if (visibleIds.contains(id))
                            visibleIds[cursor++]
                          else
                            id,
                      ];
                      try {
                        await context.read<FolioStore>().reorderAccounts(next);
                      } catch (error) {
                        if (context.mounted) showError(context, error);
                      }
                    },
                    itemBuilder: (context, index) {
                      final account = accounts[index];
                      return Padding(
                        key: ValueKey(account.id),
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            ReorderableDragStartListener(
                              index: index,
                              child: const Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: Icon(
                                  Icons.drag_handle,
                                  color: FolioColors.muted,
                                ),
                              ),
                            ),
                            Expanded(child: _AccountRow(account: account)),
                          ],
                        ),
                      );
                    },
                  ),
          ),
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
    final bank = bankByName(account.bankName);
    final meta = [
      if (account.last4.isNotEmpty) account.last4,
      if (bank == null && account.bankName.isNotEmpty) account.bankName,
      if (account.last4.isEmpty && account.bankName.isEmpty)
        accountTypeLabel(account.type),
      if (account.isBusiness) 'Business',
      if (!account.includeInNet) 'Not in net balance',
    ].join(' · ');
    return FolioCard(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AccountFormScreen(existing: account)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          AccountFace(account: account, size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: FolioColors.muted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            money(account.balance),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

List<String> unlinkedCardDigits(FolioStore store) {
  final known = <String>{
    for (final account in store.accounts) ...[
      if (account.last4.isNotEmpty) account.last4,
      ...account.cardLast4s,
    ],
  };
  final found = <String>[];
  for (final txn in store.review) {
    final digits = txn.cardLast4;
    if (digits.length == 4 &&
        !known.contains(digits) &&
        !found.contains(digits)) {
      found.add(digits);
    }
  }
  return found;
}

class _UnlinkedCards extends StatelessWidget {
  const _UnlinkedCards();

  @override
  Widget build(BuildContext context) {
    final cards = unlinkedCardDigits(context.watch<FolioStore>());
    if (cards.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        children: [
          for (final digits in cards) ...[
            _LinkCardPrompt(digits: digits),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _LinkCardPrompt extends StatefulWidget {
  const _LinkCardPrompt({required this.digits});
  final String digits;

  @override
  State<_LinkCardPrompt> createState() => _LinkCardPromptState();
}

class _LinkCardPromptState extends State<_LinkCardPrompt> {
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
            'Card ••••${widget.digits}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'A bank message used this card. Link it to the account it belongs to.',
            style: TextStyle(color: FolioColors.muted, height: 1.35),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue:
                store.accounts.any((account) => account.id == _accountId)
                ? _accountId
                : null,
            dropdownColor: FolioColors.card,
            decoration: const InputDecoration(labelText: 'Account'),
            items: [
              for (final account in store.accounts)
                DropdownMenuItem(value: account.id, child: Text(account.name)),
            ],
            onChanged: (value) => setState(() => _accountId = value),
          ),
          const SizedBox(height: 10),
          PrimaryButton(
            label: 'Link card',
            busy: _busy,
            onPressed: _accountId == null
                ? null
                : () async {
                    setState(() => _busy = true);
                    try {
                      await store.linkCard(_accountId!, widget.digits);
                    } catch (error) {
                      if (context.mounted) showError(context, error);
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
          ),
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
  late bool _includeInNet;
  bool _busy = false;
  bool _markTouched = false;
  String? _iconKey;
  String? _imagePath;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _type = existing?.type ?? 'cash';
    _purpose = existing?.purpose ?? 'personal';
    _auto = existing?.automationsEnabled ?? true;
    _includeInNet = existing?.includeInNet ?? true;
    _name = TextEditingController(text: existing?.name ?? '');
    final opening = existing == null
        ? 0.0
        : existing.type == 'credit_card'
        ? existing.openingBalance.abs()
        : existing.openingBalance;
    _balance = TextEditingController(
      text: opening == 0 ? '' : opening.toStringAsFixed(2),
    );
    _bank = TextEditingController(text: existing?.bankName ?? '');
    _last4 = TextEditingController(text: existing?.last4 ?? '');
    _sender = TextEditingController(text: existing?.smsSender ?? '');
    final mark = existing == null ? null : AccountMarks.instance.markFor(existing.id);
    if (mark != null && mark.startsWith('icon:')) _iconKey = mark.substring(5);
    if (mark != null && mark.startsWith('file:')) _imagePath = mark.substring(5);
    _name.addListener(() {
      if (mounted) setState(() {});
    });
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

  String _typeLabel(String type) {
    switch (type) {
      case 'cash':
        return 'Cash Accounts';
      case 'credit_card':
        return 'Credit Card';
      case 'debit_card':
        return 'Debit Card';
      default:
        return 'Bank Accounts';
    }
  }

  Future<void> _pickType() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: FolioColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                const SizedBox(height: 16),
                const Text(
                  'Select Account Type',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
                ),
                const SizedBox(height: 12),
                for (final entry in const [
                  (
                    'cash',
                    'Cash Account',
                    'Track cash and wallet expenses',
                    Icons.account_balance_wallet_outlined,
                  ),
                  (
                    'bank',
                    'Bank Account',
                    'Track bank account transactions',
                    Icons.account_balance_outlined,
                  ),
                  (
                    'debit_card',
                    'Debit Card',
                    'Track a debit card and its messages',
                    Icons.payment_outlined,
                  ),
                  (
                    'credit_card',
                    'Credit Card',
                    'Track credit card spending and payments',
                    Icons.credit_card_outlined,
                  ),
                ]) ...[
                  const SizedBox(height: 8),
                  Material(
                    color: _type == entry.$1
                        ? FolioColors.accent
                        : FolioColors.card,
                    borderRadius: BorderRadius.circular(16),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: _type == entry.$1
                              ? FolioColors.green
                              : Colors.transparent,
                          width: 1.4,
                        ),
                      ),
                      leading: Icon(entry.$4, color: FolioColors.text),
                      title: Text(
                        entry.$2,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        entry.$3,
                        style: const TextStyle(
                          color: FolioColors.muted,
                          fontSize: 13,
                        ),
                      ),
                      onTap: () => Navigator.pop(context, entry.$1),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _type = picked);
  }

  Future<void> _pickBank() async {
    final picked = await showBankPicker(context);
    if (picked == null) return;
    setState(() {
      _bank.text = picked.name;
      _sender.text = picked.sender;
    });
  }

  Widget _markPreview() {
    if (_imagePath != null && accountImageReady(_imagePath!)) {
      return accountImage(_imagePath!, 72);
    }
    if (_iconKey != null) {
      return _MarkChoice(icon: accountMarkIcon(_iconKey!), size: 72);
    }
    final bank = _needsBank ? bankByName(_bank.text.trim()) : null;
    if (bank != null) return BankMark(bank: bank, size: 72);
    return _MarkChoice(icon: accountIcon(_type), size: 72);
  }

  Future<void> _pickMark() async {
    final picked = await showModalBottomSheet<_MarkResult>(
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Account icon', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final choice in accountIconChoices)
                    InkWell(
                      onTap: () => Navigator.pop(context, _MarkResult.icon(choice.$1)),
                      borderRadius: BorderRadius.circular(16),
                      child: _MarkChoice(icon: choice.$2, size: 52),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (_needsBank && bankByName(_bank.text.trim()) != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: BankMark(bank: bankByName(_bank.text.trim())!, size: 44),
                  title: const Text('Use the bank logo'),
                  onTap: () => Navigator.pop(context, const _MarkResult.clear()),
                ),
              if (!kIsWeb)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.photo_outlined, color: FolioColors.text),
                  title: const Text('Upload a photo'),
                  onTap: () => Navigator.pop(context, const _MarkResult.upload()),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (picked.upload) {
      final photo = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512, imageQuality: 80);
      if (photo == null || !mounted) return;
      setState(() {
        _markTouched = true;
        _iconKey = null;
        _imagePath = photo.path;
      });
      return;
    }
    setState(() {
      _markTouched = true;
      _iconKey = picked.iconKey;
      _imagePath = null;
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
      'include_in_net': _includeInNet,
    };
    setState(() => _busy = true);
    try {
      final store = context.read<FolioStore>();
      final id = widget.existing?.id ?? await store.createAccount(body);
      if (widget.existing != null) await store.updateAccount(id, body);
      if (_markTouched && id.isNotEmpty) {
        if (_imagePath != null) {
          await AccountMarks.instance.saveUpload(id, _imagePath!);
        } else if (_iconKey != null) {
          await AccountMarks.instance.setIcon(id, _iconKey!);
        } else {
          await AccountMarks.instance.clear(id);
        }
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
      appBar: AppBar(title: Text(editing ? 'Edit account' : 'Add New Account')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          TextField(
            controller: _balance,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
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
          Center(
            child: InkWell(
              onTap: _pickMark,
              borderRadius: BorderRadius.circular(20),
              child: Column(
                children: [
                  _markPreview(),
                  const SizedBox(height: 6),
                  const Text('Icon', style: TextStyle(color: FolioColors.muted, fontSize: 13)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(hintText: 'Account name'),
          ),
          const SizedBox(height: 10),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            tileColor: FolioColors.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            title: const Text(
              'Account type',
              style: TextStyle(color: FolioColors.muted, fontSize: 12),
            ),
            subtitle: Text(
              _typeLabel(_type),
              style: const TextStyle(
                color: FolioColors.text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            trailing: const Icon(Icons.expand_more),
            onTap: _pickType,
          ),
          const SizedBox(height: 10),
          ChoiceChipRow(
            labels: const ['Personal', 'Business'],
            selected: _purpose == 'business' ? 1 : 0,
            onSelect: (index) =>
                setState(() => _purpose = index == 1 ? 'business' : 'personal'),
          ),
          if (_needsBank) ...[
            const SizedBox(height: 10),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              tileColor: FolioColors.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              title: const Text(
                'Bank',
                style: TextStyle(color: FolioColors.muted, fontSize: 12),
              ),
              subtitle: Text(
                _bank.text.trim().isEmpty
                    ? 'Select a value'
                    : _bank.text.trim(),
                style: TextStyle(
                  color: _bank.text.trim().isEmpty
                      ? FolioColors.muted
                      : FolioColors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: const Icon(Icons.expand_more, color: FolioColors.muted),
              onTap: _pickBank,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _last4,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'Last 4 digits of account number',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _sender,
              decoration: const InputDecoration(hintText: 'Short number'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Automations Enabled',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Turn off to stop tracking messages for this account. Past transactions stay, and new ones are not added automatically.',
              ),
              value: _auto,
              activeThumbColor: FolioColors.green,
              onChanged: (value) => setState(() => _auto = value),
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Include in net balance',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'Turn off to leave this account out of the net balance. Its own balance and transactions stay.',
            ),
            value: _includeInNet,
            activeThumbColor: FolioColors.green,
            onChanged: (value) => setState(() => _includeInNet = value),
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            label: editing ? 'Save' : 'Create Account',
            busy: _busy,
            onPressed: _name.text.trim().isEmpty ? null : _save,
          ),
          if (editing) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : _delete,
              child: const Text(
                'Delete account',
                style: TextStyle(color: FolioColors.red),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MarkResult {
  const _MarkResult.icon(this.iconKey) : upload = false;
  const _MarkResult.upload() : iconKey = null, upload = true;
  const _MarkResult.clear() : iconKey = null, upload = false;

  final String? iconKey;
  final bool upload;
}

class _MarkChoice extends StatelessWidget {
  const _MarkChoice({required this.icon, required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    const color = FolioColors.green;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, size: size * 0.46, color: color),
    );
  }
}
