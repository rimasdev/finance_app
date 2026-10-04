import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../models.dart';
import '../store.dart';
import '../subscriptions.dart';
import '../subscriptions.dart';
import '../theme.dart';
import '../widgets.dart';

const _kinds = ['repeat', 'installment', 'subscription'];

class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});

  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  int _tab = 2;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FolioStore>();
    final kind = _kinds[_tab];
    final items = store.recurring.where((item) => item.kind == kind).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recurring'),
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RecurringFormScreen(kind: kind),
              ),
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
              labels: const ['Repeat', 'Installment', 'Subscription'],
              selected: _tab,
              onSelect: (index) => setState(() => _tab = index),
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const EmptyBlock(
                    icon: Icons.event_repeat,
                    title: 'No recurring inputs',
                    body:
                        'Add a repeat, an installment plan, or a subscription.',
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final item in items) ...[
                        _RecurringCard(item: item),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: TextButton.icon(
                onPressed: () =>
                    store.setRecurringOnHome(!store.showRecurringHome),
                icon: Icon(
                  store.showRecurringHome
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  color: FolioColors.green,
                ),
                label: const Text('Display on Homepage'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecurringCard extends StatelessWidget {
  const _RecurringCard({required this.item});
  final RecurringModel item;

  @override
  Widget build(BuildContext context) {
    final store = context.read<FolioStore>();
    final progress = item.installmentsTotal == null
        ? null
        : '${item.installmentsDone} of ${item.installmentsTotal}';
    return FolioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SubscriptionMark(name: item.name, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                money(item.amount),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              item.accountName,
              item.interval,
              if (item.active) 'Next ${item.nextOn}' else 'Finished',
              if (progress != null) progress,
            ].where((part) => part.isNotEmpty).join(' · '),
            style: const TextStyle(color: FolioColors.muted, fontSize: 12),
          ),
          if (item.active) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: () async {
                    try {
                      await store.payRecurring(item.id);
                    } catch (error) {
                      if (context.mounted) showError(context, error);
                    }
                  },
                  child: const Text('Record payment'),
                ),
                TextButton(
                  onPressed: () async {
                    try {
                      await store.deleteRecurring(item.id);
                    } catch (error) {
                      if (context.mounted) showError(context, error);
                    }
                  },
                  child: const Text(
                    'Delete',
                    style: TextStyle(color: FolioColors.red),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class RecurringFormScreen extends StatefulWidget {
  const RecurringFormScreen({super.key, required this.kind});
  final String kind;

  @override
  State<RecurringFormScreen> createState() => _RecurringFormScreenState();
}

class _RecurringFormScreenState extends State<RecurringFormScreen> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _count = TextEditingController(text: '12');
  String? _service;
  String? _accountId;
  String _interval = 'monthly';
  DateTime _next = DateTime.now();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _count.dispose();
    super.dispose();
  }

  Future<void> _pickService() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: FolioColors.bg,
      builder: (context) => const _ServicePicker(),
    );
    if (picked == null) return;
    setState(() {
      _service = picked;
      if (picked != 'Other') _name.text = picked;
    });
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _next,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date != null) setState(() => _next = date);
  }

  Future<void> _save() async {
    final store = context.read<FolioStore>();
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    final name =
        widget.kind == 'subscription' && _service != null && _service != 'Other'
        ? _service!
        : _name.text.trim();
    final count = int.tryParse(_count.text.trim());
    if (name.isEmpty || amount == null || amount <= 0 || _accountId == null) {
      showError(context, Exception('Add a name, an amount, and an account'));
      return;
    }
    if (widget.kind == 'installment' && (count == null || count < 1)) {
      showError(context, Exception('Add how many payments'));
      return;
    }
    setState(() => _busy = true);
    try {
      await store.createRecurring({
        'kind': widget.kind,
        'name': name,
        'amount': amount,
        'account_id': _accountId,
        'interval': _interval,
        'next_on': _next.toIso8601String().substring(0, 10),
        'note': '',
        if (widget.kind == 'installment') 'installments_total': count,
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
    _accountId ??= store.accounts.firstOrNull?.id;
    final title = switch (widget.kind) {
      'installment' => 'Installment',
      'subscription' => 'Subscription',
      _ => 'Repeat',
    };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.kind == 'subscription') ...[
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              tileColor: FolioColors.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              title: const Text(
                'Service',
                style: TextStyle(color: FolioColors.muted, fontSize: 12),
              ),
              subtitle: Text(_service ?? 'Choose a subscription'),
              trailing: const Icon(Icons.arrow_drop_down),
              onTap: _pickService,
            ),
            if (_service == 'Other') ...[
              const SizedBox(height: 10),
              TextField(
                controller: _name,
                decoration: const InputDecoration(hintText: 'Service name'),
              ),
            ],
          ] else
            TextField(
              controller: _name,
              decoration: InputDecoration(
                hintText: widget.kind == 'installment'
                    ? 'What are you paying off'
                    : 'Name',
              ),
            ),
          const SizedBox(height: 10),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(hintText: 'Rs. 0'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _accountId,
            dropdownColor: FolioColors.card,
            decoration: const InputDecoration(labelText: 'Account'),
            items: [
              for (final account in store.accounts)
                DropdownMenuItem(value: account.id, child: Text(account.name)),
            ],
            onChanged: (value) => setState(() => _accountId = value),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _interval,
            dropdownColor: FolioColors.card,
            decoration: const InputDecoration(labelText: 'Every'),
            items: const [
              DropdownMenuItem(value: 'weekly', child: Text('Week')),
              DropdownMenuItem(value: 'monthly', child: Text('Month')),
              DropdownMenuItem(value: 'yearly', child: Text('Year')),
            ],
            onChanged: (value) =>
                setState(() => _interval = value ?? 'monthly'),
          ),
          if (widget.kind == 'installment') ...[
            const SizedBox(height: 10),
            TextField(
              controller: _count,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Number of payments',
              ),
            ),
          ],
          const SizedBox(height: 10),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            tileColor: FolioColors.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            title: const Text(
              'Next payment',
              style: TextStyle(color: FolioColors.muted, fontSize: 12),
            ),
            subtitle: Text(longDay(_next)),
            onTap: _pickDate,
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Save',
            busy: _busy,
            onPressed: store.accounts.isEmpty ? null : _save,
          ),
        ],
      ),
    );
  }
}

class _ServicePicker extends StatefulWidget {
  const _ServicePicker();

  @override
  State<_ServicePicker> createState() => _ServicePickerState();
}

class _ServicePickerState extends State<_ServicePicker> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = matchingSubscriptions(_query.text);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: 520,
          child: Column(
            children: [
              const SizedBox(height: 8),
              const Text(
                'Subscriptions',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _query,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Search Netflix, Dialog, ChatGPT',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final name in matches)
                      ListTile(
                        leading: SubscriptionMark(name: name, size: 32),
                        title: Text(name),
                        onTap: () => Navigator.pop(context, name),
                      ),
                    ListTile(
                      title: const Text('Other'),
                      subtitle: const Text(
                        'Type a service that is not in the list',
                      ),
                      onTap: () => Navigator.pop(context, 'Other'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
