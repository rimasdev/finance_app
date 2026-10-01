import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../capture.dart';
import '../download.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'accounts_screen.dart';
import 'categories_screen.dart';
import 'entry_screens.dart';

class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FolioStore>();
    final me = store.me;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            FolioCard(
              child: Row(
                children: [
                  const CircleAvatar(backgroundColor: FolioColors.cardHigh, child: Icon(Icons.person)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(me?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        Text(me?.email ?? '', style: const TextStyle(color: FolioColors.muted, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SectionLabel('Manage'),
            MenuRow(
              icon: Icons.savings_outlined,
              title: 'Budgets',
              subtitle: 'Set limits on the Grow tab',
            ),
            const SizedBox(height: 8),
            MenuRow(
              icon: Icons.category_outlined,
              title: 'Categories',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoriesScreen())),
            ),
            const SizedBox(height: 8),
            MenuRow(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Accounts',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountsScreen())),
            ),
            const SectionLabel('Capture'),
            MenuRow(
              icon: Icons.sms_outlined,
              title: 'Paste a bank SMS',
              subtitle: isIosPhone ? 'iPhone cannot read your messages, so paste them here' : 'Add a message the app did not catch',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SmsScreen())),
            ),
            const SizedBox(height: 8),
            MenuRow(
              icon: Icons.bolt_outlined,
              title: 'Auto-track spending',
              subtitle: isAndroidPhone
                  ? 'Read bank alerts on this phone'
                  : isIosPhone
                      ? 'Create the shortcut that files bank SMS'
                      : 'Use the phone app',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AutoTrackScreen())),
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
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
              onTap: () => _pickStartDay(context, store),
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
                    content: const Text('This removes your accounts, transactions, and login from your server.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
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
              style: TextStyle(color: FolioColors.muted, fontSize: 12, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickStartDay(BuildContext context, FolioStore store) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: FolioColors.bg,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: 320,
          child: ListView(
            children: [
              for (var day = 1; day <= 28; day++)
                ListTile(
                  title: Text('Day $day'),
                  trailing: day == store.me?.monthStartDay ? const Icon(Icons.check, color: FolioColors.green) : null,
                  onTap: () => Navigator.pop(context, day),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    try {
      await store.updateProfile(monthStartDay: picked);
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }
}

class AutoTrackScreen extends StatefulWidget {
  const AutoTrackScreen({super.key});

  @override
  State<AutoTrackScreen> createState() => _AutoTrackScreenState();
}

class _AutoTrackScreenState extends State<AutoTrackScreen> with WidgetsBindingObserver {
  bool _notifications = false;
  bool _sms = false;
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
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
    if (!mounted) return;
    setState(() {
      _notifications = notifications;
      _sms = sms;
      _enabled = enabled;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Auto-track')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (isIosPhone) ...[
            const Text(
              'iPhone will not let an app read SMS. The same result comes from a Shortcut, the way Kiwi does it. When a bank text arrives, Shortcuts runs Save data to Takings.',
              style: TextStyle(color: FolioColors.muted, height: 1.4),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Create the SMS shortcut',
              onPressed: () async {
                final opened = await Capture.openMessageShortcut();
                if (!context.mounted) return;
                if (!opened) {
                  showError(context, 'Open the Shortcuts app, then follow the steps below.');
                }
              },
            ),
            const SizedBox(height: 16),
            const Text('In Shortcuts, create a personal automation:', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('1. When I receive a message, set Message contains Rs.'),
            const SizedBox(height: 6),
            const Text('2. Add the action Save data to Takings.'),
            const SizedBox(height: 6),
            const Text('3. Set message to Shortcut Input, and sender to Sender.'),
            const SizedBox(height: 6),
            const Text('4. Turn off Ask Before Running, then allow the shortcut.'),
            const SizedBox(height: 16),
            const Text(
              'Sign in to Takings first. Pick the bank and last 4 digits on each account so the message lands on the right one.',
              style: TextStyle(color: FolioColors.muted, fontSize: 13, height: 1.4),
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
              subtitle: _notifications ? 'On' : 'Off — this is the usual way to catch bank alerts',
              onTap: Capture.openNotificationAccess,
            ),
            const SizedBox(height: 8),
            MenuRow(
              icon: Icons.sms_outlined,
              title: 'SMS access',
              subtitle: _sms ? 'On' : 'Optional, for messages that do not show a notification',
              onTap: () async {
                await Capture.requestSmsPermission();
                await _load();
              },
            ),
            const SizedBox(height: 16),
            const Text(
              'Put the last 4 digits and the SMS sender on each account. A message is filed only when those digits match. Turn auto-track off on an account you do not want recorded.',
              style: TextStyle(color: FolioColors.muted, fontSize: 13, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}
