import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/security_store.dart';
import '../services/totp.dart';

/// Enrol an authenticator app as a second factor.
///
/// The secret is only persisted after the user has produced a valid code from
/// it. Saving on display would let someone arm a factor their authenticator
/// never actually received — and then be locked out of their own wallet.
class TotpSetupScreen extends StatefulWidget {
  const TotpSetupScreen({super.key});

  @override
  State<TotpSetupScreen> createState() => _TotpSetupScreenState();
}

class _TotpSetupScreenState extends State<TotpSetupScreen> {
  final String _secret = Totp.generateSecret();
  final _code = TextEditingController();
  String? _error;
  bool _revealed = false;

  Future<void> _confirm() async {
    if (!Totp.verify(_secret, _code.text)) {
      setState(() => _error = 'That code did not match. Check the time on your '
          'phone is correct, then try the next one.');
      return;
    }
    await SecurityStore.enableTotp(_secret);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Two-factor authentication')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Scan this with your authenticator app, then enter the code it '
              'shows to confirm it works.',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 16),
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                color: Colors.white,
                child: QrImageView(
                  data: Totp.provisioningUri(_secret),
                  size: 200,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // A phone that cannot scan its own screen needs the secret in text.
            TextButton(
              onPressed: () => setState(() => _revealed = !_revealed),
              child: Text(_revealed ? 'Hide setup key' : 'Enter it manually'),
            ),
            if (_revealed) ...[
              SelectableText(
                _secret,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: 'monospace', letterSpacing: 1.5),
              ),
              TextButton.icon(
                onPressed: () => Clipboard.setData(ClipboardData(text: _secret)),
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy'),
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '6-digit code',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _confirm(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Color(0xFFF85149))),
            ],
            const SizedBox(height: 16),
            FilledButton(
                onPressed: _confirm, child: const Text('Turn on 2FA')),
            const SizedBox(height: 10),
            const Text(
              'Keep your recovery phrase safe. If you lose your authenticator, '
              'the phrase is what restores this wallet — 2FA protects the app '
              'on this device, not the coins on the chain.',
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}
