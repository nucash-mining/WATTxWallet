import 'dart:convert';

import 'package:http/http.dart' as http;

import 'local_node.dart';

/// A UTXO as returned by the WATTx indexer (ord-api / wattx-utxo-api).
class Utxo {
  final String txid;
  final int vout;
  final int value; // satoshis
  final int height;
  final String scriptPubKey; // hex
  final bool coinbase;
  final int confirmations;

  Utxo(this.txid, this.vout, this.value, this.height, this.scriptPubKey,
      {this.coinbase = false, this.confirmations = 0});

  factory Utxo.fromJson(Map<String, dynamic> j) => Utxo(
        j['txid'] as String,
        (j['vout'] as num).toInt(),
        (j['value'] as num).toInt(),
        (j['height'] as num?)?.toInt() ?? 0,
        j['scriptPubKey'] as String,
        coinbase: j['coinbase'] as bool? ?? false,
        confirmations: (j['confirmations'] as num?)?.toInt() ?? 0,
      );

  /// WATTx coinbase maturity (mainnet, above the V2 height). A coinbase/pool
  /// payout can only be spent once it has this many confirmations; the daemon
  /// rejects a premature coinbase spend outright.
  static const int coinbaseMaturity = 100;

  /// True when this output can be spent right now. Non-coinbase outputs are
  /// always spendable; coinbase (mining) outputs only after maturity.
  bool get spendable => !coinbase || confirmations >= coinbaseMaturity;
}

/// Read-only chain access + broadcast for the self-custody wallet. The wallet
/// holds the keys; these public indexer endpoints ("seednodes") only serve
/// balances/UTXOs and relay signed transactions — they never see a private key.
///
/// The list is tried in order and rotated on failure, so one node being down
/// does not take the wallet offline. New endpoints can be appended over time.
class NodeService {
  /// Hardcoded default endpoints so a fresh install connects with no setup.
  static const List<String> defaultEndpoints = [
    'https://ord-api.wattxchange.app',
  ];

  final List<String> endpoints;
  int _current = 0;

  NodeService({List<String>? endpoints})
      : endpoints = (endpoints == null || endpoints.isEmpty)
            ? List.of(defaultEndpoints)
            : List.of(endpoints);

  String get activeEndpoint => endpoints[_current % endpoints.length];

