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

  Future<bool> _confirmRemove(CategoryModel category) async {
    final children = context.read<FolioStore>().categories.where((item) => item.parentId == category.id).toList();
    final used = category.transactionCount > 0 || children.any((child) => child.transactionCount > 0);
    if (children.isEmpty && !used) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FolioColors.card,
        title: Text('Delete ${category.name}?'),
        content: Text(
          children.isNotEmpty
              ? 'Its subcategories will be removed too. Transactions in them will be left uncategorised.'
              : 'Its ${category.transactionCount} transaction${category.transactionCount == 1 ? '' : 's'} will be left uncategorised.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _remove(CategoryModel category) async {
    try {
      await context.read<FolioStore>().deleteCategory(category.id);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final store = context.read<FolioStore>();
    final current = displayCategories(store.categories.where((category) => category.kind == _kind));
    final ordered = reorderCategoryList(current, oldIndex, newIndex);
    try {
      await store.reorderCategories(_kind, ordered);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = displayCategories(
      context.watch<FolioStore>().categories.where((category) => category.kind == _kind),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: FolioColors.green,
        foregroundColor: FolioColors.greenInk,
        onPressed: () => _add(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: ChoiceChipRow(
              labels: const ['Expense', 'Income'],
              selected: _kind == 'income' ? 1 : 0,
              onSelect: (index) => setState(() => _kind = index == 1 ? 'income' : 'expense'),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
              buildDefaultDragHandles: false,
              itemCount: categories.length,
              onReorderItem: _reorder,
              itemBuilder: (context, index) {
                final category = categories[index];
                final child = category.parentId != null && categories.any((item) => item.id == category.parentId);
                return Padding(
                  key: ValueKey(category.id),
                  padding: EdgeInsets.only(left: child ? 28 : 0, bottom: 8),
                  child: Row(
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(Icons.drag_handle, color: FolioColors.muted),
                        ),
                      ),
                      Expanded(
                        child: Dismissible(
                          key: ValueKey('delete-${category.id}'),
                          direction: DismissDirection.endToStart,
                          confirmDismiss: (_) => _confirmRemove(category),
                          onDismissed: (_) => _remove(category),
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8E3A3A),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: const Icon(Icons.delete_outline, color: Colors.white),
                          ),
                          child: _CategoryTile(
                            category: category,
                            onEdit: () => _rename(category),
                            onAdd: child ? null : () => _add(parent: category),
                          ),
                        ),
                      ),
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

/// Moves one row, keeps a category's subcategories with it, and lets a subcategory land under another category.
List<CategoryModel> reorderCategoryList(List<CategoryModel> items, int oldIndex, int newIndex) {
  if (items.isEmpty || oldIndex < 0 || oldIndex >= items.length || oldIndex == newIndex) return items;
  if (newIndex < 0) newIndex = 0;
  if (newIndex >= items.length) newIndex = items.length - 1;
  if (newIndex == oldIndex) return items;

  final parentIds = {for (final item in items) if (_isParentRow(item, items)) item.id};
  final moving = items[oldIndex];
  final next = [...items]..removeAt(oldIndex);
  next.insert(newIndex, moving);
  if (parentIds.contains(moving.id)) {
    final children = [for (final item in items) if (item.parentId == moving.id) item];
    final childIds = {for (final child in children) child.id};
    final stripped = [for (final item in next) if (!childIds.contains(item.id)) item];
    final at = stripped.indexWhere((item) => item.id == moving.id);
    stripped.insertAll(at + 1, children);
    return stripped;
  }

  String? parentId;
  final at = next.indexWhere((item) => item.id == moving.id);
  for (var i = at - 1; i >= 0; i--) {
    if (parentIds.contains(next[i].id)) {
      parentId = next[i].id;
      break;
    }
  }
  if (parentId == moving.parentId) return next;
  next[at] = moving.copyWith(parentId: parentId, clearParent: parentId == null);
  return next;
}

bool _isParentRow(CategoryModel item, List<CategoryModel> items) {
  final known = {for (final row in items) row.id};
  final parentId = item.parentId;
  return parentId == null || parentId.isEmpty || !known.contains(parentId);
}

List<CategoryModel> displayCategories(Iterable<CategoryModel> categories) {
  return [for (final group in _groups(categories)) ...[group.$1, ...group.$2]];
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
  const _CategoryTile({required this.category, required this.onEdit, this.onAdd});

  final CategoryModel category;
  final VoidCallback onEdit;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return FolioCard(
      child: Row(
        children: [
          IconBubble(icon: iconFor(category.icon), color: colorFromHex(category.color)),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: onEdit,
              behavior: HitTestBehavior.opaque,
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
          ),
          if (onAdd != null)
            GestureDetector(
              onTap: onAdd,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.create_new_folder_outlined, color: FolioColors.accent, size: 20),
              ),
            ),
        ],
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
