import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../icons.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'insights_screen.dart';
import 'loans_screen.dart';

String _loanSubtitle(FolioStore store) {
  final open = store.loans.where((loan) => !loan.settled);
  if (open.isEmpty) return 'People, businesses, or your own accounts';
  final owed = open
      .where((loan) => loan.isLend)
      .fold(0.0, (sum, loan) => sum + loan.remaining);
  final owe = open
      .where((loan) => !loan.isLend)
      .fold(0.0, (sum, loan) => sum + loan.remaining);
  return 'Owed to you ${money(owed)} · You owe ${money(owe)}';
}

class GrowScreen extends StatelessWidget {
  const GrowScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FolioStore>();
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: FolioColors.green,
          onRefresh: store.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            children: [
              MonthSwitcher(
                label: store.insights?.label ?? monthTitle(store.month),
                onPrevious: () => store.shiftMonth(-1),
                onNext: () => store.shiftMonth(1),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _NetCard(
                      label: 'Personal',
                      value: store.personalNet,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _NetCard(
                      label: 'Business',
                      value: store.businessNet,
                    ),
                  ),
                ],
              ),
              const SectionLabel('Loans'),
              MenuRow(
                icon: Icons.handshake_outlined,
                title: 'Lend and borrow',
                subtitle: _loanSubtitle(store),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoansScreen()),
                ),
              ),
              const SectionLabel('Budgets'),
              if (store.budgets.isEmpty)
                EmptyBlock(
                  icon: Icons.speed_outlined,
                  title: 'Ready to budget?',
                  body: 'Pick a category, set a limit, and Takings tracks the rest.',
                  action: PrimaryButton(
                    label: 'Create budget',
                    onPressed: () => _createBudget(context, store),
                  ),
                )
              else ...[
                for (final budget in store.budgets) ...[
                  FolioCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconBubble(
                              icon: iconFor(budget.categoryIcon),
                              color: colorFromHex(budget.categoryColor),
                              size: 36,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    budget.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '${budget.categoryName} · ${budget.accountName}',
                                    style: const TextStyle(
                                      color: FolioColors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => store.deleteBudget(budget.id),
                              icon: const Icon(
                                Icons.delete_outline,
                                color: FolioColors.muted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${money(budget.spent)} of ${money(budget.limitAmount)}',
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: budget.limitAmount == 0
                                ? 0
                                : (budget.spent / budget.limitAmount).clamp(
                                    0,
                                    1,
                                  ),
                            minHeight: 6,
                            backgroundColor: FolioColors.line,
                            color: budget.spent > budget.limitAmount
                                ? FolioColors.red
                                : FolioColors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                PrimaryButton(
                  label: 'Create budget',
                  onPressed: () => _createBudget(context, store),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createBudget(BuildContext context, FolioStore store) async {
    final amount = TextEditingController();
    final expenseCategories = store.categories
        .where((category) => category.kind == 'expense' && category.parentId == null)
        .toList();
    String? categoryId = expenseCategories
        .where((category) => !store.budgets.any((budget) => budget.categoryId == category.id))
        .firstOrNull
        ?.id ??
        expenseCategories.firstOrNull?.id;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: FolioColors.bg,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Category budget',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: categoryId,
                    isExpanded: true,
                    dropdownColor: FolioColors.card,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: [
                      for (final category in expenseCategories)
                        DropdownMenuItem(
                          value: category.id,
                          child: CategoryMenuLabel(
                            name: category.name,
                            icon: category.icon,
                            color: category.color,
                          ),
                        ),
                    ],
                    onChanged: (value) => setSheet(() => categoryId = value),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(hintText: 'Monthly limit'),
                  ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: 'Save',
                    onPressed: () => Navigator.pop(context, true),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (saved != true || !context.mounted) return;
    final limit = double.tryParse(amount.text.trim().replaceAll(',', ''));
    final category = store.categories.where((item) => item.id == categoryId).firstOrNull;
    if (category == null || limit == null || limit <= 0) {
      showError(context, Exception('Pick a category and a limit'));
      return;
    }
    try {
      await store.createBudget({
        'name': category.name,
        'limit_amount': limit,
        'category_id': category.id,
      });
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }
}

class _NetCard extends StatelessWidget {
  const _NetCard({required this.label, required this.value});
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return FolioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: FolioColors.muted)),
          const SizedBox(height: 6),
          Text(
            money(value),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
