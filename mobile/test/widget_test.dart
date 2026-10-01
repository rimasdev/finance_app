import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/format.dart';
import 'package:folio/screens/accounts_screen.dart';
import 'package:folio/store.dart';
import 'package:folio/theme.dart';
import 'package:provider/provider.dart';

void main() {
  test('money formats rupees the way the ledger shows them', () {
    expect(money(4778), 'Rs. 4,778.00');
    expect(money(-4778), 'Rs. -4,778.00');
    expect(money(-115158.53, accounting: true), '-Rs. 115,158.53');
    expect(money(0), 'Rs. 0.00');
  });

  test('month keys stay zero padded', () {
    expect(monthKey(DateTime(2026, 9)), '2026-09');
  });

  testWidgets('a new account opens the bank list', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => FolioStore(),
        child: MaterialApp(theme: buildFolioTheme(), home: const AccountFormScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Select Bank'), findsOneWidget);
    expect(find.text('Commercial Bank of Sri Lanka'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'samp');
    await tester.pump();
    expect(find.text('Sampath Bank'), findsOneWidget);
    expect(find.text('Bank of Ceylon'), findsNothing);
  });
}
