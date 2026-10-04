import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../capture.dart';
import '../download.dart';
import '../format.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'accounts_screen.dart';
import 'categories_screen.dart';
import 'entry_screens.dart';
import 'recurring_screen.dart';

class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FolioStore>();
    final me = store.me;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          children: [
            FolioCard(
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: FolioColors.cardHigh,
                    child: Icon(Icons.person),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          me?.name ?? '',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          me?.email ?? '',
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
            ),
            const SectionLabel('Manage'),
            MenuRow(
              icon: Icons.speed_outlined,
              title: 'Budgets',
              subtitle: 'Set limits on the Grow tab',
            ),
            const SizedBox(height: 8),
            MenuRow(
              icon: Icons.category_outlined,
              title: 'Categories',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CategoriesScreen()),
              ),
            ),
            const SizedBox(height: 8),
            MenuRow(
              icon: Icons.event_repeat,
              title: 'Recurring',
              subtitle: 'Repeats, installments, and subscriptions',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RecurringScreen()),
              ),
            ),
            const SizedBox(height: 8),
            MenuRow(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Accounts',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AccountsScreen()),
              ),
            ),
            const SectionLabel('Capture'),
            const _WithdrawalToCash(),
            const SizedBox(height: 8),
            MenuRow(
              icon: Icons.sms_outlined,
              title: 'Paste a bank SMS',
              subtitle: isIosPhone
                  ? 'iPhone cannot read your messages, so paste them here'
                  : 'Add a message the app did not catch',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SmsScreen()),
              ),
            ),
            const SizedBox(height: 8),
            MenuRow(
              icon: Icons.bolt_outlined,
              title: 'Auto-track spending',
              subtitle: isAndroidPhone
                  ? 'Read bank alerts on this phone'
                  : isIosPhone
                  ? 'Runs when a message contains the letter a'
                  : 'Use the phone app',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AutoTrackScreen()),
              ),
            ),
            const SectionLabel('Data'),
            MenuRow(
              icon: Icons.download_outlined,
              title: 'Export to CSV',
              onTap: () async {
                try {
                  final csv = await store.api.exportCsv();
                  final message = await saveCsv('folio.csv', csv);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(message)));
                  }
                } catch (error) {
                  if (context.mounted) showError(context, error);
                }
              },
            ),
            const SizedBox(height: 8),
            MenuRow(
              icon: Icons.calendar_month_outlined,
              title: 'Monthly start date',
              subtitle: 'Day ${me?.monthStartDay ?? 1}',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MonthStartScreen()),
              ),
            ),
            const SizedBox(height: 8),
            MenuRow(
              icon: Icons.star_outline,
              title: 'Preferred accounts',
              subtitle:
                  'Where a bank message goes when it has no account number',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PreferredAccountsScreen(),
                ),
              ),
            ),
            const SectionLabel('Account'),
            MenuRow(icon: Icons.logout, title: 'Sign out', onTap: store.logout),
            const SizedBox(height: 8),
            MenuRow(
              icon: Icons.delete_outline,
              title: 'Delete my data',
              danger: true,
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: FolioColors.card,
                    title: const Text('Delete everything?'),
                    content: const Text(
                      'This removes your accounts, transactions, and login from your server.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  try {
                    await store.deleteEverything();
                  } catch (error) {
                    if (context.mounted) showError(context, error);
                  }
                }
              },
            ),
            const SizedBox(height: 18),
            const Text(
              'Takings stores your numbers on the server you chose. Bank messages are only sent there after you sign in.',
              style: TextStyle(
                color: FolioColors.muted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MonthStartScreen extends StatefulWidget {
  const MonthStartScreen({super.key});

  @override
  State<MonthStartScreen> createState() => _MonthStartScreenState();
}

class _MonthStartScreenState extends State<MonthStartScreen> {
  late final TextEditingController _day;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final current = context.read<FolioStore>().me?.monthStartDay ?? 1;
    _day = TextEditingController(text: '$current');
  }

  @override
  void dispose() {
    _day.dispose();
    super.dispose();
  }

  String _ordinal(int day) {
    if (day >= 11 && day <= 13) return '${day}th';
    return switch (day % 10) {
      1 => '${day}st',
      2 => '${day}nd',
      3 => '${day}rd',
      _ => '${day}th',
    };
  }

  (DateTime, DateTime) _cycle(int day) {
    final today = DateTime.now();
    var start = DateTime(today.year, today.month, day);
    if (today.day < day) start = DateTime(today.year, today.month - 1, day);
    final next = DateTime(start.year, start.month + 1, day);
    return (start, next.subtract(const Duration(days: 1)));
  }

  Future<void> _save() async {
    final day = int.tryParse(_day.text.trim());
    if (day == null || day < 1 || day > 28) {
      showError(context, Exception('Choose a day from 1 to 28'));
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<FolioStore>().updateProfile(monthStartDay: day);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final day = int.tryParse(_day.text.trim());
    final valid = day != null && day >= 1 && day <= 28;
    final cycle = valid ? _cycle(day) : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Monthly start date')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Choose the day your month starts. Budgets and the timeline follow that cycle.',
            style: TextStyle(color: FolioColors.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _day,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              suffixText: 'of every month',
              hintText: valid ? _ordinal(day) : '1st',
            ),
          ),
          const SizedBox(height: 12),
          if (cycle != null)
            Text.rich(
              TextSpan(
                style: const TextStyle(color: FolioColors.muted),
                children: [
                  const TextSpan(text: 'Your expense cycle runs from '),
                  TextSpan(
                    text: shortRange(cycle.$1, cycle.$2),
                    style: const TextStyle(color: FolioColors.green),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: 'Save changes',
            busy: _busy,
            onPressed: valid ? _save : null,
          ),
        ],
      ),
    );
  }
}

class PreferredAccountsScreen extends StatelessWidget {
  const PreferredAccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FolioStore>();
    final groups = <String, List<AccountModel>>{};
    for (final account in store.accounts) {
      final key = account.smsSender.trim().isNotEmpty
          ? account.smsSender.trim()
          : account.bankName.trim();
      if (key.isEmpty) continue;
      groups.putIfAbsent(key, () => []).add(account);
    }
    final keys = groups.keys.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('Preferred accounts')),
      body: keys.isEmpty
          ? const EmptyBlock(
              icon: Icons.account_balance_outlined,
              title: 'No bank accounts yet',
              body: 'Add a bank and its SMS sender. Messages without an account number can then land on the account you pick here.',
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Some bank messages leave out the account number. Takings files those on the preferred account for that bank.',
                  style: TextStyle(color: FolioColors.muted, height: 1.4),
                ),
                for (final key in keys) ...[
                  const SizedBox(height: 16),
                  Text(
                    key,
                    style: const TextStyle(
                      color: FolioColors.muted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    initialValue: groups[key]!
                        .where((account) => account.preferred)
                        .map((account) => account.id)
                        .firstOrNull,
                    dropdownColor: FolioColors.card,
                    decoration: const InputDecoration(labelText: 'Account'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('None')),
                      for (final account in groups[key]!)
                        DropdownMenuItem(
                          value: account.id,
                          child: Text(account.name),
                        ),
                    ],
                    onChanged: (value) async {
                      try {
                        for (final account in groups[key]!) {
                          final next = account.id == value;
                          if (account.preferred != next) {
                            await store.updateAccount(account.id, {
                              'preferred': next,
                            });
                          }
                        }
                      } catch (error) {
                        if (context.mounted) showError(context, error);
                      }
                    },
                  ),
                ],
              ],
            ),
    );
  }
}

