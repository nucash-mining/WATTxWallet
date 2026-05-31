import 'package:flutter/material.dart';

class BalanceCard extends StatelessWidget {
  final double balance;
  final double unconfirmed;
  final bool staking;

  const BalanceCard({super.key, required this.balance, required this.unconfirmed, required this.staking});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1C2128), Color(0xFF0D1117)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF7C948).withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('WATTx Balance', style: TextStyle(color: Colors.white54, fontSize: 13)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: staking ? const Color(0xFF3FB950).withOpacity(0.15) : Colors.orange.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: staking ? const Color(0xFF3FB950).withOpacity(0.4) : Colors.orange.withOpacity(0.4)),
            ),
            child: Text(
              staking ? '⚡ Staking' : 'Not Staking',
              style: TextStyle(color: staking ? const Color(0xFF3FB950) : Colors.orange, fontSize: 11),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          '${balance.toStringAsFixed(4)} WTX',
          style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: -0.5),
        ),
        if (unconfirmed != balance && unconfirmed > 0) ...[
          const SizedBox(height: 4),
          Text('${unconfirmed.toStringAsFixed(4)} WTX unconfirmed',
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ]),
    );
  }
}
