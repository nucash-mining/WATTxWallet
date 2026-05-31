import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/wallet_provider.dart';

class TxList extends StatelessWidget {
  const TxList({super.key});

  @override
  Widget build(BuildContext context) {
    final txs = context.watch<WalletProvider>().transactions;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Recent Transactions', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
      const SizedBox(height: 10),
      if (txs.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: Text('No transactions yet', style: TextStyle(color: Colors.white38))),
        )
      else
        ...txs.take(20).map((tx) => _TxTile(tx: tx)),
    ]);
  }
}

class _TxTile extends StatelessWidget {
  final Map<String, dynamic> tx;
  const _TxTile({required this.tx});

  @override
  Widget build(BuildContext context) {
    final cat = tx['category'] as String? ?? 'unknown';
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
    final confirmations = (tx['confirmations'] as num?)?.toInt() ?? 0;
    final txid = tx['txid'] as String? ?? '';
    final time = tx['blocktime'] != null
        ? DateTime.fromMillisecondsSinceEpoch((tx['blocktime'] as int) * 1000)
        : null;

    final isIn = cat == 'receive' || cat == 'generate' || cat == 'immature';
    final color = isIn ? const Color(0xFF3FB950) : const Color(0xFFFF7B7B);
    final icon = isIn ? Icons.arrow_downward : Icons.arrow_upward;
    final label = cat == 'generate' ? 'Mining Reward'
        : cat == 'immature' ? 'Staking (maturing)'
        : isIn ? 'Received' : 'Sent';

    return Container(
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
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 2),
          Row(children: [
            Text(
              txid.length >= 16 ? '${txid.substring(0, 8)}…${txid.substring(txid.length - 6)}' : txid,
              style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
            ),
            const SizedBox(width: 8),
            if (confirmations < 6)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('$confirmations conf', style: const TextStyle(color: Colors.orange, fontSize: 9)),
              ),
          ]),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            '${isIn ? '+' : '-'}${amount.abs().toStringAsFixed(4)}',
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          if (time != null)
            Text(
              '${time.month}/${time.day} ${time.hour}:${time.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(color: Colors.white24, fontSize: 10),
            ),
        ]),
      ]),
    );
  }
}
