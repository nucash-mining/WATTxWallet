import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/wallet_provider.dart';
import '../widgets/balance_card.dart';
import '../widgets/quick_actions.dart';
import '../widgets/tx_list.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      context.read<WalletProvider>().refresh();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: Row(children: [
          Image.asset('assets/images/logo.png', height: 28, errorBuilder: (_, __, ___) =>
              const Icon(Icons.bolt, color: Color(0xFFF7C948), size: 28)),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('WATTx Wallet', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            Text(
              wallet.status == WalletStatus.connected
                  ? '${wallet.chainName.toUpperCase()} · Block ${wallet.blockHeight}'
                  : wallet.status.name,
              style: TextStyle(
                color: wallet.status == WalletStatus.connected
                    ? const Color(0xFF3FB950) : Colors.orange,
                fontSize: 11,
              ),
            ),
          ]),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white54),
            onPressed: () => wallet.refresh(),
          ),
          _NetworkDot(peers: wallet.connectionCount),
          const SizedBox(width: 4),
        ],
      ),
      body: wallet.status == WalletStatus.connecting
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFF7C948)))
          : wallet.status == WalletStatus.error
              ? _ErrorView(message: wallet.errorMessage)
              : RefreshIndicator(
                  color: const Color(0xFFF7C948),
                  onRefresh: wallet.refresh,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      BalanceCard(
                        balance: wallet.balance,
                        unconfirmed: wallet.unconfirmedBalance,
                        staking: wallet.stakingEnabled,
                        maturing: wallet.maturingBalance,
                      ),
                      const SizedBox(height: 16),
                      if (wallet.initialBlockDownload)
                        const _SyncBanner(),
                      const SizedBox(height: 8),
                      const QuickActions(),
                      const SizedBox(height: 20),
                      const TxList(),
                    ],
                  ),
                ),
    );
  }
}

class _NetworkDot extends StatelessWidget {
  final int peers;
  const _NetworkDot({required this.peers});
  @override
  Widget build(BuildContext context) {
    final color = peers == 0 ? Colors.red : peers < 3 ? Colors.orange : const Color(0xFF3FB950);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        Text('$peers', style: const TextStyle(fontSize: 9, color: Colors.white54)),
      ]),
    );
  }
}

class _SyncBanner extends StatelessWidget {
  const _SyncBanner();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withOpacity(0.4)),
      ),
      child: const Row(children: [
        Icon(Icons.sync, color: Colors.orange, size: 18),
        SizedBox(width: 8),
        Text('Syncing blockchain…', style: TextStyle(color: Colors.orange, fontSize: 13)),
      ]),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});
  @override
  Widget build(BuildContext context) {
    return Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off, size: 64, color: Colors.red),
        const SizedBox(height: 16),
        const Text('Cannot connect to node', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(message, style: const TextStyle(color: Colors.white54), textAlign: TextAlign.center),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF7C948), foregroundColor: Colors.black),
          icon: const Icon(Icons.settings),
          label: const Text('Edit RPC Settings'),
          onPressed: () => Navigator.pushNamed(context, '/settings'),
        ),
      ]),
    ));
  }
}
