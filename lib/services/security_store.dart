import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

import 'wallet_store.dart';

/// PIN, biometrics and TOTP for the wallet lock.
///
/// The seed itself already lives in the platform secure store; this adds the
/// gate in front of it. Nothing here is a substitute for that storage — it
/// decides *when* the app will hand the seed over.
class SecurityStore {
  static const _pinHashKey = 'sec_pin_hash';
  static const _pinSaltKey = 'sec_pin_salt';
  static const _bioKey = 'sec_biometric_enabled';
  static const _totpKey = 'sec_totp_secret';
  static const _lockKey = 'sec_lock_enabled';
  static const _passKey = 'sec_remembered_passphrase';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // ---- PIN ---------------------------------------------------------------

  /// scrypt, not a bare hash: a 6-digit PIN has a million possibilities, so the
  /// only thing standing between a stolen device and the wallet is how long
  /// each guess takes. N=2^14 keeps that painful while staying usable on a
  /// phone. A per-device salt stops one rainbow table covering every install.
  static Uint8List _derive(String pin, Uint8List salt) {
    final params = ScryptParameters(16384, 8, 1, 32, salt);
    return (Scrypt()..init(params))
        .process(Uint8List.fromList(utf8.encode(pin)));
  }

  static Future<void> setPin(String pin) async {
    final rng = Random.secure();
    final salt = Uint8List.fromList(List.generate(16, (_) => rng.nextInt(256)));
    final hash = _derive(pin, salt);
    await _storage.write(key: _pinSaltKey, value: base64Encode(salt));
    await _storage.write(key: _pinHashKey, value: base64Encode(hash));
    await _storage.write(key: _lockKey, value: 'true');
  }

  static Future<bool> hasPin() async =>
      await _storage.read(key: _pinHashKey) != null;

  /// Constant-time comparison: a PIN check that returns early leaks how much
  /// of the guess was right.
  static Future<bool> verifyPin(String pin) async {
    final saltB64 = await _storage.read(key: _pinSaltKey);
    final hashB64 = await _storage.read(key: _pinHashKey);
    if (saltB64 == null || hashB64 == null) return false;
    final expected = base64Decode(hashB64);
    final actual = _derive(pin, base64Decode(saltB64));
    if (expected.length != actual.length) return false;
    var diff = 0;
    for (var i = 0; i < expected.length; i++) {
      diff |= expected[i] ^ actual[i];
    }
    return diff == 0;
  }

  static Future<void> clearPin() async {
    await _storage.delete(key: _pinHashKey);
    await _storage.delete(key: _pinSaltKey);
  }

  // ---- biometrics --------------------------------------------------------

  static Future<bool> biometricEnabled() async =>
      (await _storage.read(key: _bioKey)) == 'true';

  static Future<void> setBiometricEnabled(bool on) =>
      _storage.write(key: _bioKey, value: on ? 'true' : 'false');

  // ---- TOTP (second factor) ---------------------------------------------

  static Future<String?> totpSecret() => _storage.read(key: _totpKey);

  static Future<bool> totpEnabled() async => await totpSecret() != null;

  /// Only stored once the user has proved they can produce a code from it —
  /// enrolling a secret the authenticator never received would lock them out.
  static Future<void> enableTotp(String secret) =>
      _storage.write(key: _totpKey, value: secret);

  static Future<void> disableTotp() => _storage.delete(key: _totpKey);

  // ---- the gate ----------------------------------------------------------

  /// Whether the app should demand authentication before revealing the wallet.
  ///
  /// An encrypted wallet ALWAYS demands it, regardless of which convenience
  /// factors are configured. Gating only on biometrics-or-PIN is the bug that
  /// let a user who had set only a passphrase walk straight in.
  static Future<bool> lockEnabled() async =>
      await WalletStore.isEncrypted() ||
      await hasPin() ||
      await biometricEnabled() ||
      await totpEnabled();

  // ---- passphrase held for biometric / PIN unlock -------------------------

  /// Biometrics and the PIN do not decrypt anything by themselves; they release
  /// the passphrase the platform store is holding. Kept separate from the seed
  /// so that turning the convenience off leaves the wallet encrypted exactly as
  /// it was, rather than quietly weakening it.
  static Future<void> rememberPassphrase(String passphrase) =>
      _storage.write(key: _passKey, value: passphrase);

  static Future<String?> rememberedPassphrase() => _storage.read(key: _passKey);

  static Future<void> forgetPassphrase() => _storage.delete(key: _passKey);

  static Future<void> clearAll() async {
    await clearPin();
    await disableTotp();
    await forgetPassphrase();
    await _storage.delete(key: _bioKey);
    await _storage.delete(key: _lockKey);
  }
}
