import 'package:flutter_test/flutter_test.dart';
import 'package:hex/hex.dart';
import 'package:wattx_wallet/services/wattx_wallet.dart';

void main() {
  // Ground truth generated from the browser extension's own crypto
  // (wattx-wallet-extension/src/wattx.js) for the standard BIP39 test mnemonic.
  // If this fails, phone and extension derive DIFFERENT addresses from the same
  // seed — funds would be lost. Do not "fix" the test to match the code.
  const testMnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
  const expectedPriv =
      '477a6912ac2291075e0bb1e01d411761de28e5898a63ba6e8d4d9f87e010304a';
  const expectedPub =
      '0223e95755582066d43e598eb83bacd06687d15b40aff0524ff2a8b8a317c3e64b';
  const expectedLegacy = 'WZ6MH7ztirRwdpK6UwaABzyxnsLRzL3UiV';

  test('derives the extension-identical key and legacy address', () {
    final w = WattxWallet.fromMnemonic(testMnemonic);
    expect(HEX.encode(w.privateKey), expectedPriv);
    expect(HEX.encode(w.publicKey), expectedPub);
    expect(w.legacyAddress, expectedLegacy);
  });

  test('rejects an invalid mnemonic', () {
    expect(() => WattxWallet.fromMnemonic('not a real phrase'),
        throwsArgumentError);
  });

  test('legacy addresses start with W and round-trip a fresh mnemonic', () {
    final m = WattxWallet.generateMnemonic();
    final w = WattxWallet.fromMnemonic(m);
    expect(w.legacyAddress.startsWith('W'), true);
    // Same mnemonic re-derives the same address (deterministic).
    expect(WattxWallet.fromMnemonic(m).legacyAddress, w.legacyAddress);
  });
}
