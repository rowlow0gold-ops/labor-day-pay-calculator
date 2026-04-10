import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'services/app_state.dart';
import 'services/storage_service.dart';
import 'services/firestore_tax_service.dart';
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
  final taxService = FirestoreTaxService();
  await taxService.init();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState(storage: storage)),
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
      home: const MainShell(),
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
  int _currentIndex = 0;
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
    setState(() => _currentIndex = i);
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
