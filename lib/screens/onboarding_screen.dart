import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/wallet_provider.dart';
import '../services/wallet_store.dart';
import '../services/wattx_wallet.dart';

/// First-run flow: create a new self-custody wallet (showing the recovery phrase
/// to back up) or import an existing one. The seed is written to the device
/// secure store; it is never sent anywhere.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _createNew() async {
    setState(() => _busy = true);
    final wallet = await WalletStore.createNew(net: WalletProvider.net);
    if (!mounted) return;
    setState(() => _busy = false);
    await _showBackup(wallet);
  }

  Future<void> _showBackup(WattxWallet wallet) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BackupDialog(mnemonic: wallet.mnemonic),
    );
    if (confirmed == true && mounted) {
      await context.read<WalletProvider>().onWalletReady(wallet);
    }
  }

  Future<void> _import() async {
    final phrase = await showDialog<String>(
      context: context,
      builder: (_) => const _ImportDialog(),
    );
    if (phrase == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final wallet = await WalletStore.import(phrase, net: WalletProvider.net);
      if (!mounted) return;
      await context.read<WalletProvider>().onWalletReady(wallet);
    } catch (e) {
      setState(() => _error = 'Invalid recovery phrase');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.bolt, color: Color(0xFFF7C948), size: 72),
              const SizedBox(height: 16),
              const Text('WATTx Wallet',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(height: 8),
              const Text('Self-custody. Your keys stay on this device.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54)),
              const SizedBox(height: 40),
              if (_error != null) ...[
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent)),
                const SizedBox(height: 12),
              ],
              if (_busy)
                const Center(child: CircularProgressIndicator())
              else ...[
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF7C948),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  onPressed: _createNew,
                  child: const Text('Create a new wallet',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 14),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  onPressed: _import,
                  child: const Text('Import a recovery phrase'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BackupDialog extends StatefulWidget {
  final String mnemonic;
  const _BackupDialog({required this.mnemonic});
  @override
  State<_BackupDialog> createState() => _BackupDialogState();
}

class _BackupDialogState extends State<_BackupDialog> {
  bool _saved = false;
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF161B22),
      title: const Text('Back up your recovery phrase',
          style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
              'These 12 words are the ONLY way to restore your wallet. Write them '
              'down and keep them offline. Anyone with them can spend your coins.',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: Colors.black26, borderRadius: BorderRadius.circular(8)),
            child: SelectableText(widget.mnemonic,
                style: const TextStyle(
                    color: Color(0xFFF7C948),
                    fontSize: 16,
                    height: 1.5,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy'),
            onPressed: () => Clipboard.setData(
                ClipboardData(text: widget.mnemonic)),
          ),
          CheckboxListTile(
            value: _saved,
            onChanged: (v) => setState(() => _saved = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('I have written down my phrase',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: _saved ? () => Navigator.pop(context, true) : null,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog();
  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _ctrl = TextEditingController();
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF161B22),
      title: const Text('Import recovery phrase',
          style: TextStyle(color: Colors.white)),
      content: TextField(
        controller: _ctrl,
        maxLines: 3,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          hintText: 'Enter your 12-word phrase',
          hintStyle: TextStyle(color: Colors.white38),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: const Text('Import'),
        ),
      ],
    );
  }
}
