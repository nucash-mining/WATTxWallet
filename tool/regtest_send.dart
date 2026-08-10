// Signing test driver — proves buildSend produces a daemon-valid transaction.
// Runs the SAME signing code the app uses, only with regtest version bytes.
//
//   dart run tool/regtest_send.dart address <mnemonic>
//   dart run tool/regtest_send.dart build <mnemonic> <toAddr> <amountSats> <utxosJsonFile>
import 'dart:convert';
import 'dart:io';

import 'package:wattx_wallet/services/node_service.dart';
import 'package:wattx_wallet/services/tx_service.dart';
import 'package:wattx_wallet/services/wattx_wallet.dart';

void main(List<String> args) {
  final cmd = args.isEmpty ? '' : args[0];
  if (cmd == 'address') {
    final w = WattxWallet.fromMnemonic(args[1], net: WattxNet.regtest);
    stdout.writeln(w.legacyAddress);
  } else if (cmd == 'build') {
    final w = WattxWallet.fromMnemonic(args[1], net: WattxNet.regtest);
    final toAddr = args[2];
    final amount = int.parse(args[3]);
    final utxosJson = jsonDecode(File(args[4]).readAsStringSync()) as List;
    final utxos = utxosJson
        .map((e) => Utxo.fromJson(e as Map<String, dynamic>))
        .toList();
    final built = TxService.buildSend(
      wallet: w,
      toAddress: toAddr,
      amountSats: amount,
      utxos: utxos,
      feeRateSatPerVByte: 400,
    );
    stderr.writeln('fee=${built.fee} change=${built.change}');
    stdout.writeln(built.hex);
  } else {
    stderr.writeln('usage: address|build ...');
    exit(2);
  }
}
