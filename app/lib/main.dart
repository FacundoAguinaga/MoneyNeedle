import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'src/auth/onboarding_vault_screen.dart';
import 'src/auth/unlock_screen.dart';
import 'src/auth/vault_service.dart';
import 'src/auth/welcome_screen.dart';
import 'src/providers/privacy_provider.dart';
import 'src/rust/api.dart/frb_generated.dart';
import 'src/screens/accounts_tab.dart';
import 'src/screens/home_tab.dart';
import 'src/screens/recurring_tab.dart';
import 'src/screens/metrics_tab.dart';
import 'src/screens/search_screen.dart';
import 'src/screens/settings_screen.dart';
import 'src/services/widget_service.dart';
import 'src/theme/mn_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const MoneyNeedleApp());
}

class MoneyNeedleApp extends StatelessWidget {
  const MoneyNeedleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MoneyNeedle',
      theme: MnTheme.light(),
      darkTheme: MnTheme.dark(),
      themeMode: ThemeMode.system,
      home: const RootGate(),
    );
  }
}

class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  bool _loading = true;
  bool _hasVault = false;
  bool _unlocked = false;
  bool _seenWelcome = false;

  @override
  void initState() {
    super.initState();
    _checkVault();
  }

  Future<void> _checkVault() async {
    final has = await VaultService.hasVault();
    if (!mounted) return;
    setState(() {
      _hasVault = has;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasVault) {
      if (!_seenWelcome) {
        return WelcomeScreen(
          onStart: () => setState(() => _seenWelcome = true),
        );
      }

      return OnboardingVaultScreen(
        onVaultReady: () {
          setState(() {
            _hasVault = true;
            _unlocked = true;
          });
        },
      );
    }

    if (!_unlocked) {
      return UnlockScreen(
        onUnlocked: () {
          setState(() {
            _unlocked = true;
          });
        },
      );
    }

    return const HomePage();
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentTabIndex = 0;
  Key _tabsKey = UniqueKey();

  late final List<Widget> _tabs = [
    HomeTab(key: HomeTab.homeTabKey),
    const AccountsTab(),
    const RecurringTab(),
    const MetricsTab(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetService.init(onQuickAdd: _onWidgetQuickAdd);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final shouldOpen = await WidgetService.checkInitialQuickAdd();
      if (shouldOpen && mounted) {
        _onWidgetQuickAdd();
      }
    });
  }

  void _onWidgetQuickAdd() {
    if (!mounted) return;
    setState(() => _currentTabIndex = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      HomeTab.homeTabKey.currentState?.abrirQuickAdd();
    });
  }

  @override
  Widget build(BuildContext context) {
    final titles = [
      'MoneyNeedle 🌵',
      'Cuentas y Tarjetas',
      'Suscripciones y Recurrentes',
      'Analítica y Métricas',
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_currentTabIndex]),
        elevation: 0,
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: PrivacyController.instance,
            builder: (context, isPrivate, _) {
              return IconButton(
                icon: Icon(
                  isPrivate ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                ),
                tooltip: isPrivate ? 'Mostrar montos' : 'Ocultar montos',
                onPressed: () {
                  HapticFeedback.selectionClick();
                  PrivacyController.instance.toggle();
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Buscar movimientos',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SearchScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Ajustes y Respaldos',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SettingsScreen(
                    onDataRestored: () {
                      setState(() {
                        _tabsKey = UniqueKey();
                      });
                    },
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: IndexedStack(
        key: _tabsKey,
        index: _currentTabIndex,
        children: _tabs,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTabIndex,
        onDestinationSelected: (index) => setState(() => _currentTabIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Cuentas',
          ),
          NavigationDestination(
            icon: Icon(Icons.autorenew_outlined),
            selectedIcon: Icon(Icons.autorenew),
            label: 'Recurrentes',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Métricas',
          ),
        ],
      ),
    );
  }
}
