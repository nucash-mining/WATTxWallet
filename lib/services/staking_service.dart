import 'dart:convert';
import 'dart:typed_data';

import 'package:bs58check/bs58check.dart' as bs58check;
import 'package:crypto/crypto.dart' as crypto;
import 'package:hex/hex.dart';
import 'package:pointycastle/digests/keccak.dart';

import 'node_service.dart';
import 'wattx_wallet.dart';

/// Thrown while on-chain delegation staking is not yet enabled in the wallet.
class StakingNotReadyException implements Exception {
  final String message;
  StakingNotReadyException(this.message);
  @override
  String toString() => message;
}

/// Offline-staking delegation via the on-chain 0x…0086 contract (the real,
/// consensus-enforced path — proven on regtest). "Staking" here means signing an
/// `addDelegation` contract call so a superstaker can stake THIS wallet's coins
/// while the keys stay on the device.
///
/// The address-signing primitives below (hexStaker, ABI, Proof-of-Delegation)
/// are implemented and unit-testable. Broadcasting is gated by
/// [buildAddDelegation] until the Qtum OP_SENDER sender-signature assembly is
/// verified end-to-end on regtest — the same discipline the P2PKH send passed
/// before it was allowed to move funds.
class StakingService {
  /// The offline-staking delegations contract (same on main/test/regtest).
  static const delegationContract = '0000000000000000000000000000000000000086';

  /// WATTx inherited Qtum's message-signing magic verbatim — it is NOT the
  /// "WATTx Signed Message" prefix the browser extension uses. The delegation
  /// Proof-of-Delegation must be signed with THIS or consensus rejects it.
  /// (Proven: the daemon's verifymessage accepts a PoD signed with this prefix.)
  static const messageMagic = 'Qtum Signed Message:\n';

  /// The Bitcoin-style message hash the PoD is signed over: double-SHA256 of
  /// varint-prefixed(magic) ‖ varint-prefixed(message).
  static Uint8List messageHash(String message) {
    final bb = BytesBuilder();
    final magic = utf8.encode(messageMagic);
    bb.add(_varint(magic.length));
    bb.add(magic);
    final msg = utf8.encode(message);
    bb.add(_varint(msg.length));
    bb.add(msg);
    final h1 = crypto.sha256.convert(bb.toBytes()).bytes;
    return Uint8List.fromList(crypto.sha256.convert(h1).bytes);
  }

  /// The 65-byte compact-recoverable Proof-of-Delegation: the delegator signs
  /// the hexStaker string. Byte-for-byte what the daemon's SignMessage produces
  /// and what addDelegation embeds.
  static Uint8List buildPoD(WattxWallet wallet, String stakerAddress) {
    return wallet.ecPair.signRecoverable(messageHash(hexStaker(stakerAddress)));
  }

  /// keccak256("addDelegation(address,uint8,bytes)")[:4] — the call selector.
  static Uint8List addDelegationSelector() {
    final k = KeccakDigest(256);
    final sig = Uint8List.fromList('addDelegation(address,uint8,bytes)'.codeUnits);
    final out = k.process(sig);
    return out.sublist(0, 4);
  }

  /// The staker's 20-byte key id (hash160) as the contract expects it: the
  /// hash160 extracted from a legacy WATTx address.
  static Uint8List stakerHash160(String stakerAddress) {
    final decoded = bs58check.decode(stakerAddress);
    // [version][20-byte hash160]
    return Uint8List.fromList(decoded.sublist(1));
  }

  /// The message the delegator signs for the Proof-of-Delegation: the staker
  /// hash160 in REVERSED byte order, as a lowercase hex STRING (matches the
  /// daemon's `ToKeyID(pkhStaker).GetReverseHex()`).
  static String hexStaker(String stakerAddress) {
    final h = stakerHash160(stakerAddress);
    final reversed = Uint8List.fromList(h.reversed.toList());
    return HEX.encode(reversed);
  }

  /// ABI-encode addDelegation(_staker, _fee, _PoD) → call data (with selector).
  static Uint8List encodeAddDelegation({
    required Uint8List stakerHash160,
    required int feePercent,
    required Uint8List pod,
  }) {
    final out = <int>[];
    out.addAll(addDelegationSelector());
    // _staker: address, left-padded to 32 bytes.
    out.addAll(Uint8List(12));
    out.addAll(stakerHash160);
    // _fee: uint8 as 32-byte word.
    final fee = Uint8List(32);
    fee[31] = feePercent & 0xff;
    out.addAll(fee);
    // _PoD: dynamic bytes → head is the offset (0x60 = 3 words in).
    final off = Uint8List(32);
    off[31] = 0x60;
    out.addAll(off);
    // tail: length word + right-padded data.
    final len = Uint8List(32);
    len[31] = pod.length & 0xff;
    len[30] = (pod.length >> 8) & 0xff;
    out.addAll(len);
    out.addAll(pod);
    final pad = (32 - (pod.length % 32)) % 32;
    out.addAll(Uint8List(pad));
    return Uint8List.fromList(out);
  }

  static Uint8List _varint(int n) {
    if (n < 0xfd) return Uint8List.fromList([n]);
    if (n <= 0xffff) return Uint8List.fromList([0xfd, n & 0xff, n >> 8]);
    return Uint8List.fromList(
        [0xfe, n & 0xff, (n >> 8) & 0xff, (n >> 16) & 0xff, (n >> 24) & 0xff]);
  }

  /// Build the signed addDelegation transaction. NOT YET ENABLED: the Qtum
  /// OP_SENDER sender-signature must be proven daemon-valid on regtest first.
  static String buildAddDelegation({
    required WattxWallet wallet,
    required String stakerAddress,
    required int feePercent,
    required List<Utxo> utxos,
  }) {
    throw StakingNotReadyException(
      'On-chain delegation staking is being finalized and will be enabled in a '
      'wallet update. The chain path is verified; the transaction builder is '
      'undergoing the same on-chain testing the send path passed.',
    );
  }
}
