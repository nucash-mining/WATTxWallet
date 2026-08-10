import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
  static Future<WattxWallet> createNew({WattxNet net = WattxNet.mainnet}) async {
    final mnemonic = WattxWallet.generateMnemonic();
    await _storage.write(key: _seedKey, value: mnemonic);
    return WattxWallet.fromMnemonic(mnemonic, net: net);
  }

  /// Import an existing recovery phrase. Throws [ArgumentError] on an invalid
  /// phrase (nothing is persisted in that case).
  static Future<WattxWallet> import(String mnemonic,
      {WattxNet net = WattxNet.mainnet}) async {
    final wallet = WattxWallet.fromMnemonic(mnemonic, net: net); // validates
    await _storage.write(key: _seedKey, value: wallet.mnemonic);
    return wallet;
  }

  /// Load the stored wallet, or null if none exists.
  static Future<WattxWallet?> load({WattxNet net = WattxNet.mainnet}) async {
    final mnemonic = await _storage.read(key: _seedKey);
    if (mnemonic == null) return null;
    return WattxWallet.fromMnemonic(mnemonic, net: net);
  }

  /// Reveal the mnemonic for backup. Callers must gate this behind device auth.
  static Future<String?> revealMnemonic() => _storage.read(key: _seedKey);

  /// Permanently delete the wallet from this device.
  static Future<void> deleteWallet() => _storage.delete(key: _seedKey);
}
