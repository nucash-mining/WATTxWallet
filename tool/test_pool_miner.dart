// Desktop harness for the mobile pool miner: runs the exact PoolMiner the app
// ships (no Flutter imports in it) against the live pool so the stratum
// protocol, header assembly and share submission can be verified without an
// Android device.
//
//   dart run tool/test_pool_miner.dart <WTX_ADDRESS> [seconds]
import 'dart:async';
import '../lib/services/pool_miner.dart';

Future<void> main(List<String> args) async {
  final address = args.isNotEmpty ? args[0] : '';
  final seconds = args.length > 1 ? int.parse(args[1]) : 60;
  if (address.isEmpty) {
    print('usage: dart run tool/test_pool_miner.dart <WTX_ADDRESS> [seconds]');
    return;
  }

  final miner = PoolMiner(threads: 1);
  miner.statsStream.listen((s) {
    print('hashrate=${s.hashRate.toStringAsFixed(0)} H/s  '
        'shares=${s.sharesAccepted}/${s.sharesRejected}  '
        'connected=${s.connected}'
        '${s.lastError != null ? "  err=${s.lastError}" : ""}');
  });

  print('connecting to ${PoolMiner.defaultHost}:${PoolMiner.defaultPort} as $address');
  await miner.start(address, worker: 'harness');
  await Future.delayed(Duration(seconds: seconds));
  miner.stop();
  print('done');
}