  /// Try each endpoint once, starting at the current one, rotating past any that
  /// fail. Throws only when every endpoint fails.
  Future<T> _withFailover<T>(Future<T> Function(String base) fn) async {
    Object? lastError;
    for (var i = 0; i < endpoints.length; i++) {
      final base = endpoints[(_current + i) % endpoints.length];
      try {
        final result = await fn(base);
        _current = (_current + i) % endpoints.length; // stick to the one that worked
        return result;
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('All WATTx nodes unreachable: $lastError');
  }

  Future<Map<String, dynamic>> _getJson(String url) async {
    final res = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Chain height + reachability of the active node.
  Future<int> getHeight() => _withFailover((base) async {
        final j = await _getJson('$base/health');
        return (j['height'] as num).toInt();
      });


  bool? _localReadyCache;
  DateTime _localReadyAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// True only once the on-device node has finished syncing.
  ///
  /// A node that is still downloading the chain has not seen the blocks that
  /// paid this wallet, so scantxoutset on it answers with no coins and the
  /// balance reads 0. Running is not enough: the node must be out of initial
  /// block download and level with the network, otherwise every query keeps
  /// going to the remote endpoints.
  Future<bool> _localReady() async {
    if (_localReadyCache != null &&
        DateTime.now().difference(_localReadyAt) < const Duration(seconds: 30)) {
      return _localReadyCache!;
    }
    var ready = false;
    try {
      if (await LocalNode.isRunning()) {
        final info = await LocalNode.rpcInfo();
        if (info != null) {
          final res = await http
              .post(
                Uri.parse(info.url),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Basic ' +
                      base64Encode(utf8.encode('${info.user}:${info.password}')),
                },
                body: jsonEncode({
                  'jsonrpc': '1.0',
                  'id': 'sync',
                  'method': 'getblockchaininfo',
                  'params': [],
                }),
              )
              .timeout(const Duration(seconds: 10));
          final r = res.statusCode == 200
              ? (jsonDecode(res.body) as Map<String, dynamic>)['result']
                  as Map<String, dynamic>?
              : null;
          if (r != null && r['initialblockdownload'] != true) {
            final blocks = (r['blocks'] as num?)?.toInt() ?? 0;
            final headers = (r['headers'] as num?)?.toInt() ?? 0;
            int? network;
            try {
              network = await getHeight();
            } catch (_) {}
            ready = network != null
                ? blocks >= network - 3
                : blocks > 0 && blocks >= headers;
          }
        }
      }
    } catch (_) {
      ready = false;
    }
    _localReadyCache = ready;
    _localReadyAt = DateTime.now();
    return ready;
  }

  /// Ask the on-device node directly, when one is running and synced.
  ///
  /// This is what makes full-node mode mean something: the phone answers its
  /// own questions from a chain it validated, instead of trusting a public
  /// indexer. Returns null when no local node is up, so every caller falls
  /// back to the remote endpoints unchanged.
  ///
  /// scantxoutset walks the UTXO set for a descriptor. It is used rather than
  /// getaddressbalance/getaddressutxos because this daemon does not implement
  /// addressindex -- it logs "Ignoring unknown configuration value
  /// addressindex" and then answers every address query with "No information
  /// available", which looks exactly like an empty wallet.
  Future<List<Utxo>?> _localUtxos(String address) async {
    if (!await _localReady()) return null;
    final info = await LocalNode.rpcInfo();
    if (info == null) return null;
    try {
      final res = await http
          .post(
            Uri.parse(info.url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Basic ' +
                  base64Encode(utf8.encode('${info.user}:${info.password}')),
            },
            body: jsonEncode({
              'jsonrpc': '1.0',
              'id': 'scan',
              'method': 'scantxoutset',
              'params': ['start', ['addr($address)']],
            }),
          )
          // A full scan of the UTXO set is not instant on a handset.
          .timeout(const Duration(seconds: 90));
      if (res.statusCode != 200) return null;
      final r = (jsonDecode(res.body) as Map<String, dynamic>)['result'];
      if (r == null) return null;
      final unspents = (r['unspents'] as List?) ?? const [];
      return unspents.map((u) {
        final m = u as Map<String, dynamic>;
        return Utxo(
          m['txid'] as String,
          (m['vout'] as num).toInt(),
          ((m['amount'] as num) * 1e8).round(),
          (m['height'] as num?)?.toInt() ?? 0,
          m['scriptPubKey'] as String,
          // Coinbase outputs are unspendable until mature; selecting one gets
          // the transaction rejected as a premature coinbase spend.
          coinbase: m['coinbase'] as bool? ?? false,
          confirmations: (m['confirmations'] as num?)?.toInt() ?? 0,
        );
      }).toList();
    } catch (_) {
      // Any local failure falls through to the remote indexer rather than
      // showing the user an error or a wrong zero balance.
      return null;
    }
  }

  /// Confirmed balance in satoshis.
  Future<int> getBalanceSats(String address) async {
    final local = await _localUtxos(address);
    if (local != null) {
      return local.fold<int>(0, (t, u) => t + u.value);
    }
    return _withFailover((base) async {
      final j = await _getJson('$base/address/$address/balance');
      return (j['confirmed'] as num).toInt();
    });
  }

  Future<List<Utxo>> getUtxos(String address) async {
    final local = await _localUtxos(address);
    if (local != null) return local;
    return _withFailover((base) async {
        final res = await http
            .get(Uri.parse('$base/address/$address/utxo'))
            .timeout(const Duration(seconds: 20));
        if (res.statusCode != 200) {
          throw Exception('HTTP ${res.statusCode}: ${res.body}');
        }
      final list = jsonDecode(res.body) as List;
      return list
          .map((e) => Utxo.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  /// Broadcast a signed transaction hex; returns the txid.
  Future<String> broadcast(String txHex) => _withFailover((base) async {
        final res = await http
            .post(
              Uri.parse('$base/tx'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'hex': txHex}),
            )
            .timeout(const Duration(seconds: 25));
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        if (res.statusCode != 200) {
          throw Exception(body['error'] ?? 'broadcast failed (${res.statusCode})');
        }
        return body['txid'] as String;
      });

  /// One page of this address's transaction history, newest first.
  ///
  /// Pass the previous page's [HistoryPage.next] as [before] to continue.
  /// History comes from the indexer even in full-node mode: the on-device node
  /// keeps no address index, so it cannot answer "which transactions touched
  /// this address" without rescanning the whole chain.
  Future<HistoryPage> getHistory(String address,
          {String? before, int limit = 25}) =>
      _withFailover((base) async {
        final q = 'limit=$limit${before == null ? '' : '&before=$before'}';
        final j = await _getJson('$base/address/$address/txs?$q');
        return HistoryPage(
          ((j['items'] as List?) ?? const [])
              .map((e) => TxRecord.fromJson(e as Map<String, dynamic>))
              .toList(),
          j['next'] as String?,
        );
      });
}

/// A transaction as it affected this wallet's address.
class TxRecord {
  final String txid;
  final int height;
  final DateTime? time;

  /// Net change to this address in satoshis: positive for money in, negative
  /// for money out (a send shows the amount plus its fee).
  final int delta;

  /// coinbase (mining reward), coinstake (staking reward) or normal.
  final String kind;
  final int confirmations;

  TxRecord(this.txid, this.height, this.time, this.delta, this.kind,
      this.confirmations);

  factory TxRecord.fromJson(Map<String, dynamic> j) => TxRecord(
        j['txid'] as String,
        (j['height'] as num).toInt(),
        j['time'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (j['time'] as num).toInt() * 1000),
        (j['delta'] as num).toInt(),
        j['kind'] as String? ?? 'normal',
        (j['confirmations'] as num?)?.toInt() ?? 0,
      );

  bool get incoming => delta >= 0;
  bool get isReward => kind == 'coinbase' || kind == 'coinstake';

  /// Mining and staking rewards cannot be spent until they mature.
  bool get maturing => isReward && confirmations < Utxo.coinbaseMaturity;

  String get label => kind == 'coinstake'
      ? 'Staked'
      : kind == 'coinbase'
          ? 'Mining reward'
          : incoming
              ? 'Received'
              : 'Sent';
}

class HistoryPage {
  final List<TxRecord> items;

  /// Cursor for the next (older) page, or null when this is the last page.
  final String? next;
  HistoryPage(this.items, this.next);
}
