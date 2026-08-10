import 'package:flutter/foundation.dart';

import '../services/node_service.dart';
import '../services/staking_service.dart';
import '../services/tx_service.dart';
import '../services/wallet_store.dart';
import '../services/wattx_wallet.dart';

enum WalletStatus { disconnected, connecting, connected, error }

/// Self-custody wallet state. Keys live on-device (see [WalletStore]); chain
/// data and broadcasts go through public indexer nodes (see [NodeService]).
/// The remote-RPC model this replaced is gone — no node holds the user's keys.
class WalletProvider extends ChangeNotifier {
  final NodeService _node = NodeService();
  static const WattxNet net = WattxNet.mainnet;

  WattxWallet? _wallet;
  bool needsOnboarding = false;

  WalletStatus status = WalletStatus.disconnected;
  String errorMessage = '';

  // Chain
  int blockHeight = 0;
  String chainName = 'wattx';
  double difficulty = 0;
  bool initialBlockDownload = false;

  // Wallet
  int _spendableSats = 0;
  int _maturingSats = 0;
  // "balance" is the SPENDABLE balance — the only amount a send can use. Immature
  // mining/coinbase payouts are reported separately as [maturingBalance] so the
  // headline number never overstates what the user can actually spend.
  double get balance => _spendableSats / 1e8;
  double get maturingBalance => _maturingSats / 1e8;
  bool get hasMaturing => _maturingSats > 0;
  double unconfirmedBalance = 0;
  List<Utxo> _utxos = [];
  List<Map<String, dynamic>> transactions = [];

  // Staking (Qtum offline-staking delegation to a superstaker)
  bool stakingEnabled = true;
  bool walletUnlocked = true; // self-custody: no separate node unlock
  double expectedReward = 0;
  double networkWeight = 0;
  double walletWeight = 0;
  Map<String, dynamic> validatorInfo = {};
  List<Map<String, dynamic>> validators = [];
  List<Map<String, dynamic>> delegations = [];

  int connectionCount = 0;

  NodeService get node => _node;
  WattxWallet? get wallet => _wallet;
  String get receiveAddress => _wallet?.legacyAddress ?? '';
  List<String> get addresses =>
      _wallet == null ? const [] : [_wallet!.legacyAddress];

  Future<void> init() async {
    if (!await WalletStore.hasWallet()) {
      needsOnboarding = true;
      notifyListeners();
      return;
    }
    _wallet = await WalletStore.load(net: net);
    needsOnboarding = false;
    await connect();
  }

  /// Called by onboarding once a wallet is created/imported.
  Future<void> onWalletReady(WattxWallet w) async {
    _wallet = w;
    needsOnboarding = false;
    notifyListeners();
    await connect();
  }

  Future<bool> connect() async {
    status = WalletStatus.connecting;
    notifyListeners();
    try {
      blockHeight = await _node.getHeight();
      connectionCount = 1;
      status = WalletStatus.connected;
      errorMessage = '';
      notifyListeners();
      await refresh();
      return true;
    } catch (e) {
      status = WalletStatus.error;
      errorMessage = 'Cannot reach WATTx nodes (${_node.activeEndpoint})';
      connectionCount = 0;
      notifyListeners();
      return false;
    }
  }

  Future<void> refresh() async {
    if (_wallet == null) return;
    try {
      blockHeight = await _node.getHeight();
      final addr = _wallet!.legacyAddress;
      _utxos = await _node.getUtxos(addr);
      _spendableSats =
          _utxos.where((u) => u.spendable).fold(0, (s, u) => s + u.value);
      _maturingSats =
          _utxos.where((u) => !u.spendable).fold(0, (s, u) => s + u.value);
      walletWeight = _spendableSats / 1e8;
      status = WalletStatus.connected;
      connectionCount = 1;
    } catch (e) {
      status = WalletStatus.error;
      errorMessage = 'Refresh failed: $e';
    }
    notifyListeners();
  }

  /// Self-custody has one HD receive address; kept as a method so existing UI
  /// that calls it still works.
  Future<String> getNewAddress() async => receiveAddress;

  /// Build, sign, and broadcast a send. Returns the txid, or null on failure
  /// (with [errorMessage] set).
  Future<String?> sendCoins(String toAddress, double amount, String note) async {
    if (_wallet == null) return null;
    try {
      final utxos = await _node.getUtxos(_wallet!.legacyAddress);
      final built = TxService.buildSend(
        wallet: _wallet!,
        toAddress: toAddress.trim(),
        amountSats: (amount * 1e8).round(),
        utxos: utxos,
      );
      final txid = await _node.broadcast(built.hex);
      await refresh();
      return txid;
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Delegate this wallet's staking to [stakerAddress] for [feePercent], via the
  /// on-chain 0x0086 offline-staking contract. Returns the txid or null.
  Future<String?> delegateToStaker(String stakerAddress, int feePercent) async {
    if (_wallet == null) return null;
    try {
      final utxos = await _node.getUtxos(_wallet!.legacyAddress);
      final hex = StakingService.buildAddDelegation(
        wallet: _wallet!,
        stakerAddress: stakerAddress.trim(),
        feePercent: feePercent,
        utxos: utxos,
      );
      final txid = await _node.broadcast(hex);
      await refresh();
      return txid;
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  // Self-custody: no node-side unlock. Kept as no-ops for existing UI.
  Future<bool> unlockWallet(String passphrase, {bool stakingOnly = false}) async {
    walletUnlocked = true;
    notifyListeners();
    return true;
  }

  Future<void> lockWallet() async {}
}
