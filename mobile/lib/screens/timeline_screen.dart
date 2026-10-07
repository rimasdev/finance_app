import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'entry_screens.dart';
import 'insights_screen.dart';

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

double _netBalance(FolioStore store) {
  final accounts = store.accounts.where((account) {
    if (store.accountFilter != null && account.id != store.accountFilter)
      return false;
    if (store.scope == 'personal' && account.isBusiness) return false;
    if (store.scope == 'business' && !account.isBusiness) return false;
    if (store.accountFilter == null && !account.includeInNet) return false;
    return true;
  });
  return accounts.fold(0.0, (sum, account) => sum + account.balance);
}

class _TimelineScreenState extends State<TimelineScreen> {
  final _search = TextEditingController();
  bool _searching = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FolioStore>();
    final data = store.timeline;
    final accountName = store.accountFilter == null
        ? 'All accounts'
        : store.accounts
                  .where((account) => account.id == store.accountFilter)
                  .map((account) => account.name)
                  .firstOrNull ??
              'All accounts';
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: FolioColors.green,
          onRefresh: store.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _searching
                        ? TextField(
                            controller: _search,
                            autofocus: true,
                            decoration: const InputDecoration(
                              hintText: 'Search merchant',
                            ),
                            onSubmitted: store.setSearch,
                          )
                        : Align(
                            alignment: Alignment.centerLeft,
                            child: PopupMenuButton<String?>(
                              initialValue: store.accountFilter,
                              onSelected: store.setAccountFilter,
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: null,
                                  child: Text('All accounts'),
                                ),
                                for (final account in store.accounts)
                                  PopupMenuItem(
                                    value: account.id,
                                    child: Text(account.name),
                                  ),
                              ],
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: FolioColors.card,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.account_balance_wallet_outlined,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        accountName,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const Icon(Icons.arrow_drop_down),
                                  ],
                                ),
                              ),
                            ),
                          ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _searching = !_searching),
                    icon: Icon(_searching ? Icons.close : Icons.search),
                  ),
                ],
              ),
              MonthSwitcher(
                label: data == null
                    ? monthTitle(store.month)
                    : shortRange(data.from, data.to),
                onPrevious: () => store.shiftMonth(-1),
                onNext: () => store.shiftMonth(1),
              ),
              const SizedBox(height: 8),
              ChoiceChipRow(
                labels: const ['All', 'Personal', 'Business'],
                selectedColors: const [FolioColors.green, FolioColors.accent, FolioColors.accent],
                selectedInks: const [FolioColors.greenInk, FolioColors.accentInk, FolioColors.accentInk],
                selected: store.scope == 'business'
                    ? 2
                    : store.scope == 'personal'
                    ? 1
                    : 0,
                onSelect: (index) => store.setScope(
                  index == 2
                      ? 'business'
                      : index == 1
                      ? 'personal'
                      : 'all',
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Net balance',
                style: TextStyle(color: FolioColors.muted),
              ),
              Text(
                money(_netBalance(store), accounting: true),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _Total(
                      label: 'Income',
                      value: data?.income ?? 0,
                      color: FolioColors.green,
                    ),
                  ),
                  Expanded(
                    child: _Total(
                      label: 'Expenses',
                      value: data?.expenses ?? 0,
                      color: FolioColors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SyncLine(syncedLabel(store.syncedAt)),
              if (data == null || data.days.isEmpty)
                const EmptyBlock(
                  icon: Icons.receipt_long_outlined,
                  title: 'Nothing in this period',
                  body: 'Transactions from SMS and ones you add yourself land here.',
                )
              else
                for (final day in data.days) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 18, bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            longDay(day.date),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          money(day.total),
                          style: const TextStyle(color: FolioColors.muted),
                        ),
                      ],
                    ),
                  ),
                  for (final txn in day.items) ...[
                    TxnTile(
                      txn: txn,
                      onTap: () async {
                        if (txn.direction != 'loan') {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  TransactionFormScreen(existing: txn),
                            ),
                          );
                          return;
                        }
                        final removed = await showModalBottomSheet<bool>(
                          context: context,
                          backgroundColor: FolioColors.card,
                          builder: (context) => SafeArea(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  title: Text(txn.title),
                                  subtitle: Text(
                                    txn.note.isEmpty
                                        ? txn.categoryName
                                        : txn.note,
                                  ),
                                ),
                                ListTile(
                                  leading: const Icon(
                                    Icons.delete_outline,
                                    color: FolioColors.red,
                                  ),
                                  title: const Text('Delete'),
                                  onTap: () => Navigator.pop(context, true),
                                ),
                              ],
                            ),
                          ),
                        );
                        if (removed == true && context.mounted) {
                          try {
                            await store.deleteTransaction(txn.id);
                          } catch (error) {
                            if (context.mounted) showError(context, error);
                          }
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.value, required this.color});
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: FolioColors.muted)),
        Text(
          money(value),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}
