import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/wallet_provider.dart';

class StakingScreen extends StatefulWidget {
  const StakingScreen({super.key});
  @override
  State<StakingScreen> createState() => _StakingScreenState();
}

class _StakingScreenState extends State<StakingScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _passCtrl = TextEditingController();
  bool _unlocking = false;
  String? _statusMsg;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _unlockForStaking() async {
    if (_passCtrl.text.isEmpty) return;
    setState(() { _unlocking = true; _statusMsg = null; });
    final ok = await context.read<WalletProvider>().unlockWallet(_passCtrl.text, stakingOnly: true);
    setState(() {
      _unlocking = false;
      _statusMsg = ok ? 'Wallet unlocked for staking!' : 'Wrong passphrase';
    });
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Staking', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabs,
          labelColor: const Color(0xFFF7C948),
          unselectedLabelColor: Colors.white38,
          indicatorColor: const Color(0xFFF7C948),
          tabs: const [Tab(text: 'Overview'), Tab(text: 'Validators'), Tab(text: 'Delegations')],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _OverviewTab(wallet: wallet, passCtrl: _passCtrl, unlocking: _unlocking,
              statusMsg: _statusMsg, onUnlock: _unlockForStaking),
          _ValidatorsTab(wallet: wallet),
          _DelegationsTab(wallet: wallet),
        ],
      ),
    );
  }
}

// ── Overview ──────────────────────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  final WalletProvider wallet;
  final TextEditingController passCtrl;
  final bool unlocking;
  final String? statusMsg;
  final VoidCallback onUnlock;
  const _OverviewTab({required this.wallet, required this.passCtrl, required this.unlocking, required this.statusMsg, required this.onUnlock});

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      // Status card
      _Card(child: Column(children: [
        _row('Staking', wallet.stakingEnabled ? '✅ Active' : '❌ Inactive', wallet.stakingEnabled ? const Color(0xFF3FB950) : Colors.red),
        const Divider(color: Colors.white12),
        _row('Wallet Unlocked', wallet.walletUnlocked ? 'Yes' : 'No', wallet.walletUnlocked ? const Color(0xFF3FB950) : Colors.orange),
        _row('Balance', '${wallet.balance.toStringAsFixed(4)} WTX', Colors.white),
        _row('Network Weight', _fmt(wallet.networkWeight), Colors.white54),
        _row('Wallet Weight', _fmt(wallet.walletWeight), Colors.white54),
        if (wallet.expectedReward > 0)
          _row('Expected reward in', _fmtSecs(wallet.expectedReward.toInt()), const Color(0xFFF7C948)),
      ])),
      const SizedBox(height: 16),

      // Trust tier display
      _TrustTierCard(validator: wallet.validatorInfo),
      const SizedBox(height: 16),

      // Unlock widget
      if (!wallet.walletUnlocked) ...[
        const Text('Unlock Wallet for Staking', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: passCtrl,
          obscureText: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Wallet passphrase',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: const Color(0xFF161B22),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF7C948), foregroundColor: Colors.black),
          onPressed: unlocking ? null : onUnlock,
          child: unlocking ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Unlock for Staking'),
        )),
        if (statusMsg != null)
          Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(statusMsg!, style: TextStyle(
              color: statusMsg!.contains('!') ? const Color(0xFF3FB950) : Colors.red,
            ))),
      ] else ...[
        SizedBox(width: double.infinity, child: OutlinedButton(
          style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24), foregroundColor: Colors.white54),
          onPressed: () => context.read<WalletProvider>().lockWallet(),
          child: const Text('Lock Wallet'),
        )),
      ],

      const SizedBox(height: 16),
      _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Register as Validator', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        const Text('Stake any amount on testnet (no minimum). On mainnet, 100,000 WTX is required.',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF238636)),
          onPressed: () => _registerValidator(context),
          child: const Text('Register Validator', style: TextStyle(color: Colors.white)),
        )),
      ])),
    ]);
  }

  Future<void> _registerValidator(BuildContext context) async {
    final rpc = context.read<WalletProvider>().rpc;
    try {
      final txid = await rpc.registerValidator(0.0, 'My Validator');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Registered! Tx: ${txid.substring(0, 16)}…'),
        backgroundColor: const Color(0xFF238636),
      ));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed: $e'),
        backgroundColor: Colors.red.shade800,
      ));
    }
  }

  Widget _row(String k, String v, Color vc) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(k, style: const TextStyle(color: Colors.white54, fontSize: 13)),
      Text(v, style: TextStyle(color: vc, fontSize: 13, fontWeight: FontWeight.w600)),
    ]),
  );

  String _fmt(double v) {
    if (v > 1e9) return '${(v / 1e9).toStringAsFixed(2)}B';
    if (v > 1e6) return '${(v / 1e6).toStringAsFixed(2)}M';
    return v.toStringAsFixed(0);
  }

  String _fmtSecs(int s) {
    if (s < 60) return '${s}s';
    if (s < 3600) return '${s ~/ 60}m ${s % 60}s';
    return '${s ~/ 3600}h ${(s % 3600) ~/ 60}m';
  }
}

