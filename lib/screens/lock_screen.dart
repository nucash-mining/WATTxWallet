import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../services/security_store.dart';
import '../services/totp.dart';
import '../services/wallet_store.dart';

/// The gate in front of the wallet.
///
/// Order is biometric first (one touch), then PIN, then the TOTP code if a
/// second factor is enrolled. Any configured factor arms the lock — a wallet
/// that quietly opens because the *particular* factor checked was unset is a
/// bug, not a convenience.
class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const LockScreen({super.key, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _pin = TextEditingController();
  final _code = TextEditingController();
  final _auth = LocalAuthentication();

  final _pass = TextEditingController();
  bool _needsTotp = false;
  bool _hasPin = false;
  bool _pinDone = false;
  bool _encrypted = false;
  String? _error;
  int _attempts = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _needsTotp = await SecurityStore.totpEnabled();
    _hasPin = await SecurityStore.hasPin();
    _encrypted = await WalletStore.isEncrypted();
    if (mounted) setState(() {});
    if (await SecurityStore.biometricEnabled()) _tryBiometric();
  }

  Future<void> _tryBiometric() async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock your WATTx wallet',
        options: const AuthenticationOptions(
          // NOT biometricOnly. With it set, a sensor that fails or is locked
          // out leaves someone whose only factor is biometrics with no way
          // into their own wallet. Allowing the device credential (the phone's
          // own PIN, pattern or password) guarantees a route in, and it is
          // checked by Android rather than by us.
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      if (ok) _passFirstFactor();
    } catch (_) {
      // Only offer the PIN if one exists. Telling someone to use a PIN they
      // never set leaves them staring at a field that can never accept
      // anything -- locked out of their own wallet with no way forward.
      if (mounted) {
        setState(() => _error = _hasPin
            ? 'Biometrics unavailable. Use your PIN.'
            : 'Not recognised. Tap below to try again — you can also use '
              'your phone\'s PIN, pattern or password.');
      }
    }
  }

  Future<void> _submitPin() async {
    if (await SecurityStore.verifyPin(_pin.text)) {
      _pin.clear();
      _passFirstFactor();
    } else {
      // Rate-limit rather than lock out: scrypt already makes each guess slow,
      // and bricking the only wallet on the device is worse than a delay.
      _attempts++;
      await Future.delayed(Duration(milliseconds: 250 * _attempts.clamp(1, 8)));
      if (mounted) setState(() => _error = 'Wrong PIN.');
    }
  }

  Future<void> _passFirstFactor() async {
    // Biometrics and the PIN do not decrypt anything themselves. They release
    // the passphrase the platform store holds; without one the passphrase is
    // still required, because the seed is genuinely encrypted with it.
    if (_encrypted) {
      final held = await SecurityStore.rememberedPassphrase();
      if (held == null) {
        if (mounted) {
          setState(() => _error =
              'Enter your wallet passphrase to finish unlocking.');
        }
        return;
      }
      if (await WalletStore.unlockMnemonic(held) == null) {
        // The passphrase changed since it was remembered.
        await SecurityStore.forgetPassphrase();
        if (mounted) {
          setState(() => _error = 'Saved passphrase no longer works. Enter it.');
        }
        return;
      }
    }
    if (_needsTotp) {
      if (mounted) setState(() { _pinDone = true; _error = null; });
    } else {
      widget.onUnlocked();
    }
  }

  Future<void> _submitPassphrase() async {
    if (await WalletStore.unlockMnemonic(_pass.text) != null) {
      // Remember it so biometrics or the PIN can release it next time. Kept in
      // the platform store, never alongside the seed.
      await SecurityStore.rememberPassphrase(_pass.text);
      _pass.clear();
      if (_needsTotp) {
        if (mounted) setState(() { _pinDone = true; _error = null; });
      } else {
        widget.onUnlocked();
      }
    } else {
      if (mounted) setState(() => _error = 'Wrong passphrase.');
    }
  }

  Future<void> _submitTotp() async {
    final secret = await SecurityStore.totpSecret();
    if (secret != null && Totp.verify(secret, _code.text)) {
      _code.clear();
      widget.onUnlocked();
    } else {
      if (mounted) setState(() => _error = 'That code is not valid.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 44),
              const SizedBox(height: 12),
              Text(_pinDone ? 'Second factor' : 'Wallet locked',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                _pinDone
                    ? 'Enter the 6-digit code from your authenticator app.'
                    : 'Your coins stay safe while locked. Unlock to spend.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 20),
              if (!_pinDone) ...[
                if (_encrypted) ...[
                  TextField(
                    controller: _pass,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Wallet passphrase',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _submitPassphrase(),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                      onPressed: _submitPassphrase,
                      child: const Text('Unlock')),
                  const SizedBox(height: 4),
                ],
                if (_hasPin) ...[
                  TextField(
                    controller: _pin,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'PIN',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _submitPin(),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                      onPressed: _submitPin, child: const Text('Unlock')),
                ],
                TextButton.icon(
                  onPressed: _tryBiometric,
                  icon: const Icon(Icons.fingerprint),
                  label: Text(_hasPin
                      ? 'Use biometrics'
                      : 'Unlock with biometrics or device PIN'),
                ),
              ] else ...[
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '6-digit code',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _submitTotp(),
                ),
                const SizedBox(height: 12),
                FilledButton(
                    onPressed: _submitTotp, child: const Text('Verify')),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: const TextStyle(color: Color(0xFFF85149))),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
