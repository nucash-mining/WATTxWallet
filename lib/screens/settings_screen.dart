import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/wallet_provider.dart';
import '../services/node_service.dart';
import '../services/wallet_store.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _revealSeed(BuildContext context) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Reveal recovery phrase',
            style: TextStyle(color: Colors.white)),
        content: const Text(
            'Your recovery phrase controls your funds. Only reveal it somewhere '
            'private. Never share it — anyone who has it can take your coins.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reveal')),
        ],
      ),
    );
    if (proceed != true) return;
    final mnemonic = await WalletStore.revealMnemonic();
    if (mnemonic == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Recovery phrase',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(mnemonic,
                style: const TextStyle(
                    color: Color(0xFFF7C948),
                    fontSize: 16,
                    height: 1.5,
                    fontWeight: FontWeight.w600)),
            TextButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy'),
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: mnemonic)),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    return Scaffold(
      appBar: AppBar(
          title: const Text('Settings'),
          backgroundColor: const Color(0xFF161B22)),
      body: ListView(
        children: [
          const _SectionHeader('Wallet'),
          ListTile(
            title: const Text('Receive address',
                style: TextStyle(color: Colors.white)),
            subtitle: Text(wallet.receiveAddress,
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            trailing: IconButton(
              icon: const Icon(Icons.copy, color: Colors.white54),
              onPressed: () => Clipboard.setData(
                  ClipboardData(text: wallet.receiveAddress)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.key, color: Color(0xFFF7C948)),
            title: const Text('Reveal recovery phrase',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text('Back up your 12 words',
                style: TextStyle(color: Colors.white54)),
            onTap: () => _revealSeed(context),
          ),
          const _SectionHeader('Network (seednodes)'),
          ...NodeService.defaultEndpoints.map((e) => ListTile(
                leading: Icon(
                    e == wallet.node.activeEndpoint
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                    color: e == wallet.node.activeEndpoint
                        ? const Color(0xFF3FB950)
                        : Colors.white38,
                    size: 18),
                title: Text(e,
                    style:
                        const TextStyle(color: Colors.white, fontSize: 13)),
              )),
          ListTile(
            title: Text(
                wallet.status == WalletStatus.connected
                    ? 'Connected · block ${wallet.blockHeight}'
                    : 'Not connected',
                style: TextStyle(
                    color: wallet.status == WalletStatus.connected
                        ? const Color(0xFF3FB950)
                        : Colors.redAccent)),
            trailing: TextButton(
              onPressed: () => context.read<WalletProvider>().connect(),
              child: const Text('Reconnect'),
            ),
          ),
          const _SectionHeader('About'),
          const ListTile(
            title: Text('WATTx Wallet', style: TextStyle(color: Colors.white)),
            subtitle: Text('Self-custody · keys stored on this device only',
                style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(title.toUpperCase(),
            style: const TextStyle(
                color: Color(0xFFF7C948),
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2)),
      );
}
