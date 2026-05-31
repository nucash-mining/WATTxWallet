import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/wallet_provider.dart';

class ReceiveScreen extends StatelessWidget {
  const ReceiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    final address = wallet.receiveAddress;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Receive WATTx', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Color(0xFFF7C948)),
            tooltip: 'New address',
            onPressed: () => wallet.getNewAddress(),
          ),
        ],
      ),
      body: address.isEmpty
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFF7C948)))
          : ListView(padding: const EdgeInsets.all(24), children: [
              Center(child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: 'wattx:$address',
                  version: QrVersions.auto,
                  size: 220,
                ),
              )),
              const SizedBox(height: 24),
              const Text('Your Address', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: address));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Address copied to clipboard'), backgroundColor: Color(0xFF238636)));
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161B22),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(children: [
                    Expanded(child: Text(address, style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'))),
                    const SizedBox(width: 8),
                    const Icon(Icons.copy, color: Color(0xFFF7C948), size: 18),
                  ]),
                ),
              ),
              const SizedBox(height: 24),
              if (wallet.addresses.length > 1) ...[
                const Text('Previous Addresses', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ...wallet.addresses.skip(1).map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: a));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF161B22),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white.withOpacity(0.06)),
                      ),
                      child: Row(children: [
                        Expanded(child: Text(a, style: const TextStyle(color: Colors.white54, fontSize: 12, fontFamily: 'monospace'))),
                        const Icon(Icons.copy, color: Colors.white24, size: 14),
                      ]),
                    ),
                  ),
                )),
              ],
            ]),
    );
  }
}
