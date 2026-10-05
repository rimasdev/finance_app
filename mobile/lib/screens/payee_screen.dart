import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

class PayeePickerScreen extends StatefulWidget {
  const PayeePickerScreen({super.key, required this.store, this.current = ''});

  final FolioStore store;
  final String current;

  @override
  State<PayeePickerScreen> createState() => _PayeePickerScreenState();
}

class _PayeePickerScreenState extends State<PayeePickerScreen> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<String> get _matches {
    final query = _query.text.trim().toLowerCase();
    final seen = <String>{};
    final names = <String>[];
    void add(String raw) {
      final name = raw.trim();
      if (name.isEmpty || name.toLowerCase() == 'transfer') return;
      if (widget.store.hiddenPayees.contains(name.toLowerCase())) return;
      if (query.isNotEmpty && !name.toLowerCase().contains(query)) return;
      if (!seen.add(name.toLowerCase())) return;
      names.add(name);
    }

    for (final payee in widget.store.payees) {
      add(payee.label);
    }
    for (final day in widget.store.timeline?.days ?? const <TimelineDay>[]) {
      for (final txn in day.items) {
        add(txn.merchant);
      }
    }
    for (final txn in widget.store.review) {
      add(txn.merchant);
    }
    return names;
  }

  Future<void> _create() async {
    final created = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => NewPayeeScreen(store: widget.store, initialName: _query.text.trim()),
      ),
    );
    if (!mounted || created == null) return;
    setState(() => _query.clear());
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    final searching = _query.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payees'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              onPressed: _create,
              icon: const Icon(Icons.add_circle, color: Color(0xFF3B82F6), size: 32),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _query,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Search name or number',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: matches.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 36),
                      child: Text(
                        searching ? 'No payees match' : 'Use Payees for who you pay, like Dialog or Keells. Start with (+) to create the first one.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: FolioColors.muted, height: 1.4),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      for (final name in matches)
                        Dismissible(
                    key: ValueKey(name.toLowerCase()),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      color: const Color(0xFF8E3A3A),
                      child: const Icon(Icons.delete_outline, color: Colors.white),
                    ),
                    onDismissed: (_) {
                      widget.store.deletePayeeLabel(name);
                      setState(() {});
                    },
                    child: ListTile(
                      title: Text(name),
                      trailing: name == widget.current
                          ? const Icon(Icons.check_rounded, color: Color(0xFF7EB6FF))
                          : null,
                      onTap: () => Navigator.pop(context, name),
                    ),
                  ),
                      if (searching && !matches.any((name) => name.toLowerCase() == _query.text.trim().toLowerCase()))
                        ListTile(
                          title: Text('Create "${_query.text.trim()}"'),
                          onTap: _create,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class NewPayeeScreen extends StatefulWidget {
  const NewPayeeScreen({super.key, required this.store, this.initialName = ''});

  final FolioStore store;
  final String initialName;

  @override
  State<NewPayeeScreen> createState() => _NewPayeeScreenState();
}

class _NewPayeeScreenState extends State<NewPayeeScreen> {
  late final TextEditingController _name = TextEditingController(text: widget.initialName);
  final _number = TextEditingController();
  var _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final number = _number.text.trim();
    if (name.isEmpty) {
      showError(context, Exception('Add a name'));
      return;
    }
    setState(() => _busy = true);
    final label = number.isEmpty ? name : '$name · $number';
    try {
      await widget.store.savePayee(name, number);
      if (!mounted) return;
      Navigator.pop(context, label);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payee')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _number,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(hintText: 'Phone number, optional'),
          ),
          const SizedBox(height: 20),
          PrimaryButton(label: 'Save', busy: _busy, onPressed: _save),
        ],
      ),
    );
  }
}
