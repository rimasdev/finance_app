import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

class TransactionFormScreen extends StatefulWidget {
  const TransactionFormScreen({super.key});

  @override
  State<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends State<TransactionFormScreen> {
  final _amount = TextEditingController();
  final _merchant = TextEditingController();
  final _note = TextEditingController();
  String _direction = 'expense';
  String? _accountId;
  String? _transferId;
  String? _categoryId;
  bool _business = false;
  DateTime _when = DateTime.now();
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_when));
    setState(() {
      _when = DateTime(date.year, date.month, date.day, time?.hour ?? _when.hour, time?.minute ?? _when.minute);
    });
  }

  Future<void> _save() async {
    final store = context.read<FolioStore>();
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    if (_accountId == null || amount == null || amount <= 0 || _merchant.text.trim().isEmpty) {
      showError(context, Exception('Add an amount, a name, and an account'));
      return;
    }
    if (_direction == 'transfer' && (_transferId == null || _transferId == _accountId)) {
      showError(context, Exception('Pick a different account to transfer to'));
      return;
    }
    setState(() => _busy = true);
    try {
      await store.createTransaction({
        'account_id': _accountId,
        'direction': _direction,
        'amount': amount,
        'merchant': _merchant.text.trim(),
        'note': _note.text.trim(),
        'occurred_at': _when.toUtc().toIso8601String(),
        'scope': _business ? 'business' : 'personal',
        'category_id': ?_categoryId,
        if (_direction == 'transfer') 'transfer_account_id': _transferId,
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
    final store = context.watch<FolioStore>();
    if (_accountId == null && store.accounts.isNotEmpty) {
      _accountId = store.accounts.first.id;
      _business = store.accounts.first.isBusiness;
    }
    final kind = _direction == 'income' ? 'income' : 'expense';
    final categories = store.categories.where((category) => category.kind == kind).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Add transaction')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          ChoiceChipRow(
            labels: const ['Expense', 'Income', 'Transfer'],
            selected: _direction == 'income' ? 1 : _direction == 'transfer' ? 2 : 0,
            onSelect: (index) => setState(() {
              _direction = ['expense', 'income', 'transfer'][index];
              _categoryId = null;
            }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(hintText: 'Rs. 0', fillColor: Colors.transparent),
          ),
          const SizedBox(height: 8),
          TextField(controller: _merchant, decoration: const InputDecoration(hintText: 'Merchant or description')),
          const SizedBox(height: 10),
          if (store.accounts.isEmpty)
            const Text('Add an account first.', style: TextStyle(color: FolioColors.muted))
          else
            DropdownButtonFormField<String>(
            initialValue: _accountId,
            dropdownColor: FolioColors.card,
            decoration: InputDecoration(labelText: _direction == 'transfer' ? 'From account' : 'Account'),
            items: [
              for (final account in store.accounts) DropdownMenuItem(value: account.id, child: Text(account.name)),
            ],
            onChanged: (value) => setState(() {
              _accountId = value;
              final account = store.accounts.where((item) => item.id == value).firstOrNull;
              if (account != null) _business = account.isBusiness;
            }),
          ),
          if (_direction == 'transfer') ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _transferId,
              dropdownColor: FolioColors.card,
              decoration: const InputDecoration(labelText: 'To account'),
              items: [
                for (final account in store.accounts.where((account) => account.id != _accountId))
                  DropdownMenuItem(value: account.id, child: Text(account.name)),
              ],
              onChanged: (value) => setState(() => _transferId = value),
            ),
          ],
          if (_direction != 'transfer') ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              initialValue: _categoryId,
              dropdownColor: FolioColors.card,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Uncategorised')),
                for (final category in categories) DropdownMenuItem(value: category.id, child: Text(category.name)),
              ],
              onChanged: (value) => setState(() => _categoryId = value),
            ),
          ],
          const SizedBox(height: 10),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            tileColor: FolioColors.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Text('Date', style: TextStyle(color: FolioColors.muted, fontSize: 12)),
            subtitle: Text(_when.toLocal().toString().substring(0, 16)),
            onTap: _pickDate,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Business transaction'),
            value: _business,
            activeThumbColor: FolioColors.green,
            onChanged: (value) => setState(() => _business = value),
          ),
          TextField(controller: _note, decoration: const InputDecoration(hintText: 'Note')),
          const SizedBox(height: 16),
          PrimaryButton(label: 'Save', busy: _busy, onPressed: store.accounts.isEmpty ? null : _save),
          if (store.accounts.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Add an account first.', style: TextStyle(color: FolioColors.muted)),
            ),
        ],
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
  late final TextEditingController _body = TextEditingController(text: widget.initialText);
  final _sender = TextEditingController();
  bool _busy = false;
  String? _result;

  @override
  void dispose() {
    _body.dispose();
    _sender.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_body.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final result = await context.read<FolioStore>().ingestSms(_body.text, sender: _sender.text.trim());
      final status = result['status'] as String? ?? '';
      final txn = result['transaction'] as Map<String, dynamic>?;
      setState(() {
        _result = switch (status) {
          'posted' => 'Added ${txn?['merchant'] ?? 'transaction'} to ${txn?['account_name'] ?? 'an account'}.',
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
            'Paste the full message. Takings reads the amount, whether it was a debit or a credit, and the last digits of the account.',
            style: TextStyle(color: FolioColors.muted, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            minLines: 6,
            maxLines: 10,
            decoration: const InputDecoration(hintText: 'Paste the SMS here'),
          ),
          const SizedBox(height: 10),
          TextField(controller: _sender, decoration: const InputDecoration(hintText: 'Sender, optional')),
          const SizedBox(height: 16),
          PrimaryButton(label: 'Add from SMS', busy: _busy, onPressed: _save),
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
          ? const EmptyBlock(icon: Icons.check_circle_outline, title: 'All caught up', body: 'Every bank message is filed.')
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
          Text(widget.txn.merchant, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(moneyLabel(widget.txn), style: const TextStyle(color: FolioColors.muted)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _accountId,
            dropdownColor: FolioColors.card,
            items: [
              for (final account in store.accounts) DropdownMenuItem(value: account.id, child: Text(account.name)),
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
                child: const Text('Ignore', style: TextStyle(color: FolioColors.muted)),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _busy || _accountId == null
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        try {
                          await store.assignTransaction(widget.txn.id, _accountId!, widget.txn.categoryId);
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
    return '$sign · Rs. ${txn.amount.toStringAsFixed(2)}';
  }
}
