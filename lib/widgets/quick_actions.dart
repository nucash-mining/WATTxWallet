import 'package:flutter/material.dart';

class QuickActions extends StatelessWidget {
  const QuickActions({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _action(context, Icons.send, 'Send', '/send', const Color(0xFFF7C948)),
      _action(context, Icons.qr_code, 'Receive', '/receive', const Color(0xFF3FB950)),
      _action(context, Icons.stacked_bar_chart, 'Stake', '/staking', const Color(0xFF58A6FF)),
      // Swap replaces Mine: phone mining was removed (see main.dart), so the
      // old '/mining' route no longer existed and the button did nothing.
      _action(context, Icons.swap_horiz, 'Swap', '/swap', const Color(0xFFFF7B54)),
    ]);
  }

  Widget _action(BuildContext context, IconData icon, String label, String route, Color color) =>
      Expanded(child: GestureDetector(
        onTap: () => Navigator.pushNamed(context, route),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
        ),
      ));
}
