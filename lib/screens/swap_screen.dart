import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/wallet_provider.dart';
import '../services/swap_service.dart';

const _bg = Color(0xFF0D1117);
const _card = Color(0xFF161B22);
const _gold = Color(0xFFF7C948);
const _green = Color(0xFF3FB950);
const _red = Color(0xFFF85149);

/// Cake-Wallet-style swaps through the WATTxchange router: pick what to pay
/// and what to receive, see the best route with every fee spelled out, then
/// either pay straight from this wallet (WTX) or send from another wallet to
/// the deposit address shown.
class SwapScreen extends StatefulWidget {
  const SwapScreen({super.key});
  @override
  State<SwapScreen> createState() => _SwapScreenState();
}

class _SwapScreenState extends State<SwapScreen> {
  final _svc = SwapService();
  final _amount = TextEditingController();
  final _dest = TextEditingController();
  String _from = 'WTX', _to = 'WATT';
  SwapQuote? _quote;
  String? _quoteError;
  bool _quoting = false, _busy = false;
  Timer? _debounce;
  List<String> _recent = [];

  @override
  void initState() {
    super.initState();
    _amount.addListener(_requote);
    _svc.recentIds().then((ids) => mounted ? setState(() => _recent = ids) : null);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _amount.dispose();
    _dest.dispose();
    super.dispose();
  }

  double get _amt => double.tryParse(_amount.text.trim()) ?? 0;

  /// WATT routed through the desk is paid by an HTLC lock on Polygon, which
  /// this WTX-only wallet cannot make; the desk returns no deposit address for
  /// it. Send those users to the web app instead of a dead-end confirm.
  bool get _webOnly => _from == 'WATT' && _quote?.provider == 'wattx-desk';

  void _requote() {
    _debounce?.cancel();
    // The router allows about one quote per second; wait for typing to settle.
    _debounce = Timer(const Duration(milliseconds: 700), _fetchQuote);
  }

  Future<void> _fetchQuote() async {
    if (_amt <= 0 || _from == _to) {
      setState(() { _quote = null; _quoteError = null; });
      return;
    }
    setState(() { _quoting = true; _quoteError = null; });
    try {
      final q = await _svc.quote(_from, _to, _amt);
      if (mounted) setState(() => _quote = q);
    } catch (e) {
      if (mounted) setState(() { _quote = null; _quoteError = _clean(e); });
    } finally {
      if (mounted) setState(() => _quoting = false);
    }
  }

  void _pick(bool isFrom, String c) {
    setState(() {
      if (isFrom) {
        if (c == _to) _to = _from;
        _from = c;
      } else {
        if (c == _from) _from = _to;
        _to = c;
      }
      _dest.clear();
      _quote = null;
    });
    _requote();
  }

