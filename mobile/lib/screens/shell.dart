import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../account_art.dart';
import '../capture.dart';
import '../format.dart';
import '../fx.dart';
import '../models.dart';
import '../icons.dart';
import '../store.dart';
import '../subscriptions.dart';
import '../theme.dart';
import '../widgets.dart';
import 'accounts_screen.dart';
import 'entry_screens.dart';
import 'explore_screen.dart';
import 'grow_screen.dart';
import 'insights_screen.dart';
import 'recurring_screen.dart';
import 'timeline_screen.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int _index = 0;
  bool _addMenu = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _takeShare());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<FolioStore>().refresh().catchError((_) {});
      _takeShare();
    }
  }

  Future<void> _takeShare() async {
    final text = await Capture.takeSharedText();
    if (!mounted || text == null || text.trim().isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SmsScreen(initialText: text)),
    );
  }

  Future<void> _add() {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TransactionFormScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final review = context.watch<FolioStore>().review.length;
    const pages = [
      DashboardScreen(),
      InsightsScreen(),
      TimelineScreen(),
      GrowScreen(),
      ExploreScreen(),
    ];
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _index, children: pages),
      floatingActionButton: _index == 0 || _index == 2
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_addMenu) ...[
                  _AddChoice(
                    icon: Icons.edit_outlined,
                    label: 'Add manually',
                    onTap: () {
                      setState(() => _addMenu = false);
                      _add();
                    },
                  ),
                  const SizedBox(height: 8),
                  _AddChoice(
                    icon: Icons.sms_outlined,
                    label: 'Add from SMS',
                    onTap: () {
                      setState(() => _addMenu = false);
                      showSmsSheet(context);
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                FloatingActionButton(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF1A1A1C),
                  onPressed: () => setState(() => _addMenu = !_addMenu),
                  child: Icon(_addMenu ? Icons.close : Icons.add),
                ),
              ],
            )
          : null,
      bottomNavigationBar: _PillNav(
        index: _index,
        review: review,
        onSelect: (value) => setState(() {
          _index = value;
          _addMenu = false;
        }),
      ),
    );
  }
}

String _reviewLabel(FolioStore store) {
  final cards = unlinkedCardDigits(store);
  if (cards.length == 1) return 'Link card ••••${cards.first} to an account';
  if (cards.length > 1) return 'Link ${cards.length} cards to your accounts';
  return store.review.length == 1
      ? '1 bank message needs an account'
      : '${store.review.length} bank messages need an account';
}

class _PillNav extends StatelessWidget {
  const _PillNav({
    required this.index,
    required this.review,
    required this.onSelect,
  });

  final int index;
  final int review;
  final ValueChanged<int> onSelect;

