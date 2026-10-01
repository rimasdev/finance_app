import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';

import 'screens/auth_screen.dart';
import 'screens/shell.dart';
import 'store.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    SemanticsBinding.instance.ensureSemantics();
  }
  runApp(const FolioApp());
}

class FolioApp extends StatelessWidget {
  const FolioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => FolioStore()..bootstrap(),
      child: MaterialApp(
        title: 'Takings',
        debugShowCheckedModeBanner: false,
        theme: buildFolioTheme(),
        builder: (context, child) {
          return ColoredBox(
            color: FolioColors.bg,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          );
        },
        home: const Root(),
      ),
    );
  }
}

class Root extends StatelessWidget {
  const Root({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FolioStore>();
    if (store.booting) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: FolioColors.green)),
      );
    }
    if (!store.signedIn) return const AuthScreen();
    return const Shell();
  }
}
