import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/wallet_provider.dart';
import 'screens/dashboard_screen.dart';
import 'screens/send_screen.dart';
import 'screens/receive_screen.dart';
import 'screens/staking_screen.dart';
import 'screens/mining_screen.dart';
import 'screens/settings_screen.dart';

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
        '/': (_) => const _Shell(),
        '/send': (_) => const SendScreen(),
        '/receive': (_) => const ReceiveScreen(),
        '/staking': (_) => const StakingScreen(),
        '/mining': (_) => const MiningScreen(),
        '/settings': (_) => const SettingsScreen(),
      },
    );
  }
}

class _Shell extends StatefulWidget {
  const _Shell();
  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int _idx = 0;

  static const _screens = [
    DashboardScreen(),
    ReceiveScreen(),
    StakingScreen(),
    MiningScreen(),
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
          NavigationDestination(
            icon: Icon(Icons.memory_outlined),
            selectedIcon: Icon(Icons.memory, color: Color(0xFFF7C948)),
            label: 'Mine',
          ),
        ],
      ),
    );
  }
}
