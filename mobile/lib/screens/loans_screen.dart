import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

class LoansScreen extends StatefulWidget {
  const LoansScreen({super.key});

  @override
  State<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends State<LoansScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FolioStore>();
    final open = store.loans.where((loan) => !loan.settled).toList();
    final owedToMe = open
        .where((loan) => loan.isLend)
        .fold(0.0, (sum, loan) => sum + loan.remaining);
    final iOwe = open
        .where((loan) => !loan.isLend)
        .fold(0.0, (sum, loan) => sum + loan.remaining);
    final showing = store.loans
        .where((loan) => _tab == 1 ? loan.isLend : !loan.isLend)
        .toList();
    final openHere = showing.where((loan) => !loan.settled).toList();
    final settled = showing.where((loan) => loan.settled).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Loans')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: FolioColors.green,
        foregroundColor: FolioColors.greenInk,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LoanFormScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New loan'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          FolioCard(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: _NetFigure(label: 'Owed to you', value: owedToMe),
                ),
                Container(width: 1, height: 36, color: FolioColors.line),
                Expanded(
                  child: _NetFigure(label: 'You owe', value: iOwe),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _LoanTabs(
            selected: _tab,
            onSelect: (index) => setState(() => _tab = index),
          ),
          const SizedBox(height: 14),
          if (store.loans.isEmpty)
            const EmptyBlock(
              icon: Icons.handshake_outlined,
              title: 'No loans yet',
              body: 'Lend to a person or a business, borrow from them, or move a loan between your own accounts.',
            )
          else if (showing.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: Text(
                  _tab == 0 ? 'Nothing borrowed' : 'Nothing lent',
                  style: const TextStyle(color: FolioColors.muted),
                ),
              ),
            )
          else ...[
            for (final group in _loanGroups(openHere)) ...[
              if (group.length == 1)
                _LoanCard(loan: group.first)
              else
                _LoanGroup(loans: group),
              const SizedBox(height: 10),
            ],
            if (settled.isNotEmpty) ...[
              const SectionLabel('Settled'),
              for (final group in _loanGroups(settled)) ...[
                if (group.length == 1)
                  _LoanCard(loan: group.first)
                else
                  _LoanGroup(loans: group),
                const SizedBox(height: 10),
              ],
            ],
          ],
        ],
      ),
    );
  }
}

List<List<LoanModel>> _loanGroups(List<LoanModel> loans) {
  final order = <String>[];
  final grouped = <String, List<LoanModel>>{};
  for (final loan in loans) {
    final key = '${loan.partyKind}|${loan.partyName.trim().toLowerCase()}';
    grouped.putIfAbsent(key, () {
      order.add(key);
      return [];
    }).add(loan);
  }
  return [for (final key in order) grouped[key]!];
}

class _LoanGroup extends StatefulWidget {
  const _LoanGroup({required this.loans});

  final List<LoanModel> loans;

  @override
  State<_LoanGroup> createState() => _LoanGroupState();
}

class _LoanGroupState extends State<_LoanGroup> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final first = widget.loans.first;
    final remaining = widget.loans.fold(0.0, (sum, loan) => sum + loan.remaining);
    final total = widget.loans.fold(0.0, (sum, loan) => sum + loan.amount);
    final settled = widget.loans.every((loan) => loan.settled);
    return Column(
      children: [
        FolioCard(
          onTap: () => setState(() => _open = !_open),
          child: Row(
            children: [
              IconBubble(
                icon: switch (first.partyKind) {
                  'business' => Icons.storefront_outlined,
                  'account' => Icons.account_balance_outlined,
                  _ => Icons.person_outline,
                },
                color: FolioColors.accent,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      first.partyName,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.loans.length} loans',
                      style: const TextStyle(color: FolioColors.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    money(settled ? total : remaining),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    settled ? 'Settled' : 'of ${money(total)}',
                    style: const TextStyle(color: FolioColors.muted, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              Icon(
                _open ? Icons.expand_less : Icons.expand_more,
                color: FolioColors.muted,
              ),
            ],
          ),
        ),
        if (_open)
          for (final loan in widget.loans) ...[
            const SizedBox(height: 8),
            _LoanCard(loan: loan),
          ],
      ],
    );
  }
}

