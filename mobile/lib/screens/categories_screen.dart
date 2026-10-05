import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../icons.dart';
import '../models.dart';
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

  Future<void> _add({CategoryModel? parent}) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _NameDialog(
        title: parent == null ? 'New $_kind category' : 'Subcategory of ${parent.name}',
        action: 'Add',
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await context.read<FolioStore>().createCategory(name, parent?.kind ?? _kind, parentId: parent?.id);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _rename(CategoryModel category) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _NameDialog(title: 'Edit ${category.name}', action: 'Save', initial: category.name),
    );
    if (name == null || name.isEmpty || name == category.name || !mounted) return;
    try {
      await context.read<FolioStore>().updateCategory(category.id, name);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _remove(CategoryModel category) async {
    final hasChildren = context.read<FolioStore>().categories.any((item) => item.parentId == category.id);
    if (hasChildren) {
      showError(context, 'Remove its subcategories first');
      return;
    }
    final used = category.transactionCount > 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FolioColors.card,
        title: Text('Delete ${category.name}?'),
        content: Text(
          used
              ? 'Its ${category.transactionCount} transaction${category.transactionCount == 1 ? '' : 's'} will be left uncategorised.'
              : 'This category will be removed.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<FolioStore>().deleteCategory(category.id);
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
        onPressed: () => _add(),
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
          for (final group in _groups(categories)) ...[
            if (group.$2.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                child: Text(
                  group.$1.name,
                  style: const TextStyle(color: FolioColors.muted, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
            _CategoryTile(
              category: group.$1,
              onEdit: () => _rename(group.$1),
              onAdd: group.$1.parentId == null ? () => _add(parent: group.$1) : null,
              onDelete: () => _remove(group.$1),
            ),
            for (final child in group.$2)
              Padding(
                padding: const EdgeInsets.only(left: 18),
                child: _CategoryTile(
                  category: child,
                  onEdit: () => _rename(child),
                  onDelete: () => _remove(child),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

List<(CategoryModel, List<CategoryModel>)> _groups(Iterable<CategoryModel> categories) {
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
    for (final parent in parents) (parent, children[parent.id] ?? const []),
  ];
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onEdit, required this.onDelete, this.onAdd});

  final CategoryModel category;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FolioCard(
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
            IconButton(
              tooltip: 'Edit',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, color: FolioColors.muted, size: 20),
            ),
            if (onAdd != null)
              IconButton(
                tooltip: 'Add subcategory',
                onPressed: onAdd,
                icon: const Icon(Icons.create_new_folder_outlined, color: FolioColors.accent, size: 20),
              ),
            IconButton(
              tooltip: 'Delete',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, color: FolioColors.red, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.action, this.initial = ''});

  final String title;
  final String action;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: FolioColors.card,
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Name'),
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, _controller.text.trim()), child: Text(widget.action)),
      ],
    );
  }
}
