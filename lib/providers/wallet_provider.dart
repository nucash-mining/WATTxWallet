import 'package:flutter/foundation.dart';
import '../services/rpc_service.dart';

enum WalletStatus { disconnected, connecting, connected, error }

class WalletProvider extends ChangeNotifier {
  final RpcService _rpc = RpcService();

  WalletStatus status = WalletStatus.disconnected;
  String errorMessage = '';

  // Blockchain
  int blockHeight = 0;
  String chainName = 'test';
  double difficulty = 0;
  bool initialBlockDownload = true;

  // Wallet
  double balance = 0;
  double unconfirmedBalance = 0;
  List<String> addresses = [];
  List<Map<String, dynamic>> transactions = [];

  // Staking
  bool stakingEnabled = false;
  bool walletUnlocked = false;
  double expectedReward = 0;
  double networkWeight = 0;
  double walletWeight = 0;
  Map<String, dynamic> validatorInfo = {};
  List<Map<String, dynamic>> validators = [];
  List<Map<String, dynamic>> delegations = [];

  // Network
  int connectionCount = 0;

  RpcService get rpc => _rpc;

  Future<void> init() async {
    await _rpc.loadConfig();
    await connect();
  }

  Future<bool> connect() async {
    status = WalletStatus.connecting;
    notifyListeners();

    final ok = await _rpc.testConnection();
    if (!ok) {
      status = WalletStatus.error;
      errorMessage = 'Cannot reach ${_rpc.host}:${_rpc.port}';
      notifyListeners();
      return false;
    }

    status = WalletStatus.connected;
    errorMessage = '';
    notifyListeners();
    await refresh();
    return true;
  }

  Future<void> refresh() async {
    if (status != WalletStatus.connected) return;
    await Future.wait([
      _refreshChain(),
      _refreshWallet(),
      _refreshStaking(),
      _refreshNetwork(),
    ]);
    notifyListeners();
  }

  Future<void> _refreshChain() async {
    try {
      final info = await _rpc.getBlockchainInfo();
      blockHeight = (info['blocks'] as num).toInt();
      chainName = info['chain'] as String? ?? 'test';
      difficulty = (info['difficulty'] as num?)?.toDouble() ?? 0;
      initialBlockDownload = info['initialblockdownload'] as bool? ?? false;
    } catch (_) {}
  }

  Future<void> _refreshWallet() async {
    try {
      balance = await _rpc.getBalance();
    } catch (_) {}
    try {
      unconfirmedBalance = await _rpc.getBalance(0);
    } catch (_) {}
    try {
      final allAddrs = await _rpc.getAddresses();
      if (allAddrs.isEmpty) {
        final addr = await _rpc.getNewAddress();
        addresses = [addr];
      } else {
        addresses = allAddrs;
      }
    } catch (_) {}
    try {
      transactions = await _rpc.listTransactions(50);
    } catch (_) {}
  }

  Future<void> _refreshStaking() async {
    try {
      final info = await _rpc.getStakingInfo();
      stakingEnabled = info['enabled'] as bool? ?? false;
      walletUnlocked = info['staking'] as bool? ?? false;
      expectedReward = (info['expectedtime'] as num?)?.toDouble() ?? 0;
      networkWeight = (info['netstakeweight'] as num?)?.toDouble() ?? 0;
      walletWeight = (info['weight'] as num?)?.toDouble() ?? 0;
    } catch (_) {}
    try {
      validatorInfo = await _rpc.getMyValidator();
    } catch (_) {}
    try {
      validators = await _rpc.listValidators();
    } catch (_) {}
    try {
      delegations = await _rpc.getMyDelegations();
    } catch (_) {}
  }

  Future<void> _refreshNetwork() async {
    try {
      connectionCount = await _rpc.getConnectionCount();
    } catch (_) {}
  }

  Future<bool> unlockWallet(String passphrase, {bool stakingOnly = true}) async {
    try {
      await _rpc.walletPassphrase(passphrase, 9999999, stakingOnly: stakingOnly);
      walletUnlocked = true;
      notifyListeners();
      return true;
    } catch (e) {
      errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> lockWallet() async {
    try {
      await _rpc.walletLock();
      walletUnlocked = false;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> sendCoins(String address, double amount, String note) async {
    try {
      final txid = await _rpc.sendToAddress(address, amount, note);
      await _refreshWallet();
      notifyListeners();
      return txid;
    } catch (e) {
      return null;
    }
  }

  Future<String?> getNewAddress() async {
    try {
      final addr = await _rpc.getNewAddress();
      addresses = [addr, ...addresses];
      notifyListeners();
      return addr;
    } catch (_) {
      return null;
    }
  }

  String get receiveAddress => addresses.isNotEmpty ? addresses.first : '';
}