class _LoanTabs extends StatelessWidget {
  const _LoanTabs({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    const labels = ['Borrowed', 'Lent'];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: FolioColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () => onSelect(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: selected == i
                          ? FolioColors.accent
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: selected == i
                            ? FolioColors.accentInk
                            : FolioColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NetFigure extends StatelessWidget {
  const _NetFigure({required this.label, required this.value});
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: FolioColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          money(value),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _LoanCard extends StatelessWidget {
  const _LoanCard({required this.loan});
  final LoanModel loan;

  @override
  Widget build(BuildContext context) {
    final store = context.read<FolioStore>();
    final overdue =
        !loan.settled &&
        loan.dueOn.isNotEmpty &&
        DateTime.parse(loan.dueOn).isBefore(DateTime.now());
    final kind = _partyLabel(loan.partyKind);
    final progress = loan.amount <= 0
        ? 0.0
        : (loan.repaid / loan.amount).clamp(0.0, 1.0).toDouble();
    return FolioCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 4, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: IconBubble(
                  icon: _partyIcon(loan.partyKind),
                  color: FolioColors.accent,
                  size: 40,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loan.partyName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      kind,
                      style: const TextStyle(
                        color: FolioColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      money(loan.settled ? loan.amount : loan.remaining),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      loan.settled ? 'Settled' : 'of ${money(loan.amount)}',
                      style: const TextStyle(
                        color: FolioColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Delete loan',
                visualDensity: VisualDensity.compact,
                onPressed: () => _confirmDelete(context, store),
                icon: const Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: FolioColors.muted,
                ),
              ),
            ],
          ),
          if (!loan.settled) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 2,
                  backgroundColor: FolioColors.line,
                  color: FolioColors.text,
                ),
              ),
            ),
          ],
          if (_detail.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                _detail,
                style: TextStyle(
                  color: overdue ? FolioColors.red : FolioColors.muted,
                  fontSize: 12,
                ),
              ),
            ),
          ],
          if (!loan.settled)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _recordPayment(context, store, loan),
                child: const Text('Record payment'),
              ),
            ),
        ],
      ),
    );
  }

  static String _partyLabel(String kind) {
    return switch (kind) {
      'business' => 'Business',
      'account' => 'Account',
      _ => 'Person',
    };
  }

  static IconData _partyIcon(String kind) {
    return switch (kind) {
      'business' => Icons.storefront_outlined,
      'account' => Icons.account_balance_outlined,
      _ => Icons.person_outline,
    };
  }

  String get _detail {
    final parts = <String>[
      if (loan.dueOn.isNotEmpty) 'Due ${_dueLabel(loan.dueOn)}',
      if (loan.accountName.isNotEmpty)
        loan.isLend ? 'From ${loan.accountName}' : 'Into ${loan.accountName}',
      if (loan.counterpartyAccountName.isNotEmpty)
        loan.isLend
            ? 'To ${loan.counterpartyAccountName}'
            : 'From ${loan.counterpartyAccountName}',
    ];
    return parts.join(' · ');
  }

  Future<void> _confirmDelete(BuildContext context, FolioStore store) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FolioColors.card,
        title: const Text('Delete this loan?'),
        content: Text(
          'This removes the loan with ${loan.partyName}, including the opening amount and any payments.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: FolioColors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await store.deleteLoan(loan.id);
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  Future<void> _recordPayment(
    BuildContext context,
    FolioStore store,
    LoanModel loan,
  ) async {
    final amount = TextEditingController();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: FolioColors.bg,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Payment ${loan.isLend ? 'from' : 'to'} ${loan.partyName}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '${money(loan.remaining)} still open',
              style: const TextStyle(color: FolioColors.muted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(hintText: 'Amount'),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Save payment',
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !context.mounted) return;
    final value = double.tryParse(amount.text.trim().replaceAll(',', ''));
    if (value == null || value <= 0) {
      showError(context, Exception('Add the amount paid'));
      return;
    }
    try {
      await store.repayLoan(loan.id, {'amount': value});
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }
}

class LoanFormScreen extends StatefulWidget {
  const LoanFormScreen({super.key});

  @override
  State<LoanFormScreen> createState() => _LoanFormScreenState();
}

class _LoanFormScreenState extends State<LoanFormScreen> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _kind = 'lend';
  String _partyKind = 'person';
  String? _accountId;
  String? _otherId;
  DateTime? _due;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_internal) return;
    final accounts = context.read<FolioStore>().accounts;
    _accountId ??= accounts.firstOrNull?.id;
    _otherId ??= accounts
        .where((account) => account.id != _accountId)
        .firstOrNull
        ?.id;
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _internal => _partyKind == 'account';

  String get _accountLabel {
    if (_kind == 'lend') return 'From account';
    return 'Into account';
  }

  String get _otherLabel => _kind == 'lend' ? 'To account' : 'From account';

  bool get _canPickContact =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  Future<void> _pickContact() async {
    try {
      final contact = await FlutterContacts.native.showPicker();
      final name = contact?.displayName?.trim() ?? '';
      if (!mounted) return;
      if (contact != null && name.isEmpty) {
        showError(context, 'That contact has no name.');
        return;
      }
      if (name.isNotEmpty) setState(() => _name.text = name);
    } catch (_) {
      if (mounted) showError(context, 'Contacts could not be opened.');
    }
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? now.add(const Duration(days: 30)),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _due = picked);
  }

  Future<void> _save() async {
    final store = context.read<FolioStore>();
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      showError(context, Exception('Add the loan amount'));
      return;
    }
    if (_internal && _accountId == null) {
      showError(context, Exception('Choose an account'));
      return;
    }
    if (_internal) {
      if (_otherId == null || _otherId == _accountId) {
        showError(context, Exception('Choose two different accounts'));
        return;
      }
    } else if (_name.text.trim().isEmpty) {
      showError(context, Exception('Add the person or business name'));
      return;
    }
    setState(() => _busy = true);
    try {
      await store.createLoan({
        'kind': _kind,
        'party_kind': _partyKind,
        'party_name': _internal ? '' : _name.text.trim(),
        'account_id': _accountId,
        'counterparty_account_id': _internal ? _otherId : null,
        'amount': amount,
        'due_on': _due?.toIso8601String().substring(0, 10),
        'note': _note.text.trim(),
      });
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<FolioStore>().accounts;
    final others = accounts
        .where((account) => account.id != _accountId)
        .toList();
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
        appBar: AppBar(title: const Text('New loan')),
        body: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const Text(
              'Lend money out, or borrow it in. A loan between your own accounts, such as personal into business, uses My account.',
              style: TextStyle(color: FolioColors.muted, height: 1.4),
            ),
            const SizedBox(height: 16),
            ChoiceChipRow(
              labels: const ['Lend', 'Borrow'],
              selected: _kind == 'borrow' ? 1 : 0,
              onSelect: (index) =>
                  setState(() => _kind = index == 1 ? 'borrow' : 'lend'),
            ),
            const SizedBox(height: 12),
            ChoiceChipRow(
              labels: const ['Person', 'Business', 'My account'],
              selected: _partyKind == 'business'
                  ? 1
                  : _partyKind == 'account'
                  ? 2
                  : 0,
              onSelect: (index) => setState(() {
                _partyKind = ['person', 'business', 'account'][index];
                if (_internal && _accountId == null) {
                  final accounts = context.read<FolioStore>().accounts;
                  _accountId = accounts.firstOrNull?.id;
                  _otherId ??= accounts
                      .where((account) => account.id != _accountId)
                      .firstOrNull
                      ?.id;
                }
              }),
            ),
            const SizedBox(height: 16),
            if (!_internal)
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: _partyKind == 'business'
                      ? 'Business name'
                      : 'Person name',
                  suffixIcon: _partyKind == 'person' && _canPickContact
                      ? IconButton(
                          tooltip: 'Choose from contacts',
                          onPressed: _pickContact,
                          icon: const Icon(Icons.contacts_outlined),
                        )
                      : null,
                ),
              )
            else
              const SizedBox.shrink(),
            if (!_internal) const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _internal
                  ? (accounts.any((account) => account.id == _accountId)
                        ? _accountId
                        : null)
                  : (_accountId ?? ''),
              isExpanded: true,
              dropdownColor: FolioColors.card,
              decoration: InputDecoration(labelText: _accountLabel),
              items: [
                if (!_internal)
                  const DropdownMenuItem(value: '', child: Text('None')),
                for (final account in accounts)
                  DropdownMenuItem(
                    value: account.id,
                    child: Text(
                      '${account.name} · ${account.isBusiness ? 'Business' : 'Personal'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() {
                _accountId = value == null || value.isEmpty ? null : value;
                if (_otherId == _accountId) {
                  _otherId = accounts
                      .where((account) => account.id != _accountId)
                      .firstOrNull
                      ?.id;
                }
              }),
            ),
            if (!_internal && _accountId == null) ...[
              const SizedBox(height: 8),
              const Text(
                'None leaves the account balance as it is. Use it when you borrowed or lent the money earlier.',
                style: TextStyle(
                  color: FolioColors.muted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
            if (_internal) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: others.any((account) => account.id == _otherId)
                    ? _otherId
                    : null,
                isExpanded: true,
                dropdownColor: FolioColors.card,
                decoration: InputDecoration(labelText: _otherLabel),
                items: [
                  for (final account in others)
                    DropdownMenuItem(
                      value: account.id,
                      child: Text(
                        '${account.name} · ${account.isBusiness ? 'Business' : 'Personal'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _otherId = value),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: const [GroupedAmountFormatter()],
              decoration: const InputDecoration(hintText: 'Amount'),
            ),
            const SizedBox(height: 10),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              tileColor: FolioColors.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              title: const Text(
                'Due date',
                style: TextStyle(color: FolioColors.muted, fontSize: 12),
              ),
              subtitle: Text(
                _due == null ? 'Optional' : _dueLabel(_due!.toIso8601String()),
                style: const TextStyle(
                  color: FolioColors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: const Icon(Icons.event, color: FolioColors.muted),
              onTap: _pickDue,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              decoration: const InputDecoration(hintText: 'Note, optional'),
            ),
            const SizedBox(height: 20),
            PrimaryButton(label: 'Save loan', busy: _busy, onPressed: _save),
          ],
        ),
      ),
    );
  }
}

String _dueLabel(String iso) {
  final date = DateTime.parse(iso);
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}
