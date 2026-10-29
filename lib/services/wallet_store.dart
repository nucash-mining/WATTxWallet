import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hex/hex.dart';

import 'touch_entropy.dart';
import 'wallet_crypto.dart';
import 'wattx_wallet.dart';

/// Persists the wallet seed in the platform secure store (Android Keystore /
/// iOS Keychain) and hands out the derived [WattxWallet]. The mnemonic is the
/// only secret written; keys are derived on demand and never persisted.
class WalletStore {
  static const _seedKey = 'wattx_mnemonic';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// True once a wallet exists on this device.
  static Future<bool> hasWallet() async =>
      await _storage.read(key: _seedKey) != null;

  /// Create a brand-new wallet, persist its seed, and return it.
  ///
  /// When [entropy] is supplied the seed comes from the user's gesture mixed
  /// with the platform CSPRNG (see [TouchEntropy]); the mix can only be as
  /// strong as the CSPRNG or stronger, never weaker. Without it the CSPRNG is
  /// used alone, which is what bip39.generateMnemonic already does.
  static Future<WattxWallet> createNew({
    WattxNet net = WattxNet.mainnet,
    TouchEntropy? entropy,
    String? passphrase,
  }) async {
    final String mnemonic;
    if (entropy != null) {
      // 128 bits -> 12 words, the same length the app has always produced.
      final material = entropy.mix(16);
      mnemonic = bip39.entropyToMnemonic(HEX.encode(material));
      // Wipe the copy we hold; the phrase itself is about to be persisted, but
      // the raw entropy has no reason to linger in memory.
      material.fillRange(0, material.length, 0);
    } else {
      mnemonic = WattxWallet.generateMnemonic();
    }
    await _persist(mnemonic, passphrase);
    return WattxWallet.fromMnemonic(mnemonic, net: net);
  }

  /// The phrase is encrypted at rest whenever a passphrase is set, so the
  /// secure store holds ciphertext rather than the seed itself. Without one it
  /// is stored as before — an existing wallet is never silently downgraded or
  /// locked out by an app update.
  static Future<void> _persist(String mnemonic, String? passphrase) async {
    final value = (passphrase != null && passphrase.isNotEmpty)
        ? WalletCrypto.encrypt(mnemonic, passphrase)
        : mnemonic;
    await _storage.write(key: _seedKey, value: value);
  }

  /// True when the stored seed needs a passphrase to read.
  static Future<bool> isEncrypted() async {
    final v = await _storage.read(key: _seedKey);
    return v != null && WalletCrypto.isEncrypted(v);
  }

  /// Encrypt an existing wallet, or change the passphrase on one.
  /// Returns false when [currentPassphrase] does not open the existing seed.
  static Future<bool> setPassphrase(String? currentPassphrase, String newPassphrase) async {
    final stored = await _storage.read(key: _seedKey);
    if (stored == null) return false;
    final String mnemonic;
    if (WalletCrypto.isEncrypted(stored)) {
      final open = currentPassphrase == null
          ? null
          : WalletCrypto.decrypt(stored, currentPassphrase);
      if (open == null) return false;
      mnemonic = open;
    } else {
      mnemonic = stored;
    }
    await _persist(mnemonic, newPassphrase);
    return true;
  }

  /// Null when the passphrase is wrong, or when one is needed and absent.
  static Future<String?> unlockMnemonic(String? passphrase) async {
    final stored = await _storage.read(key: _seedKey);
    if (stored == null) return null;
    if (!WalletCrypto.isEncrypted(stored)) return stored;
    if (passphrase == null || passphrase.isEmpty) return null;
    return WalletCrypto.decrypt(stored, passphrase);
  }

  /// Import an existing recovery phrase. Throws [ArgumentError] on an invalid
  /// phrase (nothing is persisted in that case).
  static Future<WattxWallet> import(String mnemonic,
      {WattxNet net = WattxNet.mainnet, String? passphrase}) async {
    final wallet = WattxWallet.fromMnemonic(mnemonic, net: net); // validates
    await _persist(wallet.mnemonic, passphrase);
    return wallet;
  }

  /// Load the stored wallet, or null if none exists.
  static Future<WattxWallet?> load({
    WattxNet net = WattxNet.mainnet,
    String? passphrase,
  }) async {
    final mnemonic = await unlockMnemonic(passphrase);
    if (mnemonic == null) return null;
    return WattxWallet.fromMnemonic(mnemonic, net: net);
  }

  /// Reveal the mnemonic for backup. Callers must gate this behind device auth.
  static Future<String?> revealMnemonic() => _storage.read(key: _seedKey);

  /// Permanently delete the wallet from this device.
  static Future<void> deleteWallet() => _storage.delete(key: _seedKey);
}
