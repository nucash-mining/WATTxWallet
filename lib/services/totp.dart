import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart' show KeyParameter;
import 'package:pointycastle/digests/sha1.dart';
import 'package:pointycastle/macs/hmac.dart';

/// RFC 6238 time-based one-time passwords, and the RFC 4648 base32 the
/// authenticator apps expect.
///
/// Implemented here rather than pulled in as a dependency: it is thirty lines,
/// and a second factor guarding a wallet is not somewhere to inherit an
/// unaudited package for the sake of convenience.
class Totp {
  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  /// A fresh 160-bit secret, which is what RFC 4226 recommends for HMAC-SHA1.
  static String generateSecret() {
    final rng = Random.secure();
    final bytes = Uint8List.fromList(List.generate(20, (_) => rng.nextInt(256)));
    return base32Encode(bytes);
  }

  static String base32Encode(Uint8List data) {
    final out = StringBuffer();
    var buffer = 0, bits = 0;
    for (final b in data) {
      buffer = (buffer << 8) | b;
      bits += 8;
      while (bits >= 5) {
        out.write(_alphabet[(buffer >> (bits - 5)) & 31]);
        bits -= 5;
      }
    }
    if (bits > 0) out.write(_alphabet[(buffer << (5 - bits)) & 31]);
    return out.toString();
  }

  static Uint8List base32Decode(String s) {
    final clean = s.toUpperCase().replaceAll(RegExp(r'[^A-Z2-7]'), '');
    final out = <int>[];
    var buffer = 0, bits = 0;
    for (final c in clean.split('')) {
      final v = _alphabet.indexOf(c);
      if (v < 0) continue;
      buffer = (buffer << 5) | v;
      bits += 5;
      if (bits >= 8) {
        out.add((buffer >> (bits - 8)) & 0xff);
        bits -= 8;
      }
    }
    return Uint8List.fromList(out);
  }

  /// The 6-digit code for [secret] at [time] (default: now).
  static String code(String secret, {DateTime? time, int period = 30}) {
    final counter =
        ((time ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000) ~/ period;
    final msg = ByteData(8)..setUint64(0, counter);
    final mac = HMac(SHA1Digest(), 64)
      ..init(KeyParameter(base32Decode(secret)));
    final digest = Uint8List(mac.macSize);
    mac.update(msg.buffer.asUint8List(), 0, 8);
    mac.doFinal(digest, 0);

    final offset = digest[digest.length - 1] & 0x0f;
    final binary = ((digest[offset] & 0x7f) << 24) |
        ((digest[offset + 1] & 0xff) << 16) |
        ((digest[offset + 2] & 0xff) << 8) |
        (digest[offset + 3] & 0xff);
    return (binary % 1000000).toString().padLeft(6, '0');
  }

  /// Verify [input], allowing [window] steps of clock drift either way.
  ///
  /// Comparison is constant-time: a timing oracle on a 6-digit code is worth
  /// closing even though the search space is small.
  static bool verify(String secret, String input, {int window = 1, int period = 30}) {
    final candidate = input.replaceAll(RegExp(r'\s'), '');
    if (candidate.length != 6) return false;
    final now = DateTime.now();
    var ok = false;
    for (var i = -window; i <= window; i++) {
      final t = now.add(Duration(seconds: i * period));
      final expected = code(secret, time: t, period: period);
      var diff = 0;
      for (var j = 0; j < 6; j++) {
        diff |= expected.codeUnitAt(j) ^ candidate.codeUnitAt(j);
      }
      if (diff == 0) ok = true; // no early return: keep the timing flat
    }
    return ok;
  }

  /// The otpauth:// URI an authenticator app scans.
  static String provisioningUri(String secret, {String account = 'WATTx wallet'}) =>
      'otpauth://totp/${Uri.encodeComponent(account)}'
      '?secret=$secret&issuer=WATTx&algorithm=SHA1&digits=6&period=30';
}