class _WithdrawalToCash extends StatelessWidget {
  const _WithdrawalToCash();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FolioStore>();
    final cash = store.accounts
        .where((account) => account.type == 'cash')
        .toList();
    final enabled = store.me?.withdrawalToCash ?? false;
    final selected =
        cash.any((account) => account.id == store.me?.cashAccountId)
        ? store.me?.cashAccountId
        : cash.firstOrNull?.id;
    return FolioCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Withdrawals to cash',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'When a bank message is a withdrawal, move that amount into cash. Leave this off to keep it as an expense, then open it and choose Transfer.',
            ),
            value: enabled,
            activeThumbColor: FolioColors.green,
            onChanged: cash.isEmpty
                ? null
                : (value) async {
                    try {
                      await store.updateProfile(
                        withdrawalToCash: value,
                        cashAccountId: value ? selected : null,
                      );
                    } catch (error) {
                      if (context.mounted) showError(context, error);
                    }
                  },
          ),
          if (cash.isEmpty)
            const Text(
              'Add a cash account before turning this on.',
              style: TextStyle(color: FolioColors.muted),
            )
          else if (enabled && cash.length > 1) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: selected,
              dropdownColor: FolioColors.card,
              decoration: const InputDecoration(labelText: 'Cash account'),
              items: [
                for (final account in cash)
                  DropdownMenuItem(
                    value: account.id,
                    child: Text(account.name),
                  ),
              ],
              onChanged: (value) async {
                if (value == null) return;
                try {
                  await store.updateProfile(cashAccountId: value);
                } catch (error) {
                  if (context.mounted) showError(context, error);
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}

class AutoTrackScreen extends StatefulWidget {
  const AutoTrackScreen({super.key});

  @override
  State<AutoTrackScreen> createState() => _AutoTrackScreenState();
}

class _AutoTrackScreenState extends State<AutoTrackScreen>
    with WidgetsBindingObserver {
  bool _notifications = false;
  bool _sms = false;
  bool _enabled = true;
  bool _shortcutReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    if (isIosPhone) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _offerShortcut());
    }
  }

  Future<void> _markShortcutReady() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('iosShortcutRevision', 5);
    await prefs.setBool('iosShortcutCreated', true);
    if (!mounted) return;
    setState(() => _shortcutReady = true);
  }

  Future<void> _offerShortcut() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getInt('iosShortcutRevision') == 5) {
      await _markShortcutReady();
      return;
    }
    final opened = await Capture.openMessageShortcut();
    if (!opened) return;
    await prefs.setBool('iosShortcutOffered', true);
    await _markShortcutReady();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final notifications = await Capture.notificationAccessEnabled();
    final sms = await Capture.smsPermissionGranted();
    final enabled = await Capture.autoTrackEnabled();
    final prefs = await SharedPreferences.getInstance();
    final shortcutReady = prefs.getInt('iosShortcutRevision') == 5;
    if (!mounted) return;
    setState(() {
      _notifications = notifications;
      _sms = sms;
      _enabled = enabled;
      _shortcutReady = shortcutReady;
    });
  }

  Future<void> _restartGuide() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('iosShortcutRevision');
    await prefs.remove('iosShortcutCreated');
    await prefs.remove('iosShortcutOffered');
    if (!mounted) return;
    setState(() => _shortcutReady = false);
  }

  @override
  Widget build(BuildContext context) {
    final tracked = context.watch<FolioStore>().dashboard?.smsCount ?? 0;
    final active = isIosPhone
        ? _shortcutReady
        : isAndroidPhone && _enabled && _notifications;
    return Scaffold(
      appBar: AppBar(title: const Text('Auto-track')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (active) ...[
            const Icon(
              Icons.verified_user_outlined,
              size: 56,
              color: FolioColors.green,
            ),
            const SizedBox(height: 12),
            const Text(
              'Auto-tracking is on',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              isIosPhone
                  ? 'In Shortcuts, open the Automation tab. That message row must say Run Immediately. The shortcut in the other tab does not start on its own.'
                  : 'Bank alerts on this phone are saved to Takings.',
              style: const TextStyle(color: FolioColors.muted, height: 1.4),
            ),
            const SizedBox(height: 16),
            FolioCard(
              child: Text(
                '${tracked.toString().padLeft(2, '0')} transactions tracked from SMS',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: MenuRow(
                    icon: Icons.menu_book_outlined,
                    title: 'Restart guide',
                    onTap: _restartGuide,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: MenuRow(
                    icon: Icons.fact_check_outlined,
                    title: 'Re-test setup',
                    onTap: () => showSetupTest(context),
                  ),
                ),
              ],
            ),
          ] else if (isIosPhone) ...[
            const Text(
              'Step 1',
              style: TextStyle(color: FolioColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 6),
            const Text(
              'Add the Takings shortcut',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Delete the old Run Takings shortcut first. After you add this one, the top line must say Receive Images and 18 more from Nowhere, and the where line must say Message contains a. Then open the Automation tab and turn the automation on.',
              style: TextStyle(color: FolioColors.muted, height: 1.4),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Add iOS shortcut',
              onPressed: () async {
                final opened = await Capture.openMessageShortcut();
                if (!context.mounted) return;
                if (!opened) {
                  showError(
                    context,
                    'The shortcut could not be opened. Install Takings on this iPhone and try again.',
                  );
                  return;
                }
                await _markShortcutReady();
              },
            ),
          ] else if (!isAndroidPhone)
            const EmptyBlock(
              icon: Icons.phone_iphone,
              title: 'Use the phone app',
              body: 'Automatic tracking runs on Android, or on iPhone through a Shortcut.',
            )
          else ...[
            const Text(
              'Takings watches bank alerts on this phone and sends only messages that look like a debit or credit to your server. Codes and other chats stay on the phone.',
              style: TextStyle(color: FolioColors.muted, height: 1.4),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto-track on this phone'),
              value: _enabled,
              activeThumbColor: FolioColors.green,
              onChanged: (value) async {
                await Capture.setAutoTrack(value);
                setState(() => _enabled = value);
              },
            ),
            const SizedBox(height: 8),
            MenuRow(
              icon: Icons.notifications_outlined,
              title: 'Notification access',
              subtitle: _notifications
                  ? 'On'
                  : 'Off — this is the usual way to catch bank alerts',
              onTap: Capture.openNotificationAccess,
            ),
            const SizedBox(height: 8),
            MenuRow(
              icon: Icons.sms_outlined,
              title: 'SMS access',
              subtitle: _sms
                  ? 'On'
                  : 'Optional, for messages that do not show a notification',
              onTap: () async {
                await Capture.requestSmsPermission();
                await _load();
              },
            ),
            const SizedBox(height: 16),
            const Text(
              'Put the last 4 digits and the SMS sender on each account. A message is filed only when those digits match. Turn auto-track off on an account you do not want recorded.',
              style: TextStyle(
                color: FolioColors.muted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 16),
          MenuRow(
            icon: Icons.star_outline,
            title: 'Preferred accounts',
            subtitle: 'Used when the message has no account number',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PreferredAccountsScreen(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          MenuRow(
            icon: Icons.fact_check_outlined,
            title: 'Test your setup',
            subtitle: 'Check a sample message against your accounts',
            onTap: () => showSetupTest(context),
          ),
        ],
      ),
    );
  }
}
