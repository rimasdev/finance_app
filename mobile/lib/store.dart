import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'account_art.dart';
import 'api.dart';
import 'api_config.dart';
import 'capture.dart';
import 'format.dart';
import 'models.dart';

class FolioStore extends ChangeNotifier {
  FolioStore();

  final ApiClient api = ApiClient(baseUrl: defaultApiBase());
  String? token;
  UserProfile? me;
  bool booting = true;
  bool refreshing = false;
  String? lastError;
  DateTime? syncedAt;
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  String? accountFilter;
  String scope = 'all';
  String search = '';

  DashboardData? dashboard;
  InsightsData? insights;
  TimelineData? timeline;
  List<AccountModel> accounts = [];
  List<CategoryModel> categories = [];
  List<BudgetModel> budgets = [];
  List<LoanModel> loans = [];
  List<RecurringModel> recurring = [];
  bool showRecurringHome = false;
  List<TxnModel> review = [];

  bool get signedIn => token != null && me != null;

  double get personalNet => accounts
      .where((account) => account.purpose == 'personal' && account.includeInNet)
      .fold(0, (sum, account) => sum + account.balance);

  double get businessNet => accounts
      .where((account) => account.purpose == 'business' && account.includeInNet)
      .fold(0, (sum, account) => sum + account.balance);

  Future<void> bootstrap() async {
    await AccountMarks.instance.load();
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('baseUrl');
    if (saved != null && saved.isNotEmpty) api.baseUrl = saved;
    token = prefs.getString('token');
    showRecurringHome = prefs.getBool('showRecurringHome') ?? true;
    api.token = token;
    if (token != null) {
      try {
        me = UserProfile.fromJson(
          (await api.get('/me')) as Map<String, dynamic>,
        );
        await refresh();
        await Capture.setSession(token: token!, baseUrl: api.baseUrl);
      } on ApiException catch (error) {
        if (error.status == 401) {
          await _clearLocal();
        } else {
          lastError = error.message;
        }
      } catch (_) {
        lastError = 'Cannot reach the server';
      }
    }
    booting = false;
    notifyListeners();
  }