// ── Trust Tier ────────────────────────────────────────────────────────────────
class _TrustTierCard extends StatelessWidget {
  final Map<String, dynamic> validator;
  const _TrustTierCard({required this.validator});

  @override
  Widget build(BuildContext context) {
    final tier = validator['trustTier'] as String? ?? 'bronze';
    final uptime = (validator['uptimePercent'] as num?)?.toDouble() ?? 0;

    const tiers = [
      ('bronze', Color(0xFF8B6914), '95%+', '1.0x'),
      ('silver', Color(0xFF9E9E9E), '97%+', '1.25x'),
      ('gold', Color(0xFFF7C948), '99%+', '1.5x'),
      ('platinum', Color(0xFF58A6FF), '99.9%+', '2.0x'),
    ];

    return _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Trust Tier', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      Row(children: tiers.map((t) {
        final active = tier.toLowerCase() == t.$1;
        final c = t.$2;
        return Expanded(child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? c.withAlpha(50) : Colors.white.withAlpha(10),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: active ? c : Colors.white12),
          ),
          child: Column(children: [
            Text(t.$1[0].toUpperCase() + t.$1.substring(1),
                style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.bold)),
            Text(t.$4, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            Text(t.$3, style: const TextStyle(color: Colors.white38, fontSize: 9)),
          ]),
        ));
      }).toList()),
      if (uptime > 0) ...[
        const SizedBox(height: 10),
        Text('Your uptime: ${uptime.toStringAsFixed(1)}%', style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ],
    ]));
  }
}

// ── Validators ────────────────────────────────────────────────────────────────
class _ValidatorsTab extends StatefulWidget {
  final WalletProvider wallet;
  const _ValidatorsTab({required this.wallet});
  @override
  State<_ValidatorsTab> createState() => _ValidatorsTabState();
}
class _ValidatorsTabState extends State<_ValidatorsTab> {
  final _amtCtrl = TextEditingController();

  @override
  void dispose() { _amtCtrl.dispose(); super.dispose(); }

  Future<void> _delegate(String validatorId) async {
    final amt = double.tryParse(_amtCtrl.text);
    if (amt == null || amt <= 0) return;
    try {
      final txid = await widget.wallet.rpc.delegateStake(validatorId, amt);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Delegated! Tx: ${txid.substring(0, 16)}…'),
        backgroundColor: const Color(0xFF238636),
      ));
      widget.wallet.refresh();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade800));
    }
  }

  @override
  Widget build(BuildContext context) {
    final validators = widget.wallet.validators;
    if (validators.isEmpty) {
      return const Center(child: Text('No validators found', style: TextStyle(color: Colors.white38)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: validators.length,
      itemBuilder: (ctx, i) {
        final v = validators[i];
        return _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.account_circle, color: Color(0xFFF7C948)),
            const SizedBox(width: 8),
            Expanded(child: Text(v['name'] as String? ?? 'Validator ${v['id']}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
            Text('Fee: ${((v['fee'] as num?)?.toDouble() ?? 0) * 100}%',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
          const SizedBox(height: 6),
          Text('Stake: ${(v['totalStake'] as num?)?.toStringAsFixed(0) ?? 0} WTX · Tier: ${v['trustTier'] ?? 'bronze'}',
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(
              controller: _amtCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Amount WTX',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
            )),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF238636)),
              onPressed: () => _delegate(v['id'] as String? ?? ''),
              child: const Text('Delegate', style: TextStyle(color: Colors.white)),
            ),
          ]),
        ]));
      },
    );
  }
}

// ── Delegations ───────────────────────────────────────────────────────────────
class _DelegationsTab extends StatelessWidget {
  final WalletProvider wallet;
  const _DelegationsTab({required this.wallet});

  @override
  Widget build(BuildContext context) {
    final delegations = wallet.delegations;
    if (delegations.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(32),
        child: Text('No active delegations.\nDelegate stake to a validator to earn rewards.',
            style: TextStyle(color: Colors.white38), textAlign: TextAlign.center),
      ));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: delegations.length,
      itemBuilder: (ctx, i) {
        final d = delegations[i];
        final pending = (d['pendingRewards'] as num?)?.toDouble() ?? 0;
        return _Card(child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Validator: ${(d['validatorId'] as String? ?? '').substring(0, 8)}…',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            Text('${(d['amount'] as num?)?.toStringAsFixed(0) ?? 0} WTX',
                style: const TextStyle(color: Color(0xFFF7C948), fontWeight: FontWeight.bold)),
          ]),
          if (pending > 0) ...[
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Pending rewards: ${pending.toStringAsFixed(4)} WTX',
                  style: const TextStyle(color: Color(0xFF3FB950), fontSize: 13)),
              TextButton(
                onPressed: () async {
                  await wallet.rpc.claimRewards(d['validatorId'] as String? ?? '');
                  wallet.refresh();
                },
                child: const Text('Claim', style: TextStyle(color: Color(0xFF3FB950))),
              ),
            ]),
          ],
        ]));
      },
    );
  }
}

// ── Shared ────────────────────────────────────────────────────────────────────
class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF161B22),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white12),
    ),
    child: child,
  );
}
