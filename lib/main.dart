import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'services/app_state.dart';
import 'services/auth_service.dart';
import 'services/biometric_service.dart';
import 'services/encryption_service.dart';
import 'services/holiday_service.dart';
import 'services/pattern_service.dart';
import 'services/storage_service.dart';
import 'services/firestore_tax_service.dart';
import 'services/sync_service.dart';
import 'screens/auth_gate.dart';
import 'screens/calendar_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/info_screen.dart';
import 'screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await initializeDateFormatting();
  final storage = StorageService();
  await storage.init();
  final holidayService = HolidayService(await SharedPreferences.getInstance());
  final encryption = EncryptionService();
  storage.attachEncryption(encryption);
  final taxService = FirestoreTaxService();
  await taxService.init();
  final authService = AuthService();
  final patternService = PatternService();
  final biometricService = BiometricService();
  final syncService = SyncService(storage: storage, auth: authService);
  // Load the user's saved cloud-sync preference (opt-in) before wiring up
  // listeners, so returning users' choices are respected on the first frame.
  await syncService.init();
  // Every local mutation triggers a debounced upload to Firestore.
  storage.attachMutationListener(syncService.scheduleUpload);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState(storage: storage, holidays: holidayService)),
        ChangeNotifierProvider.value(value: authService),
        ChangeNotifierProvider.value(value: patternService),
        ChangeNotifierProvider.value(value: biometricService),
        ChangeNotifierProvider.value(value: syncService),
        Provider.value(value: encryption),
        Provider.value(value: taxService),
      ],
      child: const LaborDayApp(),
    ),
  );
}

class LaborDayApp extends StatelessWidget {
  const LaborDayApp({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return MaterialApp(
      title: 'Labor Day Pay Calculator',
      debugShowCheckedModeBanner: false,
      locale: app.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: app.isDark ? _darkTheme : _lightTheme,
      home: const SyncConflictHost(
        child: AuthGate(child: SyncOptInHost(child: MainShell())),
      ),
    );
  }

  static final _darkTheme = ThemeData(
    brightness: Brightness.dark,
    colorSchemeSeed: const Color(0xFF00B8A9),
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFF0D0D1A),
    cardTheme: const CardThemeData(
      color: Color(0xFF1A1A2E),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: Color(0xFF2A2A40)),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF0D0D1A),
      elevation: 0,
      centerTitle: true,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFF1A1A2E),
      indicatorColor: const Color(0xFF00B8A9).withOpacity(0.3),
      labelTextStyle: MaterialStateProperty.all(
        const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
    ),
  );

  static final _lightTheme = ThemeData(
    brightness: Brightness.light,
    colorSchemeSeed: const Color(0xFF00B8A9),
    useMaterial3: true,
    cardTheme: const CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: Color(0xFFE0E0E0)),
      ),
    ),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      centerTitle: true,
    ),
  );
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  // Persists across MainShell unmounts (e.g. when AuthGate swaps in the
  // sign-in screen and then swaps MainShell back in) so the user returns to
  // the tab they were on, not the default.
  static int _lastIndex = 0;

  late int _currentIndex = _MainShellState._lastIndex;
  final _settingsKey = GlobalKey<SettingsScreenState>();

  void _onTabTap(int i) {
    // Leaving settings tab → revert unsaved changes
    if (_currentIndex == 3 && i != 3) {
      _settingsKey.currentState?.revertIfNeeded();
    }
    // Entering settings tab → capture current state as baseline
    if (i == 3 && _currentIndex != 3) {
      _settingsKey.currentState?.onEnter();
    }
    setState(() {
      _currentIndex = i;
      _MainShellState._lastIndex = i;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const CalendarScreen(),
          const DashboardScreen(),
          const InfoScreen(),
          SettingsScreen(key: _settingsKey),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabTap,
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 11,
        unselectedFontSize: 10,
        iconSize: 22,
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1A1A2E)
            : Colors.white,
        selectedItemColor: const Color(0xFF00B8A9),
        unselectedItemColor: Colors.grey,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.calendar_month_outlined),
            activeIcon: const Icon(Icons.calendar_month),
            label: l.get('nav_calendar'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.dashboard_outlined),
            activeIcon: const Icon(Icons.dashboard),
            label: l.get('nav_dashboard'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.info_outline),
            activeIcon: const Icon(Icons.info),
            label: l.get('nav_info'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.settings_outlined),
            activeIcon: const Icon(Icons.settings),
            label: l.get('nav_settings'),
          ),
        ],
      ),
    );
  }
}

/// Listens to [SyncService.conflictStream] and shows a dialog when both the
/// local cache and the cloud snapshot have data but differ. The user picks
/// which side wins — the other side is overwritten.
class SyncConflictHost extends StatefulWidget {
  const SyncConflictHost({super.key, required this.child});
  final Widget child;

  @override
  State<SyncConflictHost> createState() => _SyncConflictHostState();
}

class _SyncConflictHostState extends State<SyncConflictHost> {
  bool _dialogOpen = false;
  StreamSubscription<SyncConflict>? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final sync = context.read<SyncService>();
      _sub = sync.conflictStream.listen(_onConflict);
      final pending = sync.pendingConflict;
      if (pending != null && !_dialogOpen) {
        _onConflict(pending);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _onConflict(SyncConflict c) async {
    if (_dialogOpen || !mounted) return;
    _dialogOpen = true;
    final sync = context.read<SyncService>();
    final l = AppLocalizations.of(context);
    final choice = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(l.get('sync_conflict_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.get('sync_conflict_body')),
            const SizedBox(height: 12),
            Text(
              l.getWith('sync_conflict_counts', {
                'local': c.localEntryCount.toString(),
                'cloud': c.cloudEntryCount.toString(),
              }),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.get('sync_use_local')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.get('sync_use_cloud')),
          ),
        ],
      ),
    );
    _dialogOpen = false;
    if (choice == null) return;
    await sync.resolveConflict(useCloud: choice);
    if (mounted) {
      context.read<AppState>().refreshRates();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Sits inside the [AuthGate] — so it only renders for signed-in, fully
/// unlocked users — and shows a one-time opt-in dialog asking whether to
/// enable cloud sync. The result is persisted by [SyncService] so we don't
/// nag on every login.
class SyncOptInHost extends StatefulWidget {
  const SyncOptInHost({super.key, required this.child});
  final Widget child;

  @override
  State<SyncOptInHost> createState() => _SyncOptInHostState();
}

class _SyncOptInHostState extends State<SyncOptInHost> {
  bool _dialogOpen = false;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_scheduled) {
      _scheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
    }
  }

  Future<void> _maybeShow() async {
    if (!mounted || _dialogOpen) return;
    final sync = context.read<SyncService>();
    final auth = context.read<AuthService>();
    // Only ask signed-in users — offline users have nothing to sync.
    if (!auth.isSignedIn) return;
    // Respect any previous answer.
    if (sync.prompted) return;

    _dialogOpen = true;
    final l = AppLocalizations.of(context);
    final choice = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(l.get('sync_optin_title')),
        content: Text(l.get('sync_optin_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.get('sync_optin_not_now')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.get('sync_optin_enable')),
          ),
        ],
      ),
    );
    _dialogOpen = false;
    if (!mounted) return;
    if (choice == true) {
      await sync.setEnabled(true);
    } else {
      // User declined (or dismissed) — remember so we don't ask again.
      await sync.markPrompted();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