  Future<void> setBaseUrl(String value) async {
    api.baseUrl = value.trim().replaceAll(RegExp(r'/+$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('baseUrl', api.baseUrl);
  }

  Future<void> register(String name, String email, String password) async {
    final result = await api.post('/auth/register', {
      'name': name,
      'email': email,
      'password': password,
    });
    await _persist(result as Map<String, dynamic>);
  }

  Future<void> login(String email, String password) async {
    final result = await api.post('/auth/login', {
      'email': email,
      'password': password,
    });
    await _persist(result as Map<String, dynamic>);
  }

  static final GoogleSignIn _google = GoogleSignIn(
    scopes: const ['email', 'profile'],
    serverClientId: ApiConfig.googleServerClientId,
  );

  Future<void> signInWithGoogle() async {
    try {
      await _google.signOut();
    } catch (_) {}
    final account = await _google.signIn();
    if (account == null) {
      throw StateError('Google sign-in cancelled');
    }
    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) {
      throw StateError(
        'Google did not return an id token. Add an Android OAuth client for lk.alphabet.takings in the Alphabet Google project, then restart the app.',
      );
    }
    final result = await api.post('/auth/google', {'idToken': idToken});
    await _persist(result as Map<String, dynamic>);
  }

  Future<void> signInWithApple() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      throw StateError(
        'Sign in with Apple is on iPhone. Use Google or email here.',
      );
    }
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );
    final idToken = credential.identityToken;
    if (idToken == null) {
      throw StateError('Apple did not return an identity token');
    }
    final result = await api.post('/auth/apple', {
      'idToken': idToken,
      'fullName': {
        'givenName': credential.givenName,
        'familyName': credential.familyName,
      },
    });
    await _persist(result as Map<String, dynamic>);
  }

  Future<void> _persist(Map<String, dynamic> result) async {
    token = result['token'] as String;
    api.token = token;
    me = UserProfile.fromJson(result['user'] as Map<String, dynamic>);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token!);
    await prefs.setString('baseUrl', api.baseUrl);
    await Capture.setSession(token: token!, baseUrl: api.baseUrl);
    await refresh();
  }

  Future<void> logout() async {
    try {
      await _google.signOut();
    } catch (_) {}
    await _clearLocal();
    notifyListeners();
  }

  Future<void> _clearLocal() async {
    token = null;
    api.token = null;
    me = null;
    dashboard = null;
    insights = null;
    timeline = null;
    accounts = [];
    categories = [];
    budgets = [];
    loans = [];
    recurring = [];
    review = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await Capture.clearSession();
  }

  Future<void> refresh() async {
    refreshing = true;
    lastError = null;
    notifyListeners();
    final key = monthKey(month);
    final params = <String, String>{'month': key};
    if (accountFilter != null) params['account_id'] = accountFilter!;
    if (scope != 'all') params['scope'] = scope;
    if (search.trim().isNotEmpty) params['q'] = search.trim();
    final query = params.entries
        .map((entry) => '${entry.key}=${Uri.encodeQueryComponent(entry.value)}')
        .join('&');
    try {
      final results = await Future.wait([
        api.get('/dashboard'),
        api.get('/insights?month=$key'),
        api.get('/timeline?$query'),
        api.get('/accounts'),
        api.get('/categories'),
        api.get('/budgets?month=$key'),
        api.get('/transactions?status=needs_review'),
      ]);
      List<dynamic> loanRows = const [];
      try {
        loanRows = await api.get('/loans') as List;
      } on ApiException catch (error) {
        if (error.status != 404) rethrow;
      }
      dashboard = DashboardData.fromJson(results[0] as Map<String, dynamic>);
      insights = InsightsData.fromJson(results[1] as Map<String, dynamic>);
      timeline = TimelineData.fromJson(results[2] as Map<String, dynamic>);
      accounts = [
        for (final row in results[3] as List)
          AccountModel.fromJson(row as Map<String, dynamic>),
      ];
      categories = [
        for (final row in results[4] as List)
          CategoryModel.fromJson(row as Map<String, dynamic>),
      ];
      budgets = [
        for (final row in results[5] as List)
          BudgetModel.fromJson(row as Map<String, dynamic>),
      ];
      review = [
        for (final row in results[6] as List)
          TxnModel.fromJson(row as Map<String, dynamic>),
      ];
      loans = [
        for (final row in loanRows)
          LoanModel.fromJson(row as Map<String, dynamic>),
      ];
      List<dynamic> recurringRows = const [];
      try {
        recurringRows = await api.get('/recurring') as List;
      } on ApiException catch (error) {
        if (error.status != 404) rethrow;
      }
      recurring = [
        for (final row in recurringRows)
          RecurringModel.fromJson(row as Map<String, dynamic>),
      ];
      syncedAt = DateTime.now();
    } on ApiException catch (error) {
      lastError = error.message;
      rethrow;
    } catch (_) {
      lastError = 'Cannot reach the server';
      rethrow;
    } finally {
      refreshing = false;
      notifyListeners();
    }
  }

  Future<void> shiftMonth(int delta) async {
    month = DateTime(month.year, month.month + delta);
    await refresh();
  }

  Future<void> setAccountFilter(String? id) async {
    accountFilter = id;
    await refresh();
  }

  Future<void> setScope(String value) async {
    scope = value;
    await refresh();
  }

  Future<void> setSearch(String value) async {
    search = value;
    await refresh();
  }

  Future<String> createAccount(Map<String, dynamic> body) async {
    final created = await api.post('/accounts', body);
    await refresh();
    if (created is Map && created['id'] is String) return created['id'] as String;
    return '';
  }

  Future<void> linkCard(String accountId, String last4) async {
    await api.post('/accounts/$accountId/cards', {'last4': last4});
    await refresh();
  }

  Future<void> updateAccount(String id, Map<String, dynamic> body) async {
    await api.patch('/accounts/$id', body);
    await refresh();
  }

  Future<void> reorderAccounts(List<String> ids) async {
    final previous = accounts;
    final byId = {for (final account in accounts) account.id: account};
    accounts = [
      for (final id in ids)
        if (byId.containsKey(id)) byId[id]!,
    ];
    notifyListeners();
    try {
      await api.post('/accounts/order', {'ids': ids});
      await refresh();
    } catch (error) {
      accounts = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteAccount(String id) async {
    await api.delete('/accounts/$id');
    await AccountMarks.instance.clear(id);
    await refresh();
  }

  Future<void> createCategory(
    String name,
    String kind, {
    String icon = 'other',
    String? parentId,
  }) async {
    await api.post('/categories', {
      'name': name,
      'kind': kind,
      'icon': icon,
      'parent_id': ?parentId,
    });
    await refresh();
  }

  Future<void> deleteCategory(String id) async {
    await api.delete('/categories/$id');
    await refresh();
  }

  Future<void> createTransaction(Map<String, dynamic> body) async {
    await api.post('/transactions', body);
    await refresh();
  }

  Future<void> updateTransaction(String id, Map<String, dynamic> body) async {
    await api.patch('/transactions/$id', body);
    await refresh();
  }

  Future<void> deleteTransaction(String id) async {
    await api.delete('/transactions/$id');
    await refresh();
  }

  Future<void> assignTransaction(
    String id,
    String accountId,
    String? categoryId,
  ) async {
    await api.post('/transactions/$id/assign', {
      'account_id': accountId,
      'category_id': ?categoryId,
    });
    await refresh();
  }

  Future<Map<String, dynamic>> previewSms(
    String body, {
    String sender = '',
  }) async {
    final result = await api.post('/sms/preview', {
      'body': body,
      'sender': sender,
    });
    return result as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> ingestSms(
    String body, {
    String sender = '',
  }) async {
    final result = await api.post('/sms/ingest', {
      'body': body,
      'sender': sender,
      'manual': true,
    });
    await refresh();
    return result as Map<String, dynamic>;
  }

  Future<void> createBudget(Map<String, dynamic> body) async {
    await api.post('/budgets', body);
    await refresh();
  }

  Future<void> createLoan(Map<String, dynamic> body) async {
    await api.post('/loans', body);
    await refresh();
  }

  Future<void> repayLoan(String id, Map<String, dynamic> body) async {
    await api.post('/loans/$id/payments', body);
    await refresh();
  }

  Future<void> setRecurringOnHome(bool value) async {
    showRecurringHome = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showRecurringHome', value);
  }

  Future<void> createRecurring(Map<String, dynamic> body) async {
    await api.post('/recurring', body);
    await refresh();
  }

  Future<void> payRecurring(String id) async {
    await api.post('/recurring/$id/pay', {});
    await refresh();
  }

  Future<void> deleteRecurring(String id) async {
    await api.delete('/recurring/$id');
    await refresh();
  }

  Future<void> deleteLoan(String id) async {
    await api.delete('/loans/$id');
    await refresh();
  }

  Future<void> deleteBudget(String id) async {
    await api.delete('/budgets/$id');
    await refresh();
  }

  Future<void> updateProfile({
    String? name,
    int? monthStartDay,
    bool? withdrawalToCash,
    String? cashAccountId,
    bool clearCashAccount = false,
  }) async {
    me = UserProfile.fromJson(
      (await api.patch('/me', {
        'name': ?name,
        'month_start_day': ?monthStartDay,
        'withdrawal_to_cash': ?withdrawalToCash,
        if (clearCashAccount) 'cash_account_id': '',
        if (!clearCashAccount && cashAccountId != null)
          'cash_account_id': cashAccountId,
      })) as Map<String, dynamic>,
    );
    await refresh();
  }

  Future<void> deleteEverything() async {
    await api.delete('/me');
    await logout();
  }
}
