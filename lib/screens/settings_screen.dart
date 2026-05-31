import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/wallet_provider.dart';
import '../services/rpc_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _testnet = true;
  bool _saving = false;
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    final rpc = RpcService();
    _hostCtrl.text = rpc.host;
    _portCtrl.text = rpc.port.toString();
    _testnet = rpc.isTestnet;
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() { _saving = true; _testResult = null; });
    await RpcService().saveConfig(
      host: _hostCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text.trim()) ?? 13890,
      user: _userCtrl.text.trim().isEmpty ? 'wattxrpc' : _userCtrl.text.trim(),
      password: _passCtrl.text,
      testnet: _testnet,
    );
    await context.read<WalletProvider>().connect();
    setState(() => _saving = false);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _testConnection() async {
    setState(() { _testing = true; _testResult = null; });
    final ok = await RpcService().testConnection();
    setState(() {
      _testing = false;
      _testResult = ok ? 'Connected!' : 'Failed — check host/port/credentials';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('RPC Settings', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _section('Remote Node'),
        _field('Host / IP', _hostCtrl, hint: '76.131.208.215'),
        const SizedBox(height: 12),
        _field('RPC Port', _portCtrl, hint: '13890', isNum: true),
        const SizedBox(height: 12),
        _field('RPC Username', _userCtrl, hint: 'wattxrpc'),
        const SizedBox(height: 12),
        _field('RPC Password', _passCtrl, hint: '••••••', obscure: true),
        const SizedBox(height: 12),
        Row(children: [
          const Text('Testnet Mode', style: TextStyle(color: Colors.white70)),
          const Spacer(),
          Switch(
            value: _testnet,
            onChanged: (v) => setState(() => _testnet = v),
            activeColor: const Color(0xFFF7C948),
          ),
        ]),
        const SizedBox(height: 20),

        _info('Default seednode: 76.131.208.215:13890 (testnet RPC)\n'
            'Enable "Testnet Mode" to connect to WATTx testnet v0.1.0'),

        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: OutlinedButton(
            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24), foregroundColor: Colors.white70),
            onPressed: _testing ? null : _testConnection,
            child: _testing
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Test Connection'),
          )),
          const SizedBox(width: 12),
          Expanded(child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF7C948), foregroundColor: Colors.black),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save & Connect', style: TextStyle(fontWeight: FontWeight.bold)),
          )),
        ]),

        if (_testResult != null) Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(_testResult!,
            style: TextStyle(color: _testResult!.contains('!') ? const Color(0xFF3FB950) : Colors.red),
            textAlign: TextAlign.center,
          ),
        ),

        const SizedBox(height: 32),
        _section('Backup & Security'),
        ListTile(
          tileColor: const Color(0xFF161B22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          leading: const Icon(Icons.vpn_key, color: Color(0xFFF7C948)),
          title: const Text('Export Private Key', style: TextStyle(color: Colors.white)),
          subtitle: const Text('Keep your key offline and secure', style: TextStyle(color: Colors.white38, fontSize: 12)),
          onTap: () => _exportKey(context),
        ),
      ]),
    );
  }

  Future<void> _exportKey(BuildContext context) async {
    final passCtrl = TextEditingController();
    await showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF161B22),
      title: const Text('Export Private Key', style: TextStyle(color: Colors.white)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Enter your wallet passphrase to reveal the private key.',
            style: TextStyle(color: Colors.white54, fontSize: 13)),
        const SizedBox(height: 12),
        TextField(
          controller: passCtrl,
          obscureText: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Passphrase',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.white.withOpacity(0.06),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
          ),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
          onPressed: () async {
            Navigator.pop(ctx);
            final wallet = context.read<WalletProvider>();
            final addr = wallet.receiveAddress;
            try {
              await wallet.rpc.walletPassphrase(passCtrl.text, 30);
              final key = await wallet.rpc.dumpPrivKey(addr);
              if (mounted) {
                showDialog(context: context, builder: (_) => AlertDialog(
                  backgroundColor: const Color(0xFF161B22),
                  title: const Text('Private Key', style: TextStyle(color: Colors.orange)),
                  content: SelectableText(key, style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done', style: TextStyle(color: Colors.white))),
                  ],
                ));
              }
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade800));
            }
          },
          child: const Text('Reveal Key', style: TextStyle(color: Colors.white)),
        ),
      ],
    ));
  }

  Widget _section(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(t, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
  );

  Widget _field(String label, TextEditingController ctrl, {String hint = '', bool isNum = false, bool obscure = false}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          keyboardType: isNum ? TextInputType.number : TextInputType.text,
          obscureText: obscure,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white24),
            filled: true,
            fillColor: const Color(0xFF161B22),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
        ),
      ]);

  Widget _info(String t) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF58A6FF).withOpacity(0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFF58A6FF).withOpacity(0.2)),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.info_outline, color: Color(0xFF58A6FF), size: 16),
      const SizedBox(width: 8),
      Expanded(child: Text(t, style: const TextStyle(color: Color(0xFF58A6FF), fontSize: 12))),
    ]),
  );
}
