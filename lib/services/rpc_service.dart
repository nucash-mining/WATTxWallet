import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'local_node.dart';

class RpcException implements Exception {
  final int code;
  final String message;
  RpcException(this.code, this.message);
  @override
  String toString() => 'RpcException($code): $message';
}

class RpcService {
  static const String _defaultHost = '76.131.208.215';
  static const int _defaultPort = 13890;
  static const String _defaultUser = 'wattxrpc';

  final _storage = const FlutterSecureStorage();

  String _host = _defaultHost;
  int _port = _defaultPort;
  String _user = _defaultUser;
  String _password = '';
  bool _testnet = true;

  static final RpcService _instance = RpcService._internal();
  factory RpcService() => _instance;
  RpcService._internal();

  Future<void> loadConfig() async {
    _host = await _storage.read(key: 'rpc_host') ?? _defaultHost;
    _port = int.tryParse(await _storage.read(key: 'rpc_port') ?? '') ?? _defaultPort;
    _user = await _storage.read(key: 'rpc_user') ?? _defaultUser;
    _password = await _storage.read(key: 'rpc_password') ?? '';
    _testnet = (await _storage.read(key: 'rpc_testnet') ?? 'true') == 'true';
  }

  Future<void> saveConfig({
    required String host,
    required int port,
    required String user,
    required String password,
    required bool testnet,
  }) async {
    _host = host;
    _port = port;
    _user = user;
    _password = password;
    _testnet = testnet;
    await _storage.write(key: 'rpc_host', value: host);
    await _storage.write(key: 'rpc_port', value: port.toString());
    await _storage.write(key: 'rpc_user', value: user);
    await _storage.write(key: 'rpc_password', value: password);
    await _storage.write(key: 'rpc_testnet', value: testnet.toString());
  }

  String get host => _host;
  int get port => _port;
  bool get isTestnet => _testnet;

  /// When the bundled daemon is running, every call goes to it instead of the
  /// configured remote. Checked per call rather than latched at startup: the
  /// node can be switched on or off, or die, while the app is open, and a
  /// wallet that kept talking to a remote it thinks is local would be lying
  /// about where its data came from.
  Future<({String url, String user, String password})?> _localOverride() async {
    if (!await LocalNode.isRunning()) return null;
    return LocalNode.rpcInfo();
  }

  Future<dynamic> call(String method, [List<dynamic> params = const []]) async {
    final local = await _localOverride();
    final credentials = local != null
        ? base64Encode(utf8.encode('${local.user}:${local.password}'))
        : base64Encode(utf8.encode('$_user:$_password'));
    final uri =
        local != null ? Uri.parse(local.url) : Uri.parse('http://$_host:$_port/');
    final body = jsonEncode({
      'jsonrpc': '1.0',
      'id': method,
      'method': method,
      'params': params,
    });

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Basic $credentials',
      },
      body: body,
    ).timeout(const Duration(seconds: 15));

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['error'] != null) {
      final err = json['error'] as Map<String, dynamic>;
      throw RpcException(err['code'] as int, err['message'] as String);
    }
    return json['result'];
  }

  // ── Blockchain ──────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getBlockchainInfo() async =>
      Map<String, dynamic>.from(await call('getblockchaininfo'));

  Future<int> getBlockCount() async => await call('getblockcount') as int;

  Future<Map<String, dynamic>> getBlock(String hash) async =>
      Map<String, dynamic>.from(await call('getblock', [hash, 2]));

  // ── Wallet ───────────────────────────────────────────────────────────────────
  Future<double> getBalance([int minConf = 1]) async {
    final raw = await call('getbalance', ['*', minConf]);
    return (raw as num).toDouble();
  }

  Future<List<String>> getAddresses() async {
    final result = await call('getaddressesbyaccount', ['']);
    return List<String>.from(result as List);
  }

  Future<String> getNewAddress() async => await call('getnewaddress') as String;

  Future<List<Map<String, dynamic>>> listTransactions([int count = 50]) async {
    final result = await call('listtransactions', ['*', count, 0, true]);
    return List<Map<String, dynamic>>.from(
        (result as List).map((e) => Map<String, dynamic>.from(e as Map)));
  }

  Future<String> sendToAddress(String address, double amount, String comment) async {
    return await call('sendtoaddress', [address, amount, comment]) as String;
  }

  Future<void> walletPassphrase(String passphrase, int timeout, {bool stakingOnly = false}) async {
    await call('walletpassphrase', [passphrase, timeout, stakingOnly]);
  }

  Future<void> walletLock() async => await call('walletlock');

  Future<String> dumpPrivKey(String address) async =>
      await call('dumpprivkey', [address]) as String;

  Future<String> importPrivKey(String privKey, [String label = '']) async =>
      await call('importprivkey', [privKey, label]) as String;

  // ── Staking ──────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getStakingInfo() async =>
      Map<String, dynamic>.from(await call('getstakinginfo'));

  Future<Map<String, dynamic>> getValidatorStats() async {
    try {
      return Map<String, dynamic>.from(await call('getvalidatorstats'));
    } catch (_) {
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> listValidators() async {
    try {
      final r = await call('listvalidators');
      return List<Map<String, dynamic>>.from(
          (r as List).map((e) => Map<String, dynamic>.from(e as Map)));
    } catch (_) {
      return [];
    }
  }

  Future<String> delegateStake(String validatorId, double amount) async =>
      await call('delegatestake', [validatorId, amount]) as String;

  Future<String> registerValidator([double fee = 0.0, String name = '']) async =>
      await call('registervalidator', [fee, name]) as String;

  Future<Map<String, dynamic>> getMyValidator() async {
    try {
      return Map<String, dynamic>.from(await call('getmyvalidator'));
    } catch (_) {
      return {};
    }
  }

  Future<String> claimRewards([String validatorId = '']) async {
    final params = validatorId.isEmpty ? [] : [validatorId];
    return await call('claimrewards', params) as String;
  }

  Future<List<Map<String, dynamic>>> getMyDelegations() async {
    try {
      final r = await call('getmydelegations');
      return List<Map<String, dynamic>>.from(
          (r as List).map((e) => Map<String, dynamic>.from(e as Map)));
    } catch (_) {
      return [];
    }
  }

  // ── Trust Tier ───────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getTrustTierInfo() async {
    try {
      return Map<String, dynamic>.from(await call('gettrusttierinfo'));
    } catch (_) {
      return {};
    }
  }

  // ── Mining ───────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getMiningInfo() async =>
      Map<String, dynamic>.from(await call('getmininginfo'));

  Future<Map<String, dynamic>> getBlockTemplate() async =>
      Map<String, dynamic>.from(await call('getblocktemplate', [
        {'capabilities': ['coinbasetxn', 'workid', 'coinbase/append']}
      ]));

  Future<bool> submitBlock(String hexData) async {
    final result = await call('submitblock', [hexData]);
    return result == null;
  }

  // ── Network ──────────────────────────────────────────────────────────────────
  Future<int> getConnectionCount() async =>
      await call('getconnectioncount') as int;

  Future<List<Map<String, dynamic>>> getPeerInfo() async {
    final r = await call('getpeerinfo');
    return List<Map<String, dynamic>>.from(
        (r as List).map((e) => Map<String, dynamic>.from(e as Map)));
  }

  Future<bool> testConnection() async {
    try {
      await call('getblockcount');
      return true;
    } catch (_) {
      return false;
    }
  }
}
