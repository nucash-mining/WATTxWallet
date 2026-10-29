import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Talks to the WATTxchange swap router (the same aggregator WATTxchange.app
/// uses). Non-custodial: the router only quotes and hands back where to send —
/// a THORChain vault, or a per-swap deposit address on the WATTxchange desk.
/// It never holds the user's funds.
class SwapService {
  static const base = 'https://bridge.wattxchange.app/router';

  /// Coins the router can route today. Pairs that have no route simply return
  /// no quote, which the screen shows as such.
  static const coins = ['WTX', 'WATT', 'BTC', 'ETH', 'LTC', 'DOGE', 'BCH', 'AVAX', 'ATOM', 'USDC', 'USDT'];

  /// Which chain a WATT payout lands on. Polygon, because Altcoinchain payouts
  /// are on hold while that chain is being repaired.
  static const wattChain = 'polygon';

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final res = await http
        .post(Uri.parse('$base$path'),
            headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
        .timeout(const Duration(seconds: 45));
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) throw Exception(j['error'] ?? 'HTTP ${res.statusCode}');
    return j;
  }

  Future<SwapQuote?> quote(String from, String to, double amount) async {
    final j = await _post('/quote', {'from': from, 'to': to, 'amount': amount});
    final best = j['best'] as Map<String, dynamic>?;
    if (best == null) {
      final errs = (j['errors'] as List?) ?? const [];
      throw Exception(errs.isNotEmpty
          ? (errs.first as Map)['error'].toString()
          : (j['note'] ?? 'No route for $from → $to yet'));
    }
    return SwapQuote.fromJson(best);
  }

  Future<SwapOrder> create(String from, String to, double amount, String destination) async {
    final j = await _post('/swap', {
      'from': from,
      'to': to,
      'amount': amount,
      'destination': destination,
      if (to == 'WATT' || from == 'WATT') 'chain': wattChain,
    });
    final order = SwapOrder.fromJson(j['swap'] as Map<String, dynamic>);
    await _remember(order.id);
    return order;
  }

  Future<SwapOrder> status(String id) async {
    final res = await http.get(Uri.parse('$base/swap/$id')).timeout(const Duration(seconds: 30));
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) throw Exception(j['error'] ?? 'HTTP ${res.statusCode}');
    return SwapOrder.fromJson(j['swap'] as Map<String, dynamic>);
  }

  /// Tell the router which transaction paid for the swap (THORChain tracks by it).
  Future<void> markSent(String id, String txid) =>
      _post('/swap/$id/sent', {'txid': txid}).then((_) {});

  // Swaps started on this phone, newest first, so the screen can show their
  // progress after the app is closed and reopened.
  static const _key = 'swap_ids';
  Future<void> _remember(String id) async {
    final p = await SharedPreferences.getInstance();
    final ids = p.getStringList(_key) ?? [];
    await p.setStringList(_key, [id, ...ids.where((x) => x != id)].take(30).toList());
  }

  Future<List<String>> recentIds() async =>
      (await SharedPreferences.getInstance()).getStringList(_key) ?? [];
}

double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

class SwapQuote {
  final String provider, from, to, custody;
  final double inAmount, outAmount, providerFeeOut, platformFeeOut;
  final int platformFeeBps;
  final String platformFeeStatus;
  final int? etaSeconds;

  SwapQuote(this.provider, this.from, this.to, this.custody, this.inAmount, this.outAmount,
      this.providerFeeOut, this.platformFeeOut, this.platformFeeBps, this.platformFeeStatus,
      this.etaSeconds);

  factory SwapQuote.fromJson(Map<String, dynamic> j) {
    final pf = (j['platformFee'] as Map?) ?? const {};
    final pfOut = _num(pf['amountOut']);
    final feeOut = _num(j['feeOut']);
    // Providers report their total fee; the desk's total IS WATTxchange's fee,
    // and THORChain's total includes the affiliate share. Show them apart.
    final providerOnly = (feeOut - pfOut).clamp(0, double.infinity).toDouble();
    return SwapQuote(
      j['provider'] as String,
      j['from'] as String,
      j['to'] as String,
      (j['custody'] as String?) ?? '',
      _num(j['inAmount']),
      _num(j['outAmount']),
      providerOnly,
      pfOut,
      (pf['bps'] as num?)?.toInt() ?? 0,
      (pf['status'] as String?) ?? '',
      (j['etaSeconds'] as num?)?.toInt(),
    );
  }

  double get rate => inAmount > 0 ? outAmount / inAmount : 0;
  bool get feeCollected => platformFeeStatus == 'collected';

  String get providerName => switch (provider) {
        'wattx-desk' => 'WATTxchange desk',
        'thorchain' => 'THORChain',
        'gleecdex' => 'GleecDEX',
        'uniswap' => 'Uniswap',
        'sideshift' => 'SideShift',
        'changenow' => 'ChangeNOW',
        _ => provider,
      };
}

class SwapOrder {
  final String id, provider, from, to, destination, state;
  final double amount, expectedOut;
  final String? depositAddress, memo, payoutTx;
  final DateTime? createdAt;

  SwapOrder(this.id, this.provider, this.from, this.to, this.destination, this.state,
      this.amount, this.expectedOut, this.depositAddress, this.memo, this.payoutTx, this.createdAt);

  factory SwapOrder.fromJson(Map<String, dynamic> j) {
    final live = (j['live'] as Map?) ?? const {};
    return SwapOrder(
      j['id'] as String,
      j['provider'] as String? ?? '',
      j['from'] as String? ?? '',
      j['to'] as String? ?? '',
      j['destination'] as String? ?? '',
      j['state'] as String? ?? 'unknown',
      _num(j['amount']),
      _num(j['expectedOut']),
      j['depositAddress'] as String?,
      j['memo'] as String?,
      (live['payoutTx'] ?? j['payoutTx']) as String?,
      DateTime.tryParse(j['createdAt'] as String? ?? ''),
    );
  }

  bool get done => const {'completed', 'refunded', 'expired', 'failed'}.contains(state);

  String get stateLabel => switch (state) {
        'awaiting_deposit' || 'created' => 'Waiting for your deposit',
        'received' => 'Deposit received — paying out',
        'paying' || 'in_progress' || 'locked' || 'claiming' => 'Swapping…',
        'completed' => 'Completed',
        'needs_review' => 'Being reviewed by WATTxchange',
        'expired' => 'Expired',
        'refunded' => 'Refunded',
        _ => state,
      };
}
