import 'package:flutter_test/flutter_test.dart';
import 'package:hex/hex.dart';
import 'package:wattx_wallet/services/node_service.dart';
import 'package:wattx_wallet/services/staking_service.dart';
import 'package:wattx_wallet/services/wattx_wallet.dart';

void main() {
  // The regtest staker/delegator pair the on-chain proof used (2026-08-10):
  // this exact combination produced a delegation the daemon's
  // getdelegationsforstaker read back with a valid PoD (regtest tx
  // 0f1a66cb8fc98aff43a2881ae419e9f36c5aa75cb8af7c97c6036df9be85f963).
  const testMnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
  const regtestStaker = 'wNp9EJGsEGDMKs47oFVXR7f4UgSrA4YPDV';

  test('hexStaker is the hash160 in NATURAL byte order (GetReverseHex trap)',
      () {
    // GetReverseHex prints m_data[0..19] as stored — reversing the bytes made
    // the delegations contract revert with "Invalid PoD signature". Guard the
    // direction with the mainnet-format staker the user delegates to.
    final h = StakingService.stakerHash160(regtestStaker);
    expect(StakingService.hexStaker(regtestStaker), HEX.encode(h));
    expect(StakingService.hexStaker(regtestStaker),
        isNot(HEX.encode(h.reversed.toList())));
  });

  test('addDelegation selector matches keccak("addDelegation(address,uint8,bytes)")',
      () {
    expect(HEX.encode(StakingService.addDelegationSelector()), '4c0e968c');
  });

  test('buildAddDelegation produces the regtest-proven transaction shape', () {
    final w = WattxWallet.fromMnemonic(testMnemonic, net: WattxNet.regtest);
    final utxos = [
      Utxo(
        '6c296dd1567e989a272c4d7dcd42b1dd4c236411c9093cacb242711ef4d4d31a',
        1,
        1000000000,
        417,
        '76a914724a99b2592ba4bf9f27aaebf773187111ad2a9e88ac',
      ),
    ];
    final built = StakingService.buildAddDelegation(
      wallet: w,
      stakerAddress: regtestStaker,
      feePercent: 10,
      utxos: utxos,
    );
    // Gas budget dominates the fee: 2.5M * 40 sat = 1 WTX, plus relay fee.
    expect(built.fee, greaterThan(100000000));
    expect(built.fee + built.change, 1000000000);
    final tx = built.hex;
    // OP_SENDER (c4) then the call part: VM version 4, gas limit 2.5M, gas
    // price 40, PUSHDATA1(0xe4) calldata beginning with the addDelegation
    // selector — the exact byte run from the regtest-accepted transaction.
    expect(tx, contains('c4010403a0252601284ce44c0e968c'));
    expect(
        tx, contains('140000000000000000000000000000000000000086c2'));
    // The ABI payload carries the staker hash160 followed by the fee word.
    expect(
        tx,
        contains(
            '${HEX.encode(StakingService.stakerHash160(regtestStaker))}'
            '000000000000000000000000000000000000000000000000000000000000000a'));
  });

  test('buildAddDelegation refuses immature coinbase funding', () {
    final w = WattxWallet.fromMnemonic(testMnemonic, net: WattxNet.regtest);
    final immature = [
      Utxo('00' * 32, 0, 2000000000, 500,
          '76a914724a99b2592ba4bf9f27aaebf773187111ad2a9e88ac',
          coinbase: true, confirmations: 5),
    ];
    expect(
      () => StakingService.buildAddDelegation(
        wallet: w,
        stakerAddress: regtestStaker,
        feePercent: 10,
        utxos: immature,
      ),
      throwsA(isA<Exception>()),
    );
  });
}
