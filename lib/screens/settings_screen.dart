import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/wallet_provider.dart';
import '../services/local_node.dart';
import '../services/security_store.dart';
import 'totp_setup_screen.dart';
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
          const _SectionHeader('Security'),
          const _SecuritySection(),
          const _SectionHeader('Node'),
          const _FullNodeSection(),
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


/// PIN, biometrics and 2FA, each reflecting what is actually stored rather than
/// local widget state — so the switches cannot drift out of step with the lock.
class _SecuritySection extends StatefulWidget {
  const _SecuritySection();

  @override
  State<_SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends State<_SecuritySection> {
  bool _hasPin = false, _bio = false, _totp = false, _loaded = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final p = await SecurityStore.hasPin();
    final b = await SecurityStore.biometricEnabled();
    final t = await SecurityStore.totpEnabled();
    if (mounted) setState(() { _hasPin = p; _bio = b; _totp = t; _loaded = true; });
  }

  Future<void> _setPin() async {
    final pin = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('Set a PIN'),
          content: TextField(
            controller: c,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'At least 4 digits'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, c.text),
                child: const Text('Save')),
          ],
        );
      },
    );
    if (pin != null && pin.length >= 4) {
      await SecurityStore.setPin(pin);
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    return Column(children: [
      ListTile(
        leading: const Icon(Icons.pin, color: Color(0xFF58A6FF)),
        title: const Text('PIN', style: TextStyle(color: Colors.white)),
        subtitle: Text(_hasPin ? 'Set' : 'Not set',
            style: const TextStyle(color: Colors.white54)),
        trailing: _hasPin
            ? TextButton(
                onPressed: () async {
                  await SecurityStore.clearPin();
                  // Dropping the PIN would otherwise leave biometrics with no
                  // fallback, which is the lockout this guards against.
                  if (await SecurityStore.biometricEnabled()) {
                    await SecurityStore.setBiometricEnabled(false);
                  }
                  await _refresh();
                },
                child: const Text('Remove'))
            : null,
        onTap: _setPin,
      ),
      SwitchListTile(
        secondary: const Icon(Icons.fingerprint, color: Color(0xFF3FB950)),
        title: const Text('Biometric unlock',
            style: TextStyle(color: Colors.white)),
        subtitle: const Text('Fingerprint or face, checked by Android',
            style: TextStyle(color: Colors.white54)),
        value: _bio,
        onChanged: (v) async {
          // Biometrics alone is a single point of failure: a sensor that stops
          // working, a re-enrolled fingerprint, or a lockout would leave no way
          // into the wallet at all. A PIN is the fallback, so require one
          // before biometrics can be armed.
          if (v && !_hasPin) {
            await _setPin();
            if (!await SecurityStore.hasPin()) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text(
                      'Set a PIN first — it is the fallback if biometrics fail.'),
                ));
              }
              return;
            }
          }
          await SecurityStore.setBiometricEnabled(v);
          await _refresh();
        },
      ),
      SwitchListTile(
        secondary: const Icon(Icons.verified_user, color: Color(0xFFF7C948)),
        title: const Text('Two-factor (TOTP)',
            style: TextStyle(color: Colors.white)),
        subtitle: Text(
            _totp ? 'Enabled' : 'Ask for an authenticator code as well',
            style: const TextStyle(color: Colors.white54)),
        value: _totp,
        onChanged: (v) async {
          if (v) {
            final ok = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const TotpSetupScreen()));
            if (ok == true) await _refresh();
          } else {
            await SecurityStore.disableTotp();
            await _refresh();
          }
        },
      ),
    ]);
  }
}


/// Run the chain on this device.
///
/// The status line is polled rather than latched, because the daemon is a
/// separate process that can stop at any time — a panel that says it is
/// validating when nothing is running is worse than no panel at all.
class _FullNodeSection extends StatefulWidget {
  const _FullNodeSection();

  @override
  State<_FullNodeSection> createState() => _FullNodeSectionState();
}

class _FullNodeSectionState extends State<_FullNodeSection> {
  bool _supported = false, _running = false, _loaded = false, _busy = false;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final s = await LocalNode.supported();
    final r = await LocalNode.isRunning();
    if (mounted) setState(() { _supported = s; _running = r; _loaded = true; });
  }

  Future<void> _toggle(bool on) async {
    setState(() { _busy = true; _error = null; });
    if (on) {
      final err = await LocalNode.start();
      // Remember the choice only if the node actually started, so a device
      // that cannot run it does not keep retrying on every app open.
      await LocalNode.setWanted(err == null);
      if (err != null && mounted) setState(() => _error = err);
    } else {
      await LocalNode.setWanted(false);
      await LocalNode.stop();
    }
    if (mounted) setState(() => _busy = false);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    // Hidden rather than shown-and-broken where no daemon ships for this ABI.
    if (!_supported) {
      return const ListTile(
        leading: Icon(Icons.dns_outlined, color: Colors.white38),
        title: Text('Full node', style: TextStyle(color: Colors.white54)),
        subtitle: Text('Not available for this device',
            style: TextStyle(color: Colors.white38)),
      );
    }
    return Column(children: [
      SwitchListTile(
        secondary: Icon(Icons.dns,
            color: _running ? const Color(0xFF3FB950) : Colors.white38),
        title: const Text('Run a full node',
            style: TextStyle(color: Colors.white)),
        subtitle: Text(
          _busy
              ? 'Working…'
              : _running
                  ? 'Validating the chain on this device. Balances come from '
                      'it once it has caught up with the network; until then '
                      'the public server is used. Keeps running while locked.'
                  : 'Verify the chain yourself instead of trusting a public '
                      'indexer. WATTx is small, so this is practical on a phone.',
          style: const TextStyle(color: Colors.white54),
        ),
        value: _running,
        onChanged: _busy ? null : _toggle,
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(_error!,
              style: const TextStyle(color: Color(0xFFF85149), fontSize: 12)),
        ),
    ]);
  }
}
