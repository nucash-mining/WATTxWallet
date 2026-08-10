import 'dart:typed_data';

import 'package:coinslib/coinslib.dart' as coins;

import 'node_service.dart';
import 'wattx_wallet.dart';

class InsufficientFundsException implements Exception {
  final int needed;
  final int available;
  InsufficientFundsException(this.needed, this.available);
  @override
  String toString() {
    final needWtx = (needed / 1e8).toStringAsFixed(8);
    final haveWtx = (available / 1e8).toStringAsFixed(8);
    return 'Not enough balance: need $needWtx WTX (incl. fee), have $haveWtx WTX.';
  }
}

class BuiltTransaction {
  final String hex;
  final int fee; // satoshis
  final int change; // satoshis returned to sender
  BuiltTransaction(this.hex, this.fee, this.change);
}

/// Builds and signs legacy P2PKH WATTx transactions entirely on-device. The
/// private key never leaves [WattxWallet]; only the finished hex is handed to
/// [NodeService.broadcast].
class TxService {
  /// Default fee rate (satoshis per virtual byte). WATTx's minimum relay fee is
  /// 400 sat/vB (0.004 WATTx/kB) — the daemon rejects anything below it as "min
  /// relay fee not met" — so this is the floor, not a guess. The caller can bump
  /// it for faster confirmation.
  static const int defaultFeeRateSatPerVByte = 400;

  /// Dust threshold — outputs below this are refused rather than created as
  /// unspendable change.
  static const int dustThreshold = 600;

  /// Select coins and build a signed transaction sending [amountSats] to
  /// [toAddress], with change back to the wallet's own address.
  ///
  /// Uses a simple accumulate-until-enough selection and recomputes the fee as
  /// inputs are added (fee depends on input count). Throws
  /// [InsufficientFundsException] when the balance cannot cover amount + fee.
  static BuiltTransaction buildSend({
    required WattxWallet wallet,
    required String toAddress,
    required int amountSats,
    required List<Utxo> utxos,
    int feeRateSatPerVByte = defaultFeeRateSatPerVByte,
  }) {
    if (amountSats < dustThreshold) {
      throw ArgumentError('Amount below dust threshold');
    }

    // Only spend mature outputs. Immature coinbase (mining/pool payouts) would
    // be rejected by the daemon as a premature coinbase spend, so they must
    // never be selected — this was the cause of "transaction failed" while the
    // balance looked large. Largest-first among the spendable set.
    final spendable = utxos.where((u) => u.spendable).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sorted = spendable;

    final selected = <Utxo>[];
    int inValue = 0;
    // Legacy sizes: ~148 vB per P2PKH input, ~34 vB per output, ~10 vB overhead.
    // Assume two outputs (recipient + change) for the fee estimate.
    int estFee(int nIn) => ((nIn * 148) + (2 * 34) + 10) * feeRateSatPerVByte;

    for (final u in sorted) {
      selected.add(u);
      inValue += u.value;
      if (inValue >= amountSats + estFee(selected.length)) break;
    }

    final fee = estFee(selected.length);
    if (inValue < amountSats + fee) {
      throw InsufficientFundsException(amountSats + fee, inValue);
    }

    int change = inValue - amountSats - fee;

    final builder = coins.TransactionBuilder(network: wallet.coinsNet);
    builder.setVersion(1);

    for (final u in selected) {
      builder.addInput(
        u.txid,
        u.vout,
        null,
        _hexToBytes(u.scriptPubKey),
      );
    }

    builder.addOutput(toAddress, BigInt.from(amountSats));

    // Fold dust change into the fee rather than create an unspendable output.
    if (change >= dustThreshold) {
      builder.addOutput(wallet.legacyAddress, BigInt.from(change));
    } else {
      change = 0;
    }

    final ecPair = wallet.ecPair;
    for (var i = 0; i < selected.length; i++) {
      builder.sign(vin: i, keyPair: ecPair);
    }

    final tx = builder.build();
    return BuiltTransaction(tx.toHex(), fee, change);
  }
}

Uint8List _hexToBytes(String hex) {
  final clean = hex.startsWith('0x') ? hex.substring(2) : hex;
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
