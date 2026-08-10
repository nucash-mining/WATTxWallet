import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../providers/wallet_provider.dart';

class SendScreen extends StatefulWidget {
  const SendScreen({super.key});
  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final _addrCtrl = TextEditingController();
  final _amtCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _sending = false;
  String? _txid;
  String? _error;

  @override
  void dispose() {
    _addrCtrl.dispose();
    _amtCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final addr = _addrCtrl.text.trim();
    final amt = double.tryParse(_amtCtrl.text.trim());
    if (addr.isEmpty || amt == null || amt <= 0) {
      setState(() => _error = 'Enter a valid address and amount');
      return;
    }
    setState(() { _sending = true; _error = null; _txid = null; });
    final provider = context.read<WalletProvider>();
    final txid = await provider.sendCoins(addr, amt, _noteCtrl.text.trim());
    setState(() {
      _sending = false;
      if (txid != null) {
        _txid = txid;
        _addrCtrl.clear();
        _amtCtrl.clear();
        _noteCtrl.clear();
      } else {
        // Show the real reason (insufficient funds, node unreachable, …) instead
        // of a generic message — there is no wallet to "unlock" in self-custody.
        final msg = provider.errorMessage;
        _error = msg.isEmpty ? 'Transaction failed.' : msg;
      }
    });
  }

  void _scanQR() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: 380,
        child: Column(children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Scan WATTx Address', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          Expanded(child: MobileScanner(
            onDetect: (capture) {
              final code = capture.barcodes.first.rawValue ?? '';
              if (code.isNotEmpty) {
                _addrCtrl.text = code.startsWith('wattx:') ? code.substring(6) : code;
                Navigator.pop(context);
              }
            },
          )),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Send WATTx', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // Balance
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Available balance', style: TextStyle(color: Colors.white54)),
            Text('${wallet.balance.toStringAsFixed(4)} WTX',
                style: const TextStyle(color: Color(0xFFF7C948), fontWeight: FontWeight.bold)),
          ]),
        ),
        const SizedBox(height: 20),

        _label('Recipient Address'),
        Row(children: [
          Expanded(child: _field(_addrCtrl, 'W... or tw1...')),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner, color: Color(0xFFF7C948)),
            onPressed: _scanQR,
          ),
        ]),
        const SizedBox(height: 12),

        _label('Amount (WTX)'),
        Row(children: [
          Expanded(child: _field(_amtCtrl, '0.0000', isNum: true)),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => _amtCtrl.text = wallet.balance.toStringAsFixed(4),
            child: const Text('MAX', style: TextStyle(color: Color(0xFFF7C948))),
          ),
        ]),
        const SizedBox(height: 12),

        _label('Note (optional)'),
        _field(_noteCtrl, 'Memo / comment'),
        const SizedBox(height: 24),

        if (_error != null) Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(_error!, style: const TextStyle(color: Colors.red)),
        ),

        if (_txid != null) Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF238636).withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF238636).withOpacity(0.4)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Sent!', style: TextStyle(color: Color(0xFF3FB950), fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: _txid!));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('TXID copied')));
              },
              child: Text(_txid!, style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ),
          ]),
        ),

        const SizedBox(height: 8),
        SizedBox(width: double.infinity, height: 52,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF7C948),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _sending ? null : _send,
            child: _sending
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Send WATTx', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ]),
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(t, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
  );

  Widget _field(TextEditingController ctrl, String hint, {bool isNum = false}) => TextField(
    controller: ctrl,
    keyboardType: isNum ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38),
      filled: true,
      fillColor: const Color(0xFF161B22),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
    ),
  );
}
