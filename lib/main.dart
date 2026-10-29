import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/wallet_provider.dart';
import 'screens/lock_screen.dart';
import 'services/security_store.dart';
import 'services/local_node.dart';
import 'screens/dashboard_screen.dart';
import 'screens/send_screen.dart';
import 'screens/receive_screen.dart';
import 'screens/staking_screen.dart';
// Mining is temporarily removed from the UI (2026-08-10): phone/CPU mining on a
// near-empty algo port lets weak miners sweep cheap blocks, so the miner tab is
// hidden until a phone-appropriate mining algorithm exists. The miner services
// (pool_miner.dart / cpu_miner.dart) and mining_screen.dart are kept so it can
// be re-added by restoring the import, route, tab, and screen below.
// import 'screens/mining_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/swap_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => WalletProvider()..init(),
      child: const WATTxApp(),
    ),
  );
}

class WATTxApp extends StatelessWidget {
  const WATTxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WATTx Wallet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFF7C948),
          secondary: Color(0xFF3FB950),
          surface: Color(0xFF161B22),
        ),
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (_) => const _Gate(),
        '/send': (_) => const SendScreen(),
        '/receive': (_) => const ReceiveScreen(),
        '/staking': (_) => const StakingScreen(),
        '/settings': (_) => const SettingsScreen(),
        '/swap': (_) => const SwapScreen(),
      },
    );
  }
}

/// Shows onboarding until a wallet exists, then the lock, then the main shell.
class _Gate extends StatefulWidget {
  const _Gate();
  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  bool _unlocked = false;
  bool? _lockEnabled;

  @override
  void initState() {
    super.initState();
    SecurityStore.lockEnabled().then((v) {
      if (mounted) setState(() => _lockEnabled = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    if (wallet.needsOnboarding) return const OnboardingScreen();

    // Until the answer is known, show nothing rather than the wallet: rendering
    // balances for an instant before the lock appears would defeat it.
    if (_lockEnabled == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_lockEnabled! && !_unlocked) {
      return LockScreen(onUnlocked: () => setState(() => _unlocked = true));
    }
    return const _Shell();
  }
}

class _Shell extends StatefulWidget {
  const _Shell();
  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> with WidgetsBindingObserver {
  int _idx = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Bring the full node back if the user left full-node mode on.
    LocalNode.ensureWanted();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) LocalNode.ensureWanted();
  }

  static const _screens = [
    DashboardScreen(),
    ReceiveScreen(),
    StakingScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _idx, children: _screens),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFF7C948),
        foregroundColor: Colors.black,
        onPressed: () => Navigator.pushNamed(context, '/send'),
        child: const Icon(Icons.send),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF161B22),
        indicatorColor: const Color(0xFFF7C948).withOpacity(0.2),
        selectedIndex: _idx,
        onDestinationSelected: (i) => setState(() => _idx = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: Color(0xFFF7C948)),
            label: 'Wallet',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_outlined),
            selectedIcon: Icon(Icons.qr_code, color: Color(0xFFF7C948)),
            label: 'Receive',
          ),
          NavigationDestination(
            icon: Icon(Icons.stacked_bar_chart_outlined),
            selectedIcon: Icon(Icons.stacked_bar_chart, color: Color(0xFFF7C948)),
            label: 'Stake',
          ),
        ],
      ),
    );
  }
}