  void _flip() {
    setState(() { final t = _from; _from = _to; _to = t; _dest.clear(); _quote = null; });
    _requote();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    // Receiving WTX defaults to this wallet's own address.
    if (_to == 'WTX' && _dest.text.isEmpty) _dest.text = wallet.receiveAddress;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(backgroundColor: _card, foregroundColor: Colors.white, title: const Text('Swap')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _box('You pay', Row(children: [
          Expanded(
            child: TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(border: InputBorder.none, hintText: '0.0',
                  hintStyle: TextStyle(color: Colors.white24)),
            ),
          ),
          _coinPicker(_from, (c) => _pick(true, c)),
        ]), footer: _from == 'WTX'
            ? Row(children: [
                Text('Balance: ${wallet.balance.toStringAsFixed(4)} WTX',
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    // Leave a little for the network fee.
                    final max = (wallet.balance - 0.01).clamp(0, double.infinity);
                    _amount.text = max.toStringAsFixed(8).replaceFirst(RegExp(r'\.?0+$'), '');
                  },
                  child: const Text('MAX', style: TextStyle(color: _gold)),
                ),
              ])
            : const Text('Sent from another wallet', style: TextStyle(color: Colors.white38, fontSize: 12))),
        Center(
          child: IconButton(
            onPressed: _flip,
            icon: const Icon(Icons.swap_vert, color: _gold, size: 30),
          ),
        ),
        _box('You receive (estimated)', Row(children: [
          Expanded(
            child: _quoting
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: LinearProgressIndicator(color: _gold, backgroundColor: Colors.white10))
                : Text(_quote == null ? '—' : _fmt(_quote!.outAmount),
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          ),
          _coinPicker(_to, (c) => _pick(false, c)),
        ])),
        const SizedBox(height: 12),
        if (_quoteError != null)
          Text(_quoteError!, style: const TextStyle(color: Colors.orange, fontSize: 13)),
        if (_quote != null) _quoteDetails(_quote!),
        if (_webOnly) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.withOpacity(0.4)),
            ),
            child: const Text(
              'Paying with WATT locks it in the WATTxchange escrow contract on Polygon, '
              'which needs the Polygon wallet that holds your WATT — this wallet only holds WTX. '
              'Start this swap on WATTxchange.app (DeFi Hub → Bridge); the WTX arrives here '
              'at the price shown above.',
              style: TextStyle(color: Colors.orange, fontSize: 13),
            ),
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _dest,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
          decoration: InputDecoration(
            labelText: _to == 'WTX' ? 'Receive WTX at (this wallet)' : 'Your $_to receive address',
            labelStyle: const TextStyle(color: Colors.white54),
            helperText: _to == 'WATT' ? 'WATT is paid on Polygon — use a Polygon (0x…) address' : null,
            helperStyle: const TextStyle(color: Colors.white38),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.paste, color: Colors.white54),
              onPressed: () async {
                final d = await Clipboard.getData('text/plain');
                if (d?.text != null) setState(() => _dest.text = d!.text!.trim());
              },
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (_webOnly)
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _gold, foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16)),
            icon: const Icon(Icons.link),
            label: const Text('Copy WATTxchange.app link',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: 'https://wattxchange.app/'));
              _snack('Link copied — open it in your browser');
            },
          )
        else
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _gold, foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16)),
            onPressed: (_quote == null || _busy || _dest.text.trim().isEmpty) ? null : () => _review(wallet),
            child: Text(_busy ? 'Working…' : 'Review swap',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        if (_recent.isNotEmpty) ...[
          const SizedBox(height: 28),
          const Text('Your swaps', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ..._recent.take(10).map((id) => _RecentSwap(id: id, svc: _svc)),
        ],
      ]),
    );
  }

  Widget _box(String label, Widget child, {Widget? footer}) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.06))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          child,
          if (footer != null) footer,
        ]),
      );

  Widget _coinPicker(String value, ValueChanged<String> onPick) => DropdownButton<String>(
        value: value,
        dropdownColor: _card,
        underline: const SizedBox.shrink(),
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        items: SwapService.coins.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
        onChanged: (c) => c == null ? null : onPick(c),
      );

  Widget _quoteDetails(SwapQuote q) {
    final eta = q.etaSeconds == null ? '—' : q.etaSeconds! < 120 ? '~${q.etaSeconds}s' : '~${(q.etaSeconds! / 60).round()} min';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(10)),
      child: Column(children: [
        _line('Rate', '1 ${q.from} ≈ ${_fmt(q.rate)} ${q.to}'),
        _line('Route', q.providerName),
        _line('WATTxchange fee', q.feeCollected
            ? '${q.platformFeeBps / 100}% (${_fmt(q.platformFeeOut)} ${q.to})'
            : 'not charged on this route'),
        _line('${q.providerName} fees', q.providerFeeOut > 0 ? '${_fmt(q.providerFeeOut)} ${q.to}' : 'included'),
        _line('Estimated time', eta),
        const SizedBox(height: 4),
        Text('The amount shown is what you receive, after every fee. ${q.custody.isNotEmpty ? 'Custody: ${q.custody}.' : ''}',
            style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ]),
    );
  }

  Widget _line(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Text(k, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          const Spacer(),
          Flexible(child: Text(v, textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white, fontSize: 13))),
        ]),
      );

  Future<void> _review(WalletProvider wallet) async {
    final q = _quote!;
    final dest = _dest.text.trim();
    if (_from == 'WTX' && _amt > wallet.balance) {
      _snack('Not enough WTX: you have ${wallet.balance.toStringAsFixed(4)}');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: _card,
        title: const Text('Confirm swap', style: TextStyle(color: Colors.white)),
        content: Text(
          'Pay ${_fmt(_amt)} ${q.from}\n'
          'Receive about ${_fmt(q.outAmount)} ${q.to}\n'
          'to $dest\n\n'
          'Via ${q.providerName}. '
          '${q.from == 'WTX' ? 'The WTX is sent from this wallet as soon as you confirm.' : 'You will get an address to send your ${q.from} to.'}\n\n'
          'The final amount can differ slightly from this estimate as prices move.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _gold, foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final order = await _svc.create(_from, _to, _amt, dest);
      String? txid;
      if (_from == 'WTX') {
        if (order.depositAddress == null) throw Exception('The desk did not return a deposit address.');
        txid = await wallet.sendCoins(order.depositAddress!, _amt, 'swap ${order.id}');
        if (txid == null) throw Exception('Sending WTX failed: ${wallet.errorMessage}');
        await _svc.markSent(order.id, txid).catchError((_) {});
      }
      if (!mounted) return;
      setState(() => _recent = [order.id, ..._recent.where((x) => x != order.id)]);
      await Navigator.push(context, MaterialPageRoute(
          builder: (_) => SwapStatusScreen(id: order.id, sentTxid: txid)));
    } catch (e) {
      _snack(_clean(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
}

/// One swap's progress, plus the deposit details when the user pays from
/// another wallet.
class SwapStatusScreen extends StatefulWidget {
  final String id;
  final String? sentTxid;
  const SwapStatusScreen({super.key, required this.id, this.sentTxid});
  @override
  State<SwapStatusScreen> createState() => _SwapStatusScreenState();
}

class _SwapStatusScreenState extends State<SwapStatusScreen> {
  final _svc = SwapService();
  final _txid = TextEditingController();
  SwapOrder? _o;
  String? _err;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _txid.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final o = await _svc.status(widget.id);
      if (mounted) setState(() { _o = o; _err = null; });
      if (o.done) _poll?.cancel();
    } catch (e) {
      if (mounted) setState(() => _err = _clean(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _o;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(backgroundColor: _card, foregroundColor: Colors.white, title: const Text('Swap status')),
      body: o == null
          ? Center(child: _err != null
              ? Text(_err!, style: const TextStyle(color: _red))
              : const CircularProgressIndicator(color: _gold))
          : ListView(padding: const EdgeInsets.all(16), children: [
              Text('${_fmt(o.amount)} ${o.from} → ~${_fmt(o.expectedOut)} ${o.to}',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(children: [
                Icon(o.state == 'completed' ? Icons.check_circle : Icons.timelapse,
                    color: o.state == 'completed' ? _green : _gold, size: 18),
                const SizedBox(width: 6),
                Text(o.stateLabel, style: const TextStyle(color: Colors.white70)),
              ]),
              const SizedBox(height: 20),
              if (widget.sentTxid != null)
                _kv(context, 'Your WTX payment', widget.sentTxid!)
              else if (o.depositAddress != null && !o.done) ...[
                Text('Send exactly ${_fmt(o.amount)} ${o.from} to:',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _kv(context, 'Deposit address', o.depositAddress!),
                if (o.memo != null) ...[
                  _kv(context, 'Memo (required)', o.memo!),
                  const Text('Include the memo exactly. Without it the swap cannot be credited.',
                      style: TextStyle(color: Colors.orange, fontSize: 12)),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: _txid,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    labelText: 'After sending: paste your transaction ID (helps tracking)',
                    labelStyle: TextStyle(color: Colors.white54),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () async {
                    final t = _txid.text.trim();
                    if (t.isEmpty) return;
                    await _svc.markSent(o.id, t).catchError((_) {});
                    _load();
                  },
                  child: const Text("I've sent it"),
                ),
              ],
              const SizedBox(height: 12),
              _kv(context, 'Receiving at', o.destination),
              if (o.payoutTx != null) _kv(context, 'Payout transaction', o.payoutTx!),
              _kv(context, 'Swap ID', o.id),
            ]),
    );
  }
}

class _RecentSwap extends StatefulWidget {
  final String id;
  final SwapService svc;
  const _RecentSwap({required this.id, required this.svc});
  @override
  State<_RecentSwap> createState() => _RecentSwapState();
}

class _RecentSwapState extends State<_RecentSwap> {
  SwapOrder? _o;
  @override
  void initState() {
    super.initState();
    widget.svc.status(widget.id).then((o) => mounted ? setState(() => _o = o) : null).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final o = _o;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(o?.state == 'completed' ? Icons.check_circle : Icons.swap_horiz,
          color: o?.state == 'completed' ? _green : _gold),
      title: Text(o == null ? widget.id : '${_fmt(o.amount)} ${o.from} → ${o.to}',
          style: const TextStyle(color: Colors.white)),
      subtitle: Text(o?.stateLabel ?? 'Loading…', style: const TextStyle(color: Colors.white54)),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SwapStatusScreen(id: widget.id))),
    );
  }
}

Widget _kv(BuildContext context, String k, String v) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        Row(children: [
          Expanded(child: SelectableText(v,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'))),
          IconButton(
            icon: const Icon(Icons.copy, size: 18, color: Colors.white54),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: v));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$k copied')));
            },
          ),
        ]),
      ]),
    );

String _fmt(double v) {
  if (v == 0) return '0';
  final s = v >= 1000 ? v.toStringAsFixed(2) : v >= 1 ? v.toStringAsFixed(4) : v.toStringAsFixed(8);
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}

String _clean(Object e) => e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
