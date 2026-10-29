import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/wallet_provider.dart';
import '../services/node_service.dart';

/// Block explorer; it routes by hash (#/tx/<id>), so plain /tx/<id> is a 404.
const _explorer = 'https://wtx-exp.wattxchange.app/#/tx/';

/// The newest transactions on the dashboard, with a link to the full history.
class TxList extends StatelessWidget {
  const TxList({super.key});

  static const _shown = 10;

  @override
  Widget build(BuildContext context) {
    final txs = context.watch<WalletProvider>().history;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(
          child: Text('Recent Transactions',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
        ),
        if (txs.length > _shown)
          TextButton(
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const HistoryScreen())),
            child: const Text('See all', style: TextStyle(color: Color(0xFFF7C948))),
          ),
      ]),
      const SizedBox(height: 10),
      if (txs.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: Text('No transactions yet', style: TextStyle(color: Colors.white38))),
        )
      else
        ...txs.take(_shown).map((tx) => TxTile(tx: tx)),
    ]);
  }
}

/// Every transaction for the wallet's address, loading older pages on scroll.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    final txs = wallet.history;
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        foregroundColor: Colors.white,
        title: const Text('Transaction history'),
      ),
      body: RefreshIndicator(
        color: const Color(0xFFF7C948),
        onRefresh: wallet.refresh,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.extentAfter < 600) wallet.loadMoreHistory();
            return false;
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: txs.length + 1,
            itemBuilder: (context, i) {
              if (i < txs.length) return TxTile(tx: txs[i]);
              if (wallet.historyHasMore) {
                // A short first page never scrolls, so ask for the next one here.
                WidgetsBinding.instance.addPostFrameCallback((_) => wallet.loadMoreHistory());
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator(color: Color(0xFFF7C948))),
                );
              }
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Text(txs.isEmpty ? 'No transactions yet' : 'End of history',
                      style: const TextStyle(color: Colors.white38)),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class TxTile extends StatelessWidget {
  final TxRecord tx;
  const TxTile({super.key, required this.tx});

  @override
  Widget build(BuildContext context) {
    final color = tx.incoming ? const Color(0xFF3FB950) : const Color(0xFFFF7B7B);
    final icon = tx.kind == 'coinstake'
        ? Icons.bolt
        : tx.kind == 'coinbase'
            ? Icons.memory
            : tx.incoming
                ? Icons.arrow_downward
                : Icons.arrow_upward;
    final badge = tx.maturing
        ? 'maturing ${tx.confirmations}/${Utxo.coinbaseMaturity}'
        : tx.confirmations < 6
            ? '${tx.confirmations} conf'
            : null;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _showDetails(context, tx),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tx.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 2),
            Row(children: [
              Text(
                '${tx.txid.substring(0, 8)}…${tx.txid.substring(tx.txid.length - 6)}',
                style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
              ),
              if (badge != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(badge, style: const TextStyle(color: Colors.orange, fontSize: 9)),
                ),
              ],
            ]),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              '${tx.incoming ? '+' : '-'}${_coins(tx.delta.abs())}',
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            if (tx.time != null)
              Text(_shortDate(tx.time!), style: const TextStyle(color: Colors.white24, fontSize: 10)),
          ]),
        ]),
      ),
    );
  }
}

void _showDetails(BuildContext context, TxRecord tx) {
  final link = '$_explorer${tx.txid}';
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF161B22),
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tx.label, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('${tx.incoming ? '+' : '-'}${_coins(tx.delta.abs())} WTX',
            style: TextStyle(
                color: tx.incoming ? const Color(0xFF3FB950) : const Color(0xFFFF7B7B),
                fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _row('Date', tx.time == null ? '—' : _longDate(tx.time!)),
        _row('Block', '${tx.height}'),
        _row('Confirmations', tx.maturing
            ? '${tx.confirmations} (spendable at ${Utxo.coinbaseMaturity})'
            : '${tx.confirmations}'),
        if (!tx.incoming)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Sent amounts include the network fee.',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
          ),
        const SizedBox(height: 8),
        const Text('Transaction ID', style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 4),
        SelectableText(tx.txid,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace')),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy ID'),
            onPressed: () => _copy(context, tx.txid, 'Transaction ID copied'),
          )),
          const SizedBox(width: 12),
          Expanded(child: OutlinedButton.icon(
            icon: const Icon(Icons.link, size: 16),
            label: const Text('Explorer link'),
            onPressed: () => _copy(context, link, 'Explorer link copied'),
          )),
        ]),
      ]),
    ),
  );
}

Widget _row(String k, String v) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        SizedBox(width: 120, child: Text(k, style: const TextStyle(color: Colors.white54, fontSize: 13))),
        Expanded(child: Text(v, style: const TextStyle(color: Colors.white, fontSize: 13))),
      ]),
    );

void _copy(BuildContext context, String text, String message) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Satoshis to a coin amount without float rounding: trailing zeros trimmed,
/// but always at least two decimals.
String _coins(int sats) {
  final whole = sats ~/ 100000000;
  var frac = (sats % 100000000).toString().padLeft(8, '0').replaceFirst(RegExp(r'0+$'), '');
  if (frac.length < 2) frac = frac.padRight(2, '0');
  return '$whole.$frac';
}

String _two(int n) => n.toString().padLeft(2, '0');
String _shortDate(DateTime t) => '${t.month}/${t.day} ${t.hour}:${_two(t.minute)}';
String _longDate(DateTime t) =>
    '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}';
