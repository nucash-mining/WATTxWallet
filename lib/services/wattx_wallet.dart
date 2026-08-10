import 'dart:typed_data';

import 'package:bip32/bip32.dart' as bip32;
import 'package:bip39/bip39.dart' as bip39;
import 'package:bs58check/bs58check.dart' as bs58check;
import 'package:coinslib/coinslib.dart' as coins;
import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/digests/ripemd160.dart';

/// WATTx (Qtum-derived UTXO) network parameters. The mainnet values MUST match
/// the browser extension (wattx-wallet-extension/src/wattx.js) so the SAME seed
/// produces the SAME addresses on phone and extension — a mismatch sends funds
/// to an address nobody controls, so [WattxWallet] is covered by a ground-truth
/// test vector. Only the base58/bech32 version bytes differ between networks;
/// the signing logic is identical, which is why regtest can prove mainnet code.
class WattxNet {
  final int pubKeyHash;
  final int scriptHash;
  final int wif;
  final String bech32;

  static const messagePrefix = '\x18WATTx Signed Message:\n';
  // BIP32 xpub/xprv version bytes (standard, shared across networks).
  static const bip32Public = 0x0488b21e;
  static const bip32Private = 0x0488ade4;
  // BIP86-style account path used by the extension. coinType 22356 = WATTx.
  static const derivationPath = "m/86'/22356'/0'/0/0";

  const WattxNet({
    required this.pubKeyHash,
    required this.scriptHash,
    required this.wif,
    required this.bech32,
  });

  /// Mainnet — 'W…' legacy addresses. The production default.
  static const mainnet =
      WattxNet(pubKeyHash: 73, scriptHash: 75, wif: 128, bech32: 'wx');

  /// Regtest — 'w…' legacy addresses. Used only to prove signing end to end.
  static const regtest =
      WattxNet(pubKeyHash: 135, scriptHash: 137, wif: 239, bech32: 'wxrt');

  bip32.NetworkType get bip32Network => bip32.NetworkType(
        bip32: bip32.Bip32Type(public: bip32Public, private: bip32Private),
        wif: wif,
      );

  coins.NetworkType get coinsNetwork => coins.NetworkType(
        messagePrefix: messagePrefix,
        bech32: bech32,
        bip32: coins.Bip32Type(public: bip32Public, private: bip32Private),
        pubKeyHash: pubKeyHash,
        scriptHash: scriptHash,
        wif: wif,
        opreturnSize: 80,
      );
}

/// Backwards-compatible mainnet alias.
class WattxNetwork {
  static const derivationPath = WattxNet.derivationPath;
  static WattxNet get mainnet => WattxNet.mainnet;
  static coins.NetworkType get coinsNetwork => WattxNet.mainnet.coinsNetwork;
}

Uint8List _hash160(Uint8List data) {
  final sha = Uint8List.fromList(crypto.sha256.convert(data).bytes);
  return RIPEMD160Digest().process(sha);
}

/// A self-custody WATTx key pair derived from a BIP39 mnemonic, with the legacy
/// P2PKH address used for balances, sends, and staking delegation.
class WattxWallet {
  final String mnemonic;
  final Uint8List privateKey;
  final Uint8List publicKey; // compressed
  final String legacyAddress;
  final WattxNet net;

  WattxWallet._({
    required this.mnemonic,
    required this.privateKey,
    required this.publicKey,
    required this.legacyAddress,
    required this.net,
  });

  static String generateMnemonic() => bip39.generateMnemonic();

  static bool validateMnemonic(String m) => bip39.validateMnemonic(m.trim());

  /// Derive the wallet at [WattxNet.derivationPath]. Throws on an invalid
  /// mnemonic rather than silently deriving from garbage.
  factory WattxWallet.fromMnemonic(String mnemonic,
      {WattxNet net = WattxNet.mainnet}) {
    final m = mnemonic.trim().toLowerCase();
    if (!bip39.validateMnemonic(m)) {
      throw ArgumentError('Invalid recovery phrase');
    }
    final seed = bip39.mnemonicToSeed(m);
    final node = bip32.BIP32
        .fromSeed(seed, net.bip32Network)
        .derivePath(WattxNet.derivationPath);
    final priv = node.privateKey;
    if (priv == null) throw StateError('derivation produced no private key');
    final pub = node.publicKey; // compressed
    return WattxWallet._(
      mnemonic: m,
      privateKey: Uint8List.fromList(priv),
      publicKey: Uint8List.fromList(pub),
      legacyAddress: legacyAddressFromPubkey(Uint8List.fromList(pub), net),
      net: net,
    );
  }

  /// base58check(pubKeyHash ‖ hash160(pubkey)) — the legacy address.
  static String legacyAddressFromPubkey(Uint8List compressedPubkey,
      [WattxNet net = WattxNet.mainnet]) {
    final payload = Uint8List.fromList([
      net.pubKeyHash,
      ..._hash160(compressedPubkey),
    ]);
    return bs58check.encode(payload);
  }

  /// hash160 of the pubkey — the 20-byte key id used in scriptPubKey and as the
  /// delegator/staker id in the delegation contract call.
  Uint8List get pubKeyHash160 => _hash160(publicKey);

  /// A single coinslib network instance for this wallet. coinslib compares
  /// networks by object identity, so the ECPair and the TransactionBuilder MUST
  /// share the same instance — hence this cached field rather than net.coinsNetwork.
  late final coins.NetworkType coinsNet = net.coinsNetwork;

  /// coinslib ECPair for signing.
  coins.ECPair get ecPair =>
      coins.ECPair.fromPrivateKey(privateKey, network: coinsNet);
}
