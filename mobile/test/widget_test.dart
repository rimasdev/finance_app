import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/format.dart';
import 'package:folio/fx.dart';
import 'package:folio/models.dart';
import 'package:folio/screens/accounts_screen.dart';
import 'package:folio/screens/categories_screen.dart';
import 'package:folio/screens/entry_screens.dart';
import 'package:folio/screens/explore_screen.dart';
import 'package:folio/screens/insights_screen.dart';
import 'package:folio/screens/loans_screen.dart';
import 'package:folio/screens/recurring_screen.dart';
import 'package:folio/store.dart';
import 'package:folio/subscriptions.dart';
import 'package:folio/theme.dart';
import 'package:provider/provider.dart';

void main() {
  test('dragging a category keeps its subcategories with it', () {
    CategoryModel row(String id, {String? parentId}) => CategoryModel(
          id: id,
          name: id,
          kind: 'expense',
          icon: 'other',
          color: '#9CA3AF',
          parentId: parentId,
          transactionCount: 0,
        );
    final items = [row('groceries'), row('rice', parentId: 'groceries'), row('outing'), row('phone', parentId: 'utilities'), row('utilities')];
    final moved = reorderCategoryList(displayCategories(items), 0, 4);
    expect(moved.map((item) => item.id).toList(), ['outing', 'utilities', 'phone', 'groceries', 'rice']);
    final shifted = reorderCategoryList(displayCategories(items), 1, 3);
    expect(shifted.map((item) => item.id).toList(), ['groceries', 'outing', 'utilities', 'rice', 'phone']);
    expect(shifted[3].parentId, 'utilities');
    final filed = reorderCategoryList(displayCategories(items), 2, 1);
    expect(filed.firstWhere((item) => item.id == 'outing').parentId, 'groceries');
    final group = reorderCategoryList(displayCategories(items), 3, 1);
    expect(group.firstWhere((item) => item.id == 'utilities').parentId, 'groceries');
    expect(group.firstWhere((item) => item.id == 'phone').parentId, 'groceries');
  });

  test('money formats rupees the way the ledger shows them', () {
    expect(money(4778), 'Rs. 4,778.00');
    expect(money(-4778), 'Rs. -4,778.00');
    expect(money(-115158.53, accounting: true), '-Rs. 115,158.53');
    expect(money(0), 'Rs. 0.00');
  });

  test('a near subscription name still finds its logo', () {
    expect(subscriptionLogo('Spotify'), contains('spotify.png'));
    expect(subscriptionLogo('Spotify Premium'), contains('spotify.png'));
    expect(subscriptionLogo('spotfy'), contains('spotify.png'));
    expect(subscriptionLogo('Rent'), isNull);
    expect(subscriptionLogo('Mint Pay'), contains('mintpay.png'));
    expect(subscriptionLogo('Koko'), contains('koko.png'));
    expect(subscriptionLogo('Payzy'), contains('payzy.png'));
    expect(subscriptionLogo('Snap'), contains('snap.png'));
  });

  test('a foreign subscription is shown in rupees at the saved rate', () {
    const rates = ExchangeRates(date: '2026-10-04', lkrPerUsd: 300, usdPerEur: 0.5, usdPerGbp: 0.75);
    expect(rupeesFor(10, 'USD', rates), money(3000));
    expect(rupeesFor(1, 'EUR', rates), money(600));
    expect(rupeesFor(10, 'LKR', rates), money(10));
    expect(rupeesFor(10, 'USD', null), 'USD 10.00');
    expect(postedAmount(amount: 986.7, currency: 'USD', fxAmount: 2.99), 'USD 2.99');
    expect(postedAmount(amount: 10, currency: 'LKR'), money(10));
    final saved = RecurringModel.fromJson({
      'id': '1',
      'kind': 'installment',
      'name': 'Carnage',
      'amount': 1077.71,
      'note': 'fx:Mint Pay|USD',
    });
    expect(saved.provider, 'Mint Pay');
    expect(saved.currency, 'USD');
    expect(saved.note, isEmpty);
  });

  test('month keys stay zero padded', () {
    expect(monthKey(DateTime(2026, 9)), '2026-09');
  });

  testWidgets('a new account asks for the type before the bank list', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => FolioStore(),
        child: MaterialApp(
          theme: buildFolioTheme(),
          home: const AccountFormScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Select Bank'), findsNothing);
    expect(find.text('Cash Accounts'), findsOneWidget);
    expect(find.text('Include in net balance'), findsOneWidget);
    expect(find.text('Bank'), findsNothing);

    await tester.tap(find.text('Account type'));
    await tester.pumpAndSettle();
    expect(find.text('Select Account Type'), findsOneWidget);
    await tester.tap(find.text('Bank Account'));
    await tester.pumpAndSettle();
    expect(find.text('Bank Accounts'), findsOneWidget);
    expect(find.text('Select a value'), findsOneWidget);
    expect(find.text('Select Bank'), findsNothing);

    await tester.tap(find.text('Bank'));
    await tester.pumpAndSettle();
    expect(find.text('Select Bank'), findsOneWidget);
    expect(find.text('Commercial Bank of Sri Lanka'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'samp');
    await tester.pump();
    expect(find.text('Sampath Bank'), findsOneWidget);
    expect(find.text('Bank of Ceylon'), findsNothing);
  });

  testWidgets('a loan can be between your own accounts', (tester) async {
    final store = FolioStore()
      ..accounts = [
        AccountModel(
          id: 'personal',
          name: 'Personal',
          type: 'bank',
          purpose: 'personal',
          bankName: '',
          last4: '',
          smsSender: '',
          openingBalance: 0,
          balance: 1000,
          automationsEnabled: true,
        ),
        AccountModel(
          id: 'business',
          name: 'Business',
          type: 'bank',
          purpose: 'business',
          bankName: '',
          last4: '',
          smsSender: '',
          openingBalance: 0,
          balance: 200,
          automationsEnabled: true,
        ),
      ];
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => store,
        child: MaterialApp(
          theme: buildFolioTheme(),
          home: const LoanFormScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Lend'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);
    expect(find.text('Borrow'), findsOneWidget);
    expect(find.text('Person'), findsOneWidget);
    expect(find.byTooltip('Choose from contacts'), findsOneWidget);
    expect(find.text('Due date'), findsOneWidget);
    expect(find.text('Optional'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(1), '179372');
    await tester.pump();
    expect(find.text('179,372'), findsOneWidget);
    expect(find.text('To account'), findsNothing);

    await tester.tap(find.text('My account'));
    await tester.pump();
    expect(find.text('From account'), findsOneWidget);
    expect(find.text('To account'), findsOneWidget);
    expect(find.text('Rs. 1,000.00'), findsOneWidget);
    expect(find.text('Rs. 200.00'), findsOneWidget);

    await tester.tap(find.text('Borrow'));
    await tester.pump();
    expect(find.text('Into account'), findsOneWidget);
    expect(find.text('From account'), findsWidgets);
  });

  testWidgets('an existing loan opens for editing', (tester) async {
    final store = FolioStore();
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => store,
        child: MaterialApp(
          theme: buildFolioTheme(),
          home: LoanFormScreen(
            existing: LoanModel(
              id: 'loan',
              kind: 'lend',
              partyKind: 'person',
              partyName: 'Brother',
              counterpartyAccountId: null,
              counterpartyAccountName: '',
              accountId: '',
              accountName: '',
              amount: 179372,
              repaid: 0,
              remaining: 179372,
              dueOn: '',
              note: '',
              settled: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Edit loan'), findsOneWidget);
    expect(find.text('Brother'), findsOneWidget);
    expect(find.text('179,372'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
  });

  testWidgets('an account card shows the bank logo', (tester) async {
    final store = FolioStore()
      ..accounts = [
        AccountModel(
          id: 'combank',
          name: 'Flash Primary',
          type: 'bank',
          purpose: 'personal',
          bankName: 'Commercial Bank of Sri Lanka',
          last4: '8741',
          smsSender: 'COMBANK',
          openingBalance: 0,
          balance: 97.29,
          automationsEnabled: true,
        ),
      ];
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => store,
        child: MaterialApp(
          theme: buildFolioTheme(),
          home: const AccountsScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Flash Primary'), findsOneWidget);
    expect(find.text('8741'), findsOneWidget);
    expect(find.text('Commercial Bank of Sri Lanka'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('an unknown card asks to be linked to an account', (
    tester,
  ) async {
    final store = FolioStore()
      ..accounts = [
        AccountModel(
          id: 'flash',
          name: 'Flash Primary',
          type: 'bank',
          purpose: 'personal',
          bankName: 'Commercial Bank of Sri Lanka',
          last4: '8741',
          smsSender: 'COMBANK',
          openingBalance: 0,
          balance: 100,
          automationsEnabled: true,
        ),
      ]
      ..review = [
        TxnModel(
          id: 'sms',
          accountId: null,
          accountName: '',
          transferAccountId: null,
          transferAccountName: '',
          categoryId: null,
          categoryName: '',
          categoryIcon: 'other',
          categoryColor: '#9CA3AF',
          direction: 'expense',
          amount: 490,
          merchant: 'Kids Mania Kandy',
          note: '',
          occurredAt: DateTime(2026, 10, 1),
          scope: 'personal',
          source: 'sms',
          status: 'needs_review',
          cardLast4: '9383',
        ),
      ];
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => store,
        child: MaterialApp(
          theme: buildFolioTheme(),
          home: const AccountsScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Card ••••9383'), findsOneWidget);
    expect(find.text('Link card'), findsOneWidget);
    expect(find.text('Flash Primary'), findsWidgets);
  });

  testWidgets('a transfer asks for bank charges and an optional description', (
    tester,
  ) async {
    final store = FolioStore()
      ..accounts = [
        AccountModel(
          id: 'from',
          name: 'Flash Primary',
          type: 'bank',
          purpose: 'personal',
          bankName: '',
          last4: '',
          smsSender: '',
          openingBalance: 0,
          balance: 100,
          automationsEnabled: true,
        ),
        AccountModel(
          id: 'to',
          name: 'Cash',
          type: 'cash',
          purpose: 'personal',
          bankName: '',
          last4: '',
          smsSender: '',
          openingBalance: 0,
          balance: 20,
          automationsEnabled: true,
        ),
      ];
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => store,
        child: MaterialApp(
          theme: buildFolioTheme(),
          home: const TransactionFormScreen(),
        ),
      ),
    );
    await tester.pump();
    final expenseBox = tester.widget<Container>(
      find.descendant(of: find.widgetWithText(GestureDetector, 'Expense'), matching: find.byType(Container)).first,
    );
    expect((expenseBox.decoration as BoxDecoration).borderRadius, BorderRadius.circular(8));
    await tester.tap(find.text('Business'));
    await tester.pump();
    final businessBox = tester.widget<Container>(
      find.descendant(of: find.widgetWithText(GestureDetector, 'Business'), matching: find.byType(Container)).first,
    );
    expect((businessBox.decoration as BoxDecoration).color, FolioColors.accent);
    final personalBox = tester.widget<Container>(
      find.descendant(of: find.widgetWithText(GestureDetector, 'Personal'), matching: find.byType(Container)).first,
    );
    final personalDecoration = personalBox.decoration as BoxDecoration;
    final incomeBox = tester.widget<Container>(
      find.descendant(of: find.widgetWithText(GestureDetector, 'Income'), matching: find.byType(Container)).first,
    );
    final incomeDecoration = incomeBox.decoration as BoxDecoration;
    expect(personalDecoration.color, incomeDecoration.color);
    expect((personalDecoration.border as Border).top.color, (incomeDecoration.border as Border).top.color);
    await tester.tap(find.text('Personal'));
    await tester.pump();
    expect(
      (tester.widget<Container>(
        find.descendant(of: find.widgetWithText(GestureDetector, 'Personal'), matching: find.byType(Container)).first,
      ).decoration as BoxDecoration).color,
      FolioColors.accent,
    );
    final expense = tester.getRect(find.widgetWithText(GestureDetector, 'Expense'));
    final income = tester.getRect(find.widgetWithText(GestureDetector, 'Income'));
    final transfer = tester.getRect(find.widgetWithText(GestureDetector, 'Transfer'));
    expect(expense.width, moreOrLessEquals(income.width, epsilon: 1));
    expect(income.width, moreOrLessEquals(transfer.width, epsilon: 1));
    expect(expense.left, 16);
    expect(transfer.right, moreOrLessEquals(tester.getSize(find.byType(ListView)).width - 16, epsilon: 1));
    await tester.tap(find.text('Transfer'));
    await tester.pump();
    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Business'), findsOneWidget);
    expect(find.text('From account'), findsOneWidget);
    expect(find.text('To account'), findsOneWidget);
    expect(find.text('Description, optional'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pump();
    expect(find.text('Bank charges'), findsOneWidget);
    await tester.tap(find.text('Show details'));
    await tester.pump();
    expect(find.text('Hide transaction'), findsOneWidget);
  });

  testWidgets('monthly start date shows the expense cycle', (tester) async {
    final store = FolioStore()
      ..me = UserProfile(
        id: 'me',
        email: 'a@b.c',
        name: 'Rimas',
        currency: 'LKR',
        timezone: 'Asia/Colombo',
        monthStartDay: 1,
      );
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => store,
        child: MaterialApp(
          theme: buildFolioTheme(),
          home: const MonthStartScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Monthly start date'), findsOneWidget);
    expect(find.textContaining('Your expense cycle runs from'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
  });

  testWidgets('a subscription can be picked from the Sri Lanka list', (
    tester,
  ) async {
    final store = FolioStore()
      ..accounts = [
        AccountModel(
          id: 'cash',
          name: 'Cash',
          type: 'cash',
          purpose: 'personal',
          bankName: '',
          last4: '',
          smsSender: '',
          openingBalance: 0,
          balance: 0,
          automationsEnabled: true,
        ),
      ];
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => store,
        child: MaterialApp(
          theme: buildFolioTheme(),
          home: const RecurringFormScreen(kind: 'subscription'),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Choose a subscription'));
    await tester.pumpAndSettle();
    expect(find.text('Netflix'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'peo');
    await tester.pump();
    expect(find.text('Peo TV'), findsOneWidget);
    expect(find.text('Netflix'), findsNothing);
  });

  testWidgets('an installment asks for the shop and the payment', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => FolioStore(),
        child: MaterialApp(
          theme: buildFolioTheme(),
          home: const RecurringFormScreen(kind: 'installment'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Choose Mint Pay, Koko, Payzy, or Snap'), findsOneWidget);
    expect(find.text('Currency'), findsOneWidget);
    expect(find.text('Payee'), findsOneWidget);
    expect(find.text('Choose who you pay'), findsOneWidget);
  });

  testWidgets('a withdrawal can be changed into a transfer to cash', (
    tester,
  ) async {
    final store = FolioStore()
      ..accounts = [
        AccountModel(
          id: 'flash',
          name: 'Flash - Primary Account',
          type: 'bank',
          purpose: 'personal',
          bankName: 'Commercial Bank',
          last4: '9383',
          smsSender: 'COMBANK',
          openingBalance: 0,
          balance: 6000,
          automationsEnabled: true,
        ),
        AccountModel(
          id: 'cash',
          name: 'Cash',
          type: 'cash',
          purpose: 'personal',
          bankName: '',
          last4: '',
          smsSender: '',
          openingBalance: 0,
          balance: 100,
          automationsEnabled: true,
        ),
      ];
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => store,
        child: MaterialApp(
          theme: buildFolioTheme(),
          home: TransactionFormScreen(
            existing: TxnModel(
              id: 'atm',
              accountId: 'flash',
              accountName: 'Flash - Primary Account',
              transferAccountId: null,
              transferAccountName: '',
              categoryId: null,
              categoryName: '',
              categoryIcon: 'other',
              categoryColor: '#9CA3AF',
              direction: 'expense',
              amount: 4000,
              merchant: 'ATM Withdrawal',
              note: '',
              occurredAt: DateTime(2026, 10, 1, 16, 13),
              scope: 'personal',
              source: 'sms',
              status: 'posted',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Edit transaction'), findsOneWidget);
    await tester.tap(find.text('Transfer'));
    await tester.pump();
    expect(find.text('From account'), findsOneWidget);
    expect(find.text('To account'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
  });

  testWidgets('add from sms opens the bank list', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => FolioStore(),
        child: MaterialApp(
          theme: buildFolioTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showSmsSheet(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Paste'), findsOneWidget);
    expect(find.text('Select your bank'), findsOneWidget);
    await tester.tap(find.text('Select your bank'));
    await tester.pumpAndSettle();
    expect(find.text('Search bank...'), findsOneWidget);
    expect(find.text('Commercial Bank of Sri Lanka'), findsOneWidget);
    expect(find.text('COMBANK'), findsOneWidget);
  });

  testWidgets('deleting a loan asks first', (tester) async {
    final store = FolioStore()
      ..loans = [
        LoanModel(
          id: 'loan',
          kind: 'borrow',
          partyKind: 'person',
          partyName: 'Misnaf',
          counterpartyAccountId: null,
          counterpartyAccountName: '',
          accountId: '',
          accountName: '',
          amount: 100000,
          repaid: 0,
          remaining: 100000,
          dueOn: '2026-10-20',
          note: '',
          settled: false,
        ),
      ];
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => store,
        child: MaterialApp(theme: buildFolioTheme(), home: const LoansScreen()),
      ),
    );
    await tester.pump();
    expect(find.text('Misnaf'), findsOneWidget);
    expect(find.text('Person'), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    await tester.tap(find.text('Lent'));
    await tester.pump();
    expect(find.text('Nothing lent'), findsOneWidget);
    expect(find.text('Misnaf'), findsNothing);
    await tester.tap(find.text('Borrowed'));
    await tester.pump();
    await tester.tap(find.byTooltip('Delete loan'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this loan?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Misnaf'), findsOneWidget);
    expect(find.text('Delete this loan?'), findsNothing);
  });

  testWidgets('a category opens the expenses inside it', (tester) async {
    final store = FolioStore()
      ..timeline = TimelineData(
        label: 'October 2026',
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 31),
        income: 0,
        expenses: 1530,
        net: -1530,
        days: [
          TimelineDay(
            date: DateTime(2026, 10, 1),
            total: -1530,
            items: [
              TxnModel(
                id: 'kids',
                accountId: 'flash',
                accountName: 'Flash Primary',
                transferAccountId: null,
                transferAccountName: '',
                categoryId: null,
                categoryName: '',
                categoryIcon: 'other',
                categoryColor: '#9CA3AF',
                direction: 'expense',
                amount: 490,
                merchant: 'Kids Mania Kandy',
                note: '',
                occurredAt: DateTime(2026, 10, 1, 16),
                scope: 'personal',
                source: 'sms',
                status: 'posted',
              ),
              TxnModel(
                id: 'shop',
                accountId: 'flash',
                accountName: 'Flash Primary',
                transferAccountId: null,
                transferAccountName: '',
                categoryId: 'shopping',
                categoryName: 'Shopping',
                categoryIcon: 'shopping',
                categoryColor: '#34D399',
                direction: 'expense',
                amount: 100,
                merchant: 'Keells',
                note: '',
                occurredAt: DateTime(2026, 10, 1, 12),
                scope: 'personal',
                source: 'sms',
                status: 'posted',
              ),
            ],
          ),
        ],
      );
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => store,
        child: MaterialApp(
          theme: buildFolioTheme(),
          home: const CategorySpendScreen(
            name: 'Uncategorised',
            categoryId: null,
            icon: 'other',
            color: '#9CA3AF',
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Kids Mania Kandy'), findsOneWidget);
    expect(find.text('Keells'), findsNothing);
    expect(find.text('1 this month'), findsOneWidget);
  });

  testWidgets('labels opens and category search filters as you type', (tester) async {
    final store = FolioStore()
      ..accounts = [
        AccountModel(
          id: 'cash',
          name: 'Cash',
          type: 'cash',
          purpose: 'personal',
          bankName: '',
          last4: '',
          smsSender: '',
          openingBalance: 0,
          balance: 100,
          automationsEnabled: true,
        ),
      ]
      ..categories = [
        CategoryModel(id: 'util', name: 'Utilities', kind: 'expense', icon: 'utilities', color: '#F5C542', transactionCount: 0),
        CategoryModel(
          id: 'phone',
          name: 'Phone',
          kind: 'expense',
          icon: 'phone',
          color: '#7EB6FF',
          parentId: 'util',
          transactionCount: 0,
        ),
        CategoryModel(id: 'food', name: 'Groceries', kind: 'expense', icon: 'groceries', color: '#8ED4B0', transactionCount: 0),
      ];
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => store,
        child: MaterialApp(theme: buildFolioTheme(), home: const TransactionFormScreen()),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Labels'));
    await tester.pumpAndSettle();
    expect(find.text('Use Labels to organize your records better. Start with (+) to create first one.'), findsOneWidget);
    await tester.tap(find.byTooltip('Add label'));
    await tester.pumpAndSettle();
    expect(find.text('New label'), findsOneWidget);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('New label'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Category'));
    await tester.pumpAndSettle();
    expect(find.text('Utilities'), findsWidgets);
    expect(find.text('Groceries'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Search categories'), 'pho');
    await tester.pump();
    expect(find.text('Phone'), findsOneWidget);
    expect(find.text('Groceries'), findsNothing);
  });

  testWidgets('category filters are two dropdowns', (tester) async {
    final store = FolioStore()
      ..categories = [
        CategoryModel(id: 'food', name: 'Groceries', kind: 'expense', icon: 'groceries', color: '#8ED4B0', transactionCount: 0),
        CategoryModel(id: 'pay', name: 'Salary', kind: 'income', icon: 'income', color: '#8ED4B0', transactionCount: 0),
      ];
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => store,
        child: MaterialApp(theme: buildFolioTheme(), home: const CategoriesScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Salary'), findsNothing);
    await tester.tap(find.text('Expense'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Income').last);
    await tester.pumpAndSettle();
    expect(find.text('Salary'), findsOneWidget);
    expect(find.text('Groceries'), findsNothing);
  });
}
