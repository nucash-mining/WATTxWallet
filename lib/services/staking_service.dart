import 'dart:convert';
import 'dart:typed_data';

import 'package:bs58check/bs58check.dart' as bs58check;
import 'package:crypto/crypto.dart' as crypto;
import 'package:hex/hex.dart';
import 'package:pointycastle/digests/keccak.dart';

import 'node_service.dart';
import 'op_sender_tx.dart';
import 'tx_service.dart';
import 'wattx_wallet.dart';

/// Offline-staking delegation via the on-chain 0x…0086 contract (the real,
/// consensus-enforced path — proven on regtest). "Staking" here means signing an
/// `addDelegation` contract call so a superstaker can stake THIS wallet's coins
/// while the keys stay on the device.
class StakingService {
  /// The offline-staking delegations contract (same on main/test/regtest).
  static const delegationContract = '0000000000000000000000000000000000000086';

  /// VersionVM::GetEVMDefault().toRaw() — the raw VM version pushed in
  /// contract-call outputs.
  static const evmVersion = 4;

  /// The daemon's setdelegateforaddress defaults: DEFAULT_GAS_LIMIT_OP_CREATE
  /// and DEFAULT_GAS_PRICE (40 sat). Up to gasLimit*gasPrice = 1 WTX is funded
  /// from the fee; unused gas is refunded by the miner's coinstake.
  static const addDelegationGasLimit = 2500000;

