import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Encrypts the recovery phrase with a passphrase the user chooses.
///
/// The platform secure store already keeps the seed out of other apps' reach,
/// but it unlocks whenever the device does — so anyone holding an unlocked
/// phone has the wallet. A passphrase makes the seed unreadable without
/// something the user knows, and that is what "locked" has to mean for a
/// wallet: not a screen in front of the balance, but ciphertext.
///
/// scrypt (N=2^15) then AES-256-GCM. GCM rather than CBC because it
/// authenticates: a wrong passphrase fails the tag check instead of returning
/// plausible-looking garbage that would be handed to the mnemonic parser.
class WalletCrypto {
  static const _n = 32768; // 2^15 — deliberately slow on a phone
  static const _r = 8;
  static const _p = 1;
  static const _keyBytes = 32;
  static const _saltBytes = 16;
  static const _nonceBytes = 12;
  static const _macBits = 128;

  static Uint8List _randomBytes(int n) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => rng.nextInt(256)));
  }

  static Uint8List _deriveKey(String passphrase, Uint8List salt) {
    final params = ScryptParameters(_n, _r, _p, _keyBytes, salt);
    return (Scrypt()..init(params))
        .process(Uint8List.fromList(utf8.encode(passphrase)));
  }

  /// Returns a self-describing envelope: version, salt, nonce and ciphertext.
  /// Everything needed to decrypt except the passphrase, so the parameters can
  /// change later without stranding wallets created today.
  static String encrypt(String plaintext, String passphrase) {
    final salt = _randomBytes(_saltBytes);
    final nonce = _randomBytes(_nonceBytes);
    final key = _deriveKey(passphrase, salt);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), _macBits, nonce, Uint8List(0)));
    final out = cipher.process(Uint8List.fromList(utf8.encode(plaintext)));

    key.fillRange(0, key.length, 0);
    return jsonEncode({
      'v': 1,
      'kdf': 'scrypt',
      'n': _n, 'r': _r, 'p': _p,
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'ct': base64Encode(out),
    });
  }

  /// Null when the passphrase is wrong — GCM's tag check catches it, so a bad
  /// passphrase can never yield a wrong-but-valid-looking phrase.
  static String? decrypt(String envelope, String passphrase) {
    try {
      final m = jsonDecode(envelope) as Map<String, dynamic>;
      final salt = base64Decode(m['salt'] as String);
      final nonce = base64Decode(m['nonce'] as String);
      final ct = base64Decode(m['ct'] as String);
      final params = ScryptParameters(
        (m['n'] as num?)?.toInt() ?? _n,
        (m['r'] as num?)?.toInt() ?? _r,
        (m['p'] as num?)?.toInt() ?? _p,
        _keyBytes,
        salt,
      );
      final key = (Scrypt()..init(params))
          .process(Uint8List.fromList(utf8.encode(passphrase)));
      final cipher = GCMBlockCipher(AESEngine())
        ..init(false, AEADParameters(KeyParameter(key), _macBits, nonce, Uint8List(0)));
      final plain = cipher.process(ct);
      key.fillRange(0, key.length, 0);
      return utf8.decode(plain);
    } catch (_) {
      return null;
    }
  }

  /// True when the stored value is an encrypted envelope rather than a bare
  /// phrase, so wallets created before encryption existed still load.
  static bool isEncrypted(String stored) {
    try {
      final m = jsonDecode(stored);
      return m is Map && m['ct'] != null && m['salt'] != null;
    } catch (_) {
      return false;
    }
  }
}
