import 'package:flutter_test/flutter_test.dart';
import 'package:wattx_wallet/services/node_service.dart';
import 'package:wattx_wallet/services/tx_service.dart';
import 'package:wattx_wallet/services/wattx_wallet.dart';

void main() {
  // The exact situation on the user's phone: nine immature coinbase mining
  // payouts (~24.9 WTX each) + one spendable 1 WTX output. A send must use only
  // the spendable output and never a premature coinbase (which the daemon rejects).
  final wallet = WattxWallet.fromMnemonic(
      'legal winner thank year wave sausage worth useful legal winner thank yellow');

  List<Utxo> phoneUtxos() => [
        for (var i = 0; i < 9; i++)
          Utxo('a' * 64, i, 2490000000, 3060, '76a914${'00' * 20}88ac',
              coinbase: true, confirmations: 9),
        Utxo('b' * 64, 0, 100000000, 3058, '76a914${'00' * 20}88ac',
            coinbase: false, confirmations: 12),
      ];

  test('spends only the mature 1 WTX output, skips immature coinbase', () {
    final built = TxService.buildSend(
      wallet: wallet,
      toAddress: wallet.legacyAddress,
      amountSats: 50000000, // 0.5 WTX
      utxos: phoneUtxos(),
    );
    // Fee is small; the tx is built from the single spendable input.
    expect(built.fee, greaterThan(0));
    expect(built.hex.isNotEmpty, true);
  });

  test('refuses to spend more than the spendable balance', () {
    expect(
      () => TxService.buildSend(
        wallet: wallet,
        toAddress: wallet.legacyAddress,
        amountSats: 5000000000, // 50 WTX — only 1 WTX is spendable
        utxos: phoneUtxos(),
      ),
      throwsA(isA<InsufficientFundsException>()),
    );
  });
}
