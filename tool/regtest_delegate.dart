// Delegation signing test driver — proves buildAddDelegation produces a
// daemon-valid OP_SENDER transaction. Runs the SAME code the app uses, only
// with regtest version bytes.
//
//   dart run tool/regtest_delegate.dart address <mnemonic>
//   dart run tool/regtest_delegate.dart build <mnemonic> <stakerAddr> <feePct> <utxosJsonFile>
//   dart run tool/regtest_delegate.dart remove <mnemonic> <utxosJsonFile>
import 'dart:convert';
import 'dart:io';

import 'package:wattx_wallet/services/node_service.dart';
import 'package:wattx_wallet/services/staking_service.dart';
import 'package:wattx_wallet/services/wattx_wallet.dart';

List<Utxo> readUtxos(String path) => (jsonDecode(File(path).readAsStringSync())
        as List)
    .map((e) => Utxo.fromJson(e as Map<String, dynamic>))
    .toList();

void main(List<String> args) {
  final cmd = args.isEmpty ? '' : args[0];
  if (cmd == 'address') {
    final w = WattxWallet.fromMnemonic(args[1], net: WattxNet.regtest);
    stdout.writeln(w.legacyAddress);
  } else if (cmd == 'build') {
    final w = WattxWallet.fromMnemonic(args[1], net: WattxNet.regtest);
    final built = StakingService.buildAddDelegation(
      wallet: w,
      stakerAddress: args[2],
      feePercent: int.parse(args[3]),
      utxos: readUtxos(args[4]),
    );
    stderr.writeln('fee=${built.fee} change=${built.change}');
    stdout.writeln(built.hex);
  } else if (cmd == 'remove') {
    final w = WattxWallet.fromMnemonic(args[1], net: WattxNet.regtest);
    final built =
        StakingService.buildRemoveDelegation(wallet: w, utxos: readUtxos(args[2]));
    stderr.writeln('fee=${built.fee} change=${built.change}');
    stdout.writeln(built.hex);
  } else {
    stderr.writeln('usage: address|build|remove ...');
    exit(2);
  }
}
