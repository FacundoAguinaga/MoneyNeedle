import 'package:flutter/material.dart';
import 'src/auth/onboarding_vault_screen.dart';
import 'src/auth/unlock_screen.dart';
import 'src/auth/vault_service.dart';
import 'src/rust/api.dart/frb_generated.dart';
import 'src/screens/accounts_tab.dart';
import 'src/screens/home_tab.dart';
import 'src/screens/recurring_tab.dart';

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
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green),
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

  final List<Widget> _tabs = const [
    HomeTab(),
    AccountsTab(),
    RecurringTab(),
  ];

  @override
  Widget build(BuildContext context) {
    final titles = [
      'MoneyNeedle 🌵',
      'Cuentas y Tarjetas',
      'Suscripciones y Recurrentes',
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_currentTabIndex]),
        elevation: 0,
      ),
      body: IndexedStack(
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
        ],
      ),
    );
  }
}
