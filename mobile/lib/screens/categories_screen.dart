import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../icons.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  String _kind = 'expense';

  Future<void> _add() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FolioColors.card,
        title: Text('New $_kind category'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: 'Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await context.read<FolioStore>().createCategory(name, _kind);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<FolioStore>().categories.where((category) => category.kind == _kind).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: FolioColors.green,
        foregroundColor: FolioColors.greenInk,
        onPressed: _add,
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          ChoiceChipRow(
            labels: const ['Expense', 'Income'],
            selected: _kind == 'income' ? 1 : 0,
            onSelect: (index) => setState(() => _kind = index == 1 ? 'income' : 'expense'),
          ),
          const SizedBox(height: 14),
          for (final category in categories) ...[
            FolioCard(
              child: Row(
                children: [
                  IconBubble(icon: iconFor(category.icon), color: colorFromHex(category.color)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(category.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          '${category.transactionCount} transaction${category.transactionCount == 1 ? '' : 's'}',
                          style: const TextStyle(color: FolioColors.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (category.transactionCount == 0)
                    IconButton(
                      onPressed: () async {
                        try {
                          await context.read<FolioStore>().deleteCategory(category.id);
                        } catch (error) {
                          if (context.mounted) showError(context, error);
                        }
                      },
                      icon: const Icon(Icons.close, color: FolioColors.muted),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
