import 'dart:convert';

import 'package:http/http.dart' as http;

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

  /// Confirmed balance in satoshis.
  Future<int> getBalanceSats(String address) => _withFailover((base) async {
        final j = await _getJson('$base/address/$address/balance');
        return (j['confirmed'] as num).toInt();
      });

  Future<List<Utxo>> getUtxos(String address) => _withFailover((base) async {
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
}
