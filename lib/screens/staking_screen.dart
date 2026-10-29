import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/wallet_provider.dart';
import '../services/staking_service.dart';

/// Offline-staking delegation: hand your coins' staking rights to a superstaker
/// (a pool) while your keys stay on the device. Backed by the on-chain 0x…0086
/// contract — the real, consensus-enforced path.
class StakingScreen extends StatefulWidget {
  const StakingScreen({super.key});
  @override
  State<StakingScreen> createState() => _StakingScreenState();
}

class _StakingScreenState extends State<StakingScreen> {
  final _stakerCtrl = TextEditingController();
  final _feeCtrl = TextEditingController(text: '10');
  String? _message;
  bool _busy = false;

  @override
  void dispose() {
    _stakerCtrl.dispose();
    _feeCtrl.dispose();
    super.dispose();
  }

  /// Up-front gas budget for an addDelegation call. Most of it comes back as a
  /// refund in a later coinstake, but it leaves the wallet now — so say so
  /// before signing rather than letting the balance appear to just drop.
  static double get _gasBudgetWtx =>
      StakingService.addDelegationGasLimit *
      StakingService.defaultGasPrice /
      1e8;

  Future<void> _delegate() async {
    final staker = _stakerCtrl.text.trim();
    final fee = int.tryParse(_feeCtrl.text.trim()) ?? -1;
    if (staker.isEmpty || fee < 0 || fee > 100) {
      setState(() => _message = 'Enter a staker address and a fee 0–100%.');
      return;
    }

    // Delegating to yourself is always a mistake unless you run a superstaking
    // node: nobody stakes the coins, nothing is earned, and every attempt still
    // burns the gas budget below.
    final own = context.read<WalletProvider>().receiveAddress;
    if (staker == own) {
      setState(() => _message =
          'That is this wallet\'s own address. Enter the superstaker\'s '
          'address — delegating to yourself earns nothing unless you run a '
          'superstaking node.');
      return;
    }
    try {
      StakingService.stakerHash160(staker);
    } catch (_) {
      setState(() =>
          _message = 'That is not a valid WATTx address. It should start with W.');
      return;
    }
    final balance = context.read<WalletProvider>().balance;
    if (balance < _gasBudgetWtx) {
      setState(() => _message =
          'Not enough spendable balance: delegating needs up to '
          '${_gasBudgetWtx.toStringAsFixed(2)} WTX of gas up front '
          '(you have ${balance.toStringAsFixed(4)} WTX).');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Confirm delegation',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Delegate staking to\n$staker\nfor a $fee% fee.\n\n'
          'This sends a contract call that reserves up to '
          '${_gasBudgetWtx.toStringAsFixed(2)} WTX as a gas budget. Your '
          'balance drops by that much straight away; the unused part is '
          'refunded automatically in a later block, so the real cost is '
          'normally a fraction of a WTX.\n\n'
          'Your coins never leave this wallet.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Delegate')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final txid =
          await context.read<WalletProvider>().delegateToStaker(staker, fee);
      setState(() => _message = txid != null
          ? 'Delegated. Transaction $txid'
          : context.read<WalletProvider>().errorMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stake'),
        backgroundColor: const Color(0xFF161B22),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            color: const Color(0xFF161B22),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Delegated balance',
                      style: TextStyle(color: Colors.white54)),
                  const SizedBox(height: 6),
                  Text('${wallet.balance.toStringAsFixed(4)} WTX',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text(
                      'Delegate your staking to a superstaker. Your coins never '
                      'leave your wallet — only the staking right is delegated, '
                      'and rewards are paid to you on-chain.',
                      style: TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Superstaker address',
              style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 6),
          TextField(
            controller: _stakerCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'W… staker/pool address',
              hintStyle: TextStyle(color: Colors.white38),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Staker fee (%)', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 6),
          TextField(
            controller: _feeCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: '10',
              hintStyle: TextStyle(color: Colors.white38),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF3FB950),
                padding: const EdgeInsets.symmetric(vertical: 16)),
            onPressed: _busy ? null : _delegate,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Delegate staking'),
          ),
          if (_message != null) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8)),
              child: Text(_message!,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ),
          ],
        ],
      ),
    );
  }
}
