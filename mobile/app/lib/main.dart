import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_lock.dart';
import 'core/app_store.dart';
import 'core/session_store.dart';
import 'features/home_shell.dart';
import 'features/pairing_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    StichtagApp(
      store: AppStore(
        sessionStore: SecureSessionStore(),
        stateCache: SecureStateCache(),
      ),
    ),
  );
}

ThemeData buildTheme(Brightness brightness) => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF0B6E60),
    brightness: brightness,
  ),
  inputDecorationTheme: const InputDecorationTheme(
    border: OutlineInputBorder(),
  ),
);

class StichtagApp extends StatefulWidget {
  const StichtagApp({super.key, required this.store, this.appLock});

  final AppStore store;

  /// Sperre per Fingerabdruck; Tests geben ihre eigene mit.
  final AppLock? appLock;

  @override
  State<StichtagApp> createState() => _StichtagAppState();
}

class _StichtagAppState extends State<StichtagApp> with WidgetsBindingObserver {
  late final AppLock _lock = widget.appLock ?? AppLock();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.store.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.store.resume();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return MaterialApp(
      title: 'Stichtag',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      locale: const Locale('de'),
      supportedLocales: const [Locale('de')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // Über dem Navigator, damit die Sperre auch offene Seiten verdeckt.
      builder: (context, child) =>
          AppLockGate(lock: _lock, child: child ?? const SizedBox.shrink()),
      home: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          if (!store.ready) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (!store.paired) return PairingPage(store: store);
          return HomeShell(store: store, appLock: _lock);
        },
      ),
    );
  }
}
