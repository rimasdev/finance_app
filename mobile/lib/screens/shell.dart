import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../capture.dart';
import '../format.dart';
import '../icons.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'accounts_screen.dart';
import 'entry_screens.dart';
import 'explore_screen.dart';
import 'grow_screen.dart';
import 'insights_screen.dart';
import 'timeline_screen.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int _index = 0;

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
    await Navigator.push(context, MaterialPageRoute(builder: (_) => SmsScreen(initialText: text)));
  }

  Future<void> _add() {
    return Navigator.push(context, MaterialPageRoute(builder: (_) => const TransactionFormScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final review = context.watch<FolioStore>().review.length;
    const pages = [DashboardScreen(), InsightsScreen(), TimelineScreen(), GrowScreen(), ExploreScreen()];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      floatingActionButton: _index == 0 || _index == 2
          ? FloatingActionButton(
              backgroundColor: FolioColors.green,
              foregroundColor: Colors.black,
              onPressed: _add,
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF101013),
        indicatorColor: Colors.transparent,
        selectedIndex: _index,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          NavigationDestination(
            icon: _BadgeIcon(icon: Icons.space_dashboard_outlined, count: review),
            selectedIcon: _BadgeIcon(icon: Icons.space_dashboard, count: review, active: true),
            label: 'Dashboard',
          ),
          const NavigationDestination(icon: Icon(Icons.pie_chart_outline), selectedIcon: Icon(Icons.pie_chart), label: 'Insights'),
          const NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Timeline'),
          const NavigationDestination(icon: Icon(Icons.trending_up), selectedIcon: Icon(Icons.trending_up), label: 'Grow'),
          const NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Explore'),
        ],
      ),
    );
  }
}

class _BadgeIcon extends StatelessWidget {
  const _BadgeIcon({required this.icon, required this.count, this.active = false});
  final IconData icon;
  final int count;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: count > 0,
      label: Text('$count'),
      child: Icon(icon, color: active ? Colors.white : FolioColors.muted),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FolioStore>();
    final data = store.dashboard;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: FolioColors.green,
          onRefresh: store.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              SyncLine(syncedLabel(store.syncedAt)),
              if (store.lastError != null) ...[
                const SizedBox(height: 12),
                FolioCard(child: Text(store.lastError!, style: const TextStyle(color: FolioColors.red))),
              ],
              if (store.review.isNotEmpty) ...[
                const SizedBox(height: 12),
                FolioCard(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReviewScreen())),
                  child: Row(
                    children: [
                      const Icon(Icons.sms_outlined, color: FolioColors.green),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          store.review.length == 1
                              ? '1 bank message needs an account'
                              : '${store.review.length} bank messages need an account',
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: FolioColors.muted),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              FolioCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hey ${data?.name ?? store.me?.name ?? ''}', style: const TextStyle(color: FolioColors.muted)),
                    const SizedBox(height: 8),
                    Text(money(data?.spentToday ?? 0), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700)),
                    const Text('Spent today', style: TextStyle(color: FolioColors.muted)),
                  ],
                ),
              ),
              const SectionLabel('Accounts'),
              SizedBox(
                height: 132,
                child: data == null || data.accounts.isEmpty
                    ? FolioCard(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountFormScreen())),
                        child: const Center(child: Text('Add a cash, bank, or card account')),
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
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountsScreen())),
                                child: const Center(child: Icon(Icons.chevron_right)),
                              ),
                            );
                          }
                          final account = data.accounts[index];
                          return SizedBox(
                            width: 230,
                            child: FolioCard(
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountsScreen())),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      IconBubble(icon: accountIcon(account.type), color: const Color(0xFF7EB6FF), size: 32),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(account.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    [
                                      if (account.last4.isNotEmpty) account.last4,
                                      if (account.bankName.isNotEmpty) account.bankName,
                                      if (account.isBusiness) 'Business',
                                    ].join(' · '),
                                    style: const TextStyle(color: FolioColors.muted, fontSize: 12),
                                  ),
                                  const Spacer(),
                                  Text(money(account.balance), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SectionLabel('Top spenders'),
              Text('Where your money went this month', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              if (data == null || data.topSpenders.isEmpty)
                const FolioCard(child: Text('Expenses you add, or that arrive by SMS, show up here.', style: TextStyle(color: FolioColors.muted)))
              else
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.45,
                  children: [
                    for (final spender in data.topSpenders)
                      FolioCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            IconBubble(icon: iconFor(spender.icon), color: colorFromHex(spender.color), size: 36),
                            const Spacer(),
                            Text(spender.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(money(spender.amount), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