  static const _items = [
    (Icons.space_dashboard_outlined, Icons.space_dashboard, 'Dashboard'),
    (Icons.pie_chart_outline, Icons.pie_chart, 'Insights'),
    (Icons.receipt_long_outlined, Icons.receipt_long, 'Timeline'),
    (Icons.trending_up, Icons.trending_up, 'Grow'),
    (Icons.explore_outlined, Icons.explore, 'Explore'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF202020),
            borderRadius: BorderRadius.circular(32),
          ),
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                for (var i = 0; i < _items.length; i++)
                  Expanded(
                    child: _PillItem(
                      icon: index == i ? _items[i].$2 : _items[i].$1,
                      label: _items[i].$3,
                      selected: index == i,
                      count: i == 0 ? review : 0,
                      onTap: () => onSelect(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PillItem extends StatelessWidget {
  const _PillItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.count,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF1A1A1C) : const Color(0xFFB7B7C2);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 36,
              height: 28,
              decoration: BoxDecoration(
                color: selected ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Badge(
                isLabelVisible: count > 0,
                label: Text('$count'),
                child: Icon(icon, size: 18, color: color),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFFB7B7C2),
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeHero extends StatefulWidget {
  const _HomeHero({
    required this.greeting,
    required this.balance,
    required this.upcoming,
  });

  final String greeting;
  final double balance;
  final List<RecurringModel> upcoming;

  @override
  State<_HomeHero> createState() => _HomeHeroState();
}

class _HomeHeroState extends State<_HomeHero> {
  Timer? _timer;
  var _index = 0;
  var _open = false;

  List<RecurringModel> get _sorted {
    final items = [...widget.upcoming];
    items.sort((a, b) {
      final left = DateTime.tryParse(a.nextOn);
      final right = DateTime.tryParse(b.nextOn);
      if (left == null && right == null) return 0;
      if (left == null) return 1;
      if (right == null) return -1;
      return left.compareTo(right);
    });
    return items;
  }

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(_HomeHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_index >= _sorted.length) _index = 0;
    _arm();
  }

  void _arm() {
    _timer?.cancel();
    if (_open || _sorted.length < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || _open) return;
      setState(() => _index = (_index + 1) % _sorted.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    _arm();
  }

  @override
  Widget build(BuildContext context) {
    final items = _sorted;
    final shown = items.isEmpty
        ? const <RecurringModel>[]
        : _open
            ? items
            : [items[_index.clamp(0, items.length - 1)]];
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: FolioColors.card,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.greeting, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 18),
                  Text(
                    money(widget.balance),
                    style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Total balance',
                    style: TextStyle(color: FolioColors.muted, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
          if (shown.isNotEmpty)
            ColoredBox(
              color: const Color(0xFF1C1E1D),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
                child: Column(
                  children: [
                    if (_open)
                      for (final item in shown) _UpcomingRow(item: item)
                    else
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        child: _UpcomingRow(
                          key: ValueKey(shown.first.id),
                          item: shown.first,
                        ),
                      ),
                    if (items.length > 1)
                      IconButton(
                        onPressed: _toggle,
                        tooltip: _open ? 'Show the next one' : 'Show all',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          _open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          color: FolioColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({super.key, required this.item});

  final RecurringModel item;

  @override
  Widget build(BuildContext context) {
    final mark = item.provider.isNotEmpty ? item.provider : item.name;
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RecurringScreen()),
      ),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SubscriptionMark(name: mark, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${item.name}  →  ${item.currency == 'LKR' ? money(item.amount) : foreignAmount(item.currency, item.amount)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _duePhrase(item.nextOn),
              style: const TextStyle(color: FolioColors.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

String _duePhrase(String iso) {
  final date = DateTime.tryParse(iso);
  if (date == null || iso.isEmpty) return '';
  final today = DateTime.now();
  final start = DateTime(today.year, today.month, today.day);
  final target = DateTime(date.year, date.month, date.day);
  final days = target.difference(start).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  if (days > 1) return 'In $days days';
  if (days == -1) return 'Yesterday';
  return '${-days} days ago';
}

String _firstName(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
  return parts.isEmpty ? '' : parts.first;
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, required this.color});

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: FolioCard(
        color: FolioColors.card,
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 18,
              height: 3,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 10),
            Text(label, style: const TextStyle(color: FolioColors.muted, fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              money(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeLabel extends StatelessWidget {
  const _HomeLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Text(
        text,
        style: const TextStyle(
          color: FolioColors.muted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.9,
        ),
      ),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FolioStore>();
    final data = store.dashboard;
    final first = _firstName(data?.name ?? store.me?.name ?? '');
    final balance = (data?.accounts ?? store.accounts)
        .where((account) => account.includeInNet)
        .fold(0.0, (sum, account) => sum + account.balance);
    final spentToday = data?.spentToday ?? 0;
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
                  const Icon(Icons.check_circle, color: FolioColors.green, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      syncedLabel(store.syncedAt),
                      style: const TextStyle(color: FolioColors.muted, fontSize: 13),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ExploreScreen()),
                    ),
                    icon: const Icon(Icons.notifications_outlined, color: FolioColors.muted),
                  ),
                ],
              ),
              if (store.lastError != null) ...[
                const SizedBox(height: 12),
                FolioCard(
                  child: Text(
                    store.lastError!,
                    style: const TextStyle(color: FolioColors.red),
                  ),
                ),
              ],
              if (store.review.isNotEmpty) ...[
                const SizedBox(height: 12),
                FolioCard(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => unlinkedCardDigits(store).isEmpty
                          ? const ReviewScreen()
                          : const AccountsScreen(),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.sms_outlined, color: FolioColors.green),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_reviewLabel(store))),
                      const Icon(Icons.chevron_right, color: FolioColors.muted),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              _HomeHero(
                greeting: first.isEmpty ? '👋  Hey' : '👋  Hey $first',
                balance: balance,
                upcoming: store.showRecurringHome
                    ? store.recurring.where((item) => item.active).toList()
                    : const <RecurringModel>[],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _MiniStat(
                    label: 'Income',
                    value: store.timeline?.income ?? 0,
                    color: const Color(0xFF7EB6FF),
                  ),
                  const SizedBox(width: 10),
                  _MiniStat(
                    label: 'Expenses',
                    value: store.timeline?.expenses ?? 0,
                    color: const Color(0xFFF3A3A8),
                  ),
                  const SizedBox(width: 10),
                  _MiniStat(
                    label: 'Today',
                    value: spentToday,
                    color: FolioColors.green,
                  ),
                ],
              ),
              const _HomeLabel('ACCOUNTS'),
              SizedBox(
                height: 132,
                child: data == null || data.accounts.isEmpty
                    ? FolioCard(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AccountFormScreen(),
                          ),
                        ),
                        child: const Center(
                          child: Text('Add a cash, bank, or card account'),
                        ),
                      )
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: data.accounts.length + 1,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          if (index == data.accounts.length) {
                            return SizedBox(
                              width: 72,
                              child: FolioCard(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const AccountsScreen(),
                                  ),
                                ),
                                child: const Center(
                                  child: Icon(Icons.chevron_right),
                                ),
                              ),
                            );
                          }
                          final account = data.accounts[index];
                          final meta = [
                            if (account.last4.isNotEmpty) account.last4,
                            if (account.smsSender.isNotEmpty)
                              account.smsSender
                            else if (account.bankName.isNotEmpty)
                              account.bankName,
                          ].join(' · ');
                          return SizedBox(
                            width: 230,
                            child: FolioCard(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AccountsScreen(),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      AccountFace(account: account, size: 36),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              account.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontWeight: FontWeight.w700),
                                            ),
                                            if (meta.isNotEmpty)
                                              Text(
                                                meta,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: FolioColors.muted,
                                                  fontSize: 12,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Spacer(),
                                  Text(
                                    money(account.balance),
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const _HomeLabel('TOP SPENDERS'),
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text(
                  'Where your 💸 went this month',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
              if (data == null || data.topSpenders.isEmpty)
                const Text(
                  'Expenses you add, or that arrive by SMS, show up here.',
                  style: TextStyle(color: FolioColors.muted),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: data.topSpenders.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.15,
                  ),
                  itemBuilder: (context, index) {
                    final spender = data.topSpenders[index];
                    final color = colorFromHex(spender.color);
                    return FolioCard(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CategorySpendScreen(
                            name: spender.name,
                            categoryId: spender.categoryId,
                            icon: spender.icon,
                            color: spender.color,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          IconBubble(icon: iconFor(spender.icon), color: color, size: 36),
                          const Spacer(),
                          Text(
                            spender.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            money(spender.amount),
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddChoice extends StatelessWidget {
  const _AddChoice({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: FolioColors.cardHigh,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: FolioColors.green),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