  /// removeDelegation is a cheap call — the daemon uses
  /// DEFAULT_GAS_LIMIT_OP_SEND for it.
  static const removeDelegationGasLimit = 250000;
  static const defaultGasPrice = 40;

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
  /// hash160 as a lowercase hex STRING in NATURAL byte order — the daemon's
  /// `ToKeyID(pkhStaker).GetReverseHex()`. Despite the name, GetReverseHex
  /// prints m_data[0..19] as stored (it is the reverse of the numeric GetHex
  /// display, not of the bytes); reversing here makes the contract revert with
  /// "Invalid PoD signature" (found the hard way on regtest).
  static String hexStaker(String stakerAddress) {
    return HEX.encode(stakerHash160(stakerAddress));
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

  /// keccak256("removeDelegation()")[:4].
  static Uint8List removeDelegationSelector() {
    final k = KeccakDigest(256);
    return k
        .process(Uint8List.fromList('removeDelegation()'.codeUnits))
        .sublist(0, 4);
  }

  /// Build the signed addDelegation transaction: an OP_SENDER contract call to
  /// the delegations contract, sender-signed with the daemon's
  /// SignatureHashOutput, funded (gas + relay fee) from the wallet's mature
  /// UTXOs, change back to the wallet. Returns the raw hex ready to broadcast.
  static BuiltTransaction buildAddDelegation({
    required WattxWallet wallet,
    required String stakerAddress,
    required int feePercent,
    required List<Utxo> utxos,
    int gasPrice = defaultGasPrice,
    int feeRateSatPerVByte = TxService.defaultFeeRateSatPerVByte,
  }) {
    if (feePercent < 0 || feePercent > 100) {
      throw ArgumentError('Fee percent must be 0-100');
    }
    final callData = encodeAddDelegation(
      stakerHash160: stakerHash160(stakerAddress),
      feePercent: feePercent,
      pod: buildPoD(wallet, stakerAddress),
    );
    return _buildContractCall(
      wallet: wallet,
      callData: callData,
      gasLimit: addDelegationGasLimit,
      gasPrice: gasPrice,
      utxos: utxos,
      feeRateSatPerVByte: feeRateSatPerVByte,
    );
  }

  /// Build the signed removeDelegation transaction (undelegate).
  static BuiltTransaction buildRemoveDelegation({
    required WattxWallet wallet,
    required List<Utxo> utxos,
    int gasPrice = defaultGasPrice,
    int feeRateSatPerVByte = TxService.defaultFeeRateSatPerVByte,
  }) {
    return _buildContractCall(
      wallet: wallet,
      callData: removeDelegationSelector(),
      gasLimit: removeDelegationGasLimit,
      gasPrice: gasPrice,
      utxos: utxos,
      feeRateSatPerVByte: feeRateSatPerVByte,
    );
  }

  /// Assemble + sign an OP_SENDER call to the delegations contract.
  ///
  /// Output 0 (value 0) follows the daemon's CALL_SENDER template:
  ///   push(num 1) push(keyId20) <senderSig slot> OP_SENDER
  ///   push(num 4) push(num gasLimit) push(num gasPrice) push(callData)
  ///   push(contract20) OP_CALL
  /// The sender-sig slot is an empty push while hashing (the daemon's
  /// GetOutputWithoutSenderSig) and afterwards carries the sender scriptSig
  /// serialized WITH its compact-size length prefix inside the push — that is
  /// how UpdateOutput stores it and ExtractSenderData reads it back.
  ///
  /// Signing order matters: the sender signature covers prevouts, sequences
  /// and outputs (not input scriptSigs), so it is created first and injected;
  /// the legacy P2PKH input signatures then commit to the final outputs.
  static BuiltTransaction _buildContractCall({
    required WattxWallet wallet,
    required Uint8List callData,
    required int gasLimit,
    required int gasPrice,
    required List<Utxo> utxos,
    required int feeRateSatPerVByte,
  }) {
    final keyId = wallet.pubKeyHash160;
    final senderP2pkh = Uint8List.fromList(
        [0x76, 0xa9, 0x14, ...keyId, 0x88, 0xac]);

    Uint8List slotScript(Uint8List slot) {
      final bb = BytesBuilder();
      bb.add(OpSender.pushData(OpSender.scriptNum(1))); // addresstype PUBKEYHASH
      bb.add(OpSender.pushData(keyId));
      bb.add(slot);
      bb.addByte(OpSender.opSender);
      bb.add(OpSender.pushData(OpSender.scriptNum(evmVersion)));
      bb.add(OpSender.pushData(OpSender.scriptNum(gasLimit)));
      bb.add(OpSender.pushData(OpSender.scriptNum(gasPrice)));
      bb.add(OpSender.pushData(callData));
      bb.add(OpSender.pushData(OpSender.hexToBytes(delegationContract)));
      bb.addByte(OpSender.opCall);
      return bb.toBytes();
    }

    final unsignedScript = slotScript(OpSender.pushData(Uint8List(0)));

    // Coin selection: the whole cost is fee (the contract output carries no
    // value): gas budget + relay fee on the estimated final size. Only mature
    // outputs — immature coinbase would be rejected exactly like in sends.
    final gasFee = gasLimit * gasPrice;
    final spendable = utxos.where((u) => u.spendable).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    // ~148 vB per input; contract output ≈ script + 11; change 34; overhead 10.
    int estFee(int nIn) =>
        gasFee +
        ((nIn * 148) + unsignedScript.length + 130 + 34 + 10) *
            feeRateSatPerVByte;

    final selected = <Utxo>[];
    var inValue = 0;
    for (final u in spendable) {
      selected.add(u);
      inValue += u.value;
      if (inValue >= estFee(selected.length)) break;
    }
    final fee = estFee(selected.length);
    if (selected.isEmpty || inValue < fee) {
      throw InsufficientFundsException(fee, inValue);
    }
    var change = inValue - fee;

    final tx = OpSender();
    for (final u in selected) {
      tx.inputs.add(
          OpSenderInput(u.txid, u.vout, OpSender.hexToBytes(u.scriptPubKey)));
    }
    tx.outputs.add(OpSenderOutput(0, unsignedScript,
        scriptWithoutSenderSig: unsignedScript));
    if (change >= TxService.dustThreshold) {
      final changeScript = Uint8List.fromList(
          [0x76, 0xa9, 0x14, ...keyId, 0x88, 0xac]);
      tx.outputs.add(OpSenderOutput(change, changeScript));
    } else {
      change = 0;
    }

    // 1) Sender signature over SignatureHashOutput (amount = output value = 0).
    final senderHash = tx.signatureHashOutput(0, senderP2pkh, 0);
    final senderDer =
        OpSender.derSignature(wallet.ecPair.sign(senderHash), OpSender.sighashAll);
    final senderScriptSig = Uint8List.fromList([
      ...OpSender.pushData(senderDer),
      ...OpSender.pushData(wallet.publicKey),
    ]);
    // The slot stores the scriptSig SERIALIZED (compact-size prefix + bytes).
    final slotData = Uint8List.fromList([
      ...OpSender.varint(senderScriptSig.length),
      ...senderScriptSig,
    ]);
    tx.outputs[0].script = slotScript(OpSender.pushData(slotData));

    // 2) Legacy P2PKH input signatures over the final outputs.
    for (var i = 0; i < tx.inputs.length; i++) {
      final hash = tx.signatureHashLegacy(i, tx.inputs[i].scriptPubKey);
      final der =
          OpSender.derSignature(wallet.ecPair.sign(hash), OpSender.sighashAll);
      tx.inputs[i].scriptSig = Uint8List.fromList([
        ...OpSender.pushData(der),
        ...OpSender.pushData(wallet.publicKey),
      ]);
    }

    return BuiltTransaction(OpSender.bytesToHex(tx.serialize()), fee, change);
  }
}
