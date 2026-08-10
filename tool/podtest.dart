import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as c;
import 'package:wattx_wallet/services/wattx_wallet.dart';

Uint8List _varint(int n) {
  if (n < 0xfd) return Uint8List.fromList([n]);
  if (n <= 0xffff) return Uint8List.fromList([0xfd, n & 0xff, n >> 8]);
  return Uint8List.fromList([0xfe, n & 0xff, (n >> 8) & 0xff, (n >> 16) & 0xff, (n >> 24) & 0xff]);
}

Uint8List magicHash(String message, String prefix) {
  final bb = BytesBuilder();
  final p = utf8.encode(prefix);
  bb.add(_varint(p.length)); bb.add(p);
  final m = utf8.encode(message);
  bb.add(_varint(m.length)); bb.add(m);
  final h1 = c.sha256.convert(bb.toBytes()).bytes;
  return Uint8List.fromList(c.sha256.convert(h1).bytes);
}

void main(List<String> args) {
  final w = WattxWallet.fromMnemonic(args[0], net: WattxNet.regtest);
  final hash = magicHash(args[1], "Qtum Signed Message:\n");
  final sig = w.ecPair.signRecoverable(hash);
  stdout.writeln('ADDR=${w.legacyAddress}');
  stdout.writeln('SIGB64=${base64.encode(sig)}');
}
