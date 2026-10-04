import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_art_file.dart';
import 'banks.dart';
import 'icons.dart';
import 'models.dart';
import 'theme.dart';

const accountIconChoices = <(String, IconData)>[
  ('payments', Icons.payments_rounded),
  ('wallet', Icons.account_balance_wallet_rounded),
  ('bank', Icons.account_balance_rounded),
  ('card', Icons.credit_card_rounded),
  ('savings', Icons.savings_rounded),
  ('cash', Icons.money_rounded),
];

IconData accountMarkIcon(String key) {
  for (final choice in accountIconChoices) {
    if (choice.$1 == key) return choice.$2;
  }
  return Icons.account_balance_wallet_rounded;
}

class AccountMarks extends ChangeNotifier {
  AccountMarks._();

  static final instance = AccountMarks._();

  static const _prefKey = 'account_marks';

  final Map<String, String> _marks = {};

  String? markFor(String id) => _marks[id];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    _marks.clear();
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            _marks[entry.key.toString()] = entry.value.toString();
          }
        }
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> setIcon(String id, String key) async {
    _marks[id] = 'icon:$key';
    await _write();
    notifyListeners();
  }

  Future<void> saveUpload(String id, String sourcePath) async {
    final stored = await persistAccountImage(id, sourcePath);
    if (stored == null) return;
    _marks[id] = 'file:$stored';
    await _write();
    notifyListeners();
  }

  Future<void> clear(String id) async {
    _marks.remove(id);
    await _write();
    notifyListeners();
  }

  Future<void> _write() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, jsonEncode(_marks));
  }
}

class AccountFace extends StatelessWidget {
  const AccountFace({super.key, required this.account, this.size = 48});

  final AccountModel account;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AccountMarks.instance,
      builder: (context, _) => accountFaceFor(account, size),
    );
  }
}

Widget accountFaceFor(AccountModel account, double size) {
  final mark = AccountMarks.instance.markFor(account.id);
  if (mark != null && mark.startsWith('file:')) {
    final path = mark.substring(5);
    if (accountImageReady(path)) return accountImage(path, size);
  }
  if (mark != null && mark.startsWith('icon:')) {
    return _MarkIcon(icon: accountMarkIcon(mark.substring(5)), size: size);
  }
  final bank = bankByName(account.bankName);
  if (bank != null) return BankMark(bank: bank, size: size);
  return _MarkIcon(icon: accountIcon(account.type), size: size);
}

class _MarkIcon extends StatelessWidget {
  const _MarkIcon({required this.icon, required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    const color = FolioColors.green;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, size: size * 0.5, color: color),
    );
  }
}
