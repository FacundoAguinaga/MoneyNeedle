import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'src/auth/onboarding_vault_screen.dart';
import 'src/auth/unlock_screen.dart';
import 'src/auth/vault_service.dart';
import 'src/auth/welcome_screen.dart';
import 'src/providers/privacy_provider.dart';
import 'src/providers/theme_provider.dart';
import 'src/rust/api.dart/frb_generated.dart';
import 'src/screens/home_tab.dart';
import 'src/screens/metrics_tab.dart';
import 'src/screens/more_hub.dart';
import 'src/screens/movements_tab.dart';
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
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'MoneyNeedle',
          theme: MnTheme.light(),
          darkTheme: MnTheme.dark(),
          themeMode: themeMode,
          debugShowCheckedModeBanner: false,
          home: const RootGate(),
        );
      },
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

    return HomePage(
      onLockVault: () {
        setState(() {
          _unlocked = false;
        });
      },
    );
  }
}

class HomePage extends StatefulWidget {
  final VoidCallback? onLockVault;

  const HomePage({super.key, this.onLockVault});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentTabIndex = 0;
  Key _tabsKey = UniqueKey();

  late final List<Widget> _tabs = [
    HomeTab(
      key: HomeTab.homeTabKey,
      onViewAllMovements: () {
        setState(() => _currentTabIndex = 1);
      },
    ),
    MovementsTab(
      key: MovementsTab.movementsTabKey,
      onQuickAdd: _abrirQuickAdd,
    ),
    const MetricsTab(),
    MoreHub(
      onDataRestored: () {
        setState(() {
          _tabsKey = UniqueKey();
        });
      },
      onLockVault: widget.onLockVault,
    ),
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
    _abrirQuickAdd();
  }

  void _abrirQuickAdd() {
    if (!mounted) return;
    if (_currentTabIndex != 0) {
      setState(() => _currentTabIndex = 0);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      HomeTab.homeTabKey.currentState?.abrirQuickAdd();
    });
  }

  @override
  Widget build(BuildContext context) {
    final titles = [
      'MoneyNeedle',
      'Movimientos',
      'Análisis',
      'Más',
    ];

    // Mostrar FAB unificado únicamente en Inicio y Movimientos
    final showFab = _currentTabIndex == 0 || _currentTabIndex == 1;

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
        ],
      ),
      body: IndexedStack(
        key: _tabsKey,
        index: _currentTabIndex,
        children: _tabs,
      ),
      floatingActionButton: showFab
          ? FloatingActionButton(
              onPressed: _abrirQuickAdd,
              tooltip: 'Registrar movimiento',
              child: const Icon(Icons.add_rounded),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTabIndex,
        onDestinationSelected: (index) => setState(() => _currentTabIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Movimientos',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics_rounded),
            label: 'Análisis',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_rounded),
            selectedIcon: Icon(Icons.menu_open_rounded),
            label: 'Más',
          ),
        ],
      ),
    );
  }
}
