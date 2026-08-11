import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

/// Low-level transaction assembly for Qtum-style OP_SENDER contract calls.
///
/// coinslib's TransactionBuilder refuses non-standard outputs, so the
/// delegation transaction is serialized by hand here: script push/CScriptNum
/// encoding, legacy P2PKH input sighash, and the daemon's BIP143-variant
/// SignatureHashOutput for the sender signature embedded in the output
/// (src/script/interpreter.cpp SignatureHashOutput — version ‖ hashPrevouts ‖
/// hashSequence ‖ output-without-sender-sig ‖ scriptCode ‖ amount ‖
/// hashOutputs ‖ locktime ‖ hashtype, double-SHA256d).
class OpSender {
  static const opSender = 0xc4;
  static const opCall = 0xc2;
  static const sighashAll = 1;

  // ---- byte helpers -------------------------------------------------------

  static Uint8List dsha256(List<int> b) {
    final h1 = crypto.sha256.convert(b).bytes;
    return Uint8List.fromList(crypto.sha256.convert(h1).bytes);
  }

  static Uint8List varint(int n) {
    if (n < 0xfd) return Uint8List.fromList([n]);
    if (n <= 0xffff) return Uint8List.fromList([0xfd, n & 0xff, n >> 8]);
    return Uint8List.fromList(
        [0xfe, n & 0xff, (n >> 8) & 0xff, (n >> 16) & 0xff, (n >> 24) & 0xff]);
  }

  static Uint8List u32le(int n) => Uint8List(4)
    ..buffer.asByteData().setUint32(0, n, Endian.little);

  static Uint8List u64le(int n) => Uint8List(8)
    ..buffer.asByteData().setUint64(0, n, Endian.little);

  /// A minimal script data push (OP_PUSHBYTES / OP_PUSHDATA1/2). An empty
  /// vector pushes as the single byte 0x00 (OP_0) — exactly what the daemon's
  /// `CScript << std::vector()` produces for the unsigned sender-sig slot.
  static Uint8List pushData(Uint8List data) {
    final bb = BytesBuilder();
    if (data.length < 0x4c) {
      bb.addByte(data.length);
    } else if (data.length <= 0xff) {
      bb.addByte(0x4c);
      bb.addByte(data.length);
    } else {
      bb.addByte(0x4d);
      bb.addByte(data.length & 0xff);
      bb.addByte(data.length >> 8);
    }
    bb.add(data);
    return bb.toBytes();
  }

  /// CScriptNum: minimal little-endian with a sign bit — positive values only
  /// (gas limit/price, VM version, address type are all positive).
  static Uint8List scriptNum(int n) {
    assert(n >= 0);
    if (n == 0) return Uint8List(0);
    final out = <int>[];
    var v = n;
    while (v > 0) {
      out.add(v & 0xff);
      v >>= 8;
    }
    if (out.last & 0x80 != 0) out.add(0x00);
    return Uint8List.fromList(out);
  }

  static Uint8List hexToBytes(String hex) {
    final clean = hex.startsWith('0x') ? hex.substring(2) : hex;
    final out = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static String bytesToHex(Uint8List b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  /// txids display big-endian but serialize little-endian.
  static Uint8List txidLe(String txidHex) =>
      Uint8List.fromList(hexToBytes(txidHex).reversed.toList());

  // ---- signature encoding -------------------------------------------------

  static final BigInt _secpN = BigInt.parse(
      'fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141',
      radix: 16);

  static BigInt _toBig(Uint8List b) =>
      b.fold(BigInt.zero, (a, x) => (a << 8) | BigInt.from(x));

  static Uint8List _to32(BigInt v) {
    final out = Uint8List(32);
    for (var i = 31; i >= 0; i--) {
      out[i] = (v & BigInt.from(0xff)).toInt();
      v >>= 8;
    }
    return out;
  }

  /// DER-encode a 64-byte r‖s signature and append the sighash byte. S is
  /// normalized to low-S — the daemon enforces SCRIPT_VERIFY_LOW_S.
  static Uint8List derSignature(Uint8List sig64, int hashType) {
    Uint8List trim(Uint8List v) {
      var i = 0;
      while (i < v.length - 1 && v[i] == 0 && v[i + 1] < 0x80) {
        i++;
      }
      var out = v.sublist(i);
      if (out[0] >= 0x80) out = Uint8List.fromList([0, ...out]);
      return out;
    }

    final r = trim(sig64.sublist(0, 32));
    var sBig = _toBig(sig64.sublist(32));
    if (sBig > (_secpN >> 1)) sBig = _secpN - sBig;
    final s = trim(_to32(sBig));

    final bb = BytesBuilder();
    bb.addByte(0x30);
    bb.addByte(4 + r.length + s.length);
    bb.addByte(0x02);
    bb.addByte(r.length);
    bb.add(r);
    bb.addByte(0x02);
    bb.addByte(s.length);
    bb.add(s);
    bb.addByte(hashType);
    return bb.toBytes();
  }

  // ---- transaction --------------------------------------------------------

  final int version;
  final int locktime;
  final List<OpSenderInput> inputs = [];
  final List<OpSenderOutput> outputs = [];

  OpSender({this.version = 2, this.locktime = 0});

  Uint8List serialize() {
    final bb = BytesBuilder();
    bb.add(u32le(version));
    bb.add(varint(inputs.length));
    for (final i in inputs) {
      bb.add(txidLe(i.txid));
      bb.add(u32le(i.vout));
      bb.add(varint(i.scriptSig.length));
      bb.add(i.scriptSig);
      bb.add(u32le(i.sequence));
    }
    bb.add(varint(outputs.length));
    for (final o in outputs) {
      bb.add(_serializeOutput(o.value, o.script));
    }
    bb.add(u32le(locktime));
    return bb.toBytes();
  }

  static Uint8List _serializeOutput(int value, Uint8List script) {
    final bb = BytesBuilder();
    bb.add(u64le(value));
    bb.add(varint(script.length));
    bb.add(script);
    return bb.toBytes();
  }

  /// The daemon's GetOutputWithoutSenderSig: the sender-sig slot (the push
  /// directly before OP_SENDER) replaced with an empty push. Callers keep the
  /// unsigned slot script around instead of re-parsing, so this just decides
  /// which script represents each output when hashing.
  Uint8List _outputForSigning(OpSenderOutput o) =>
      _serializeOutput(o.value, o.scriptWithoutSenderSig ?? o.script);

  /// The daemon's SignatureHashOutput (BIP143-variant, SIGHASH_ALL): the hash
  /// the OP_SENDER sender signature commits to. Covers prevouts + sequences +
  /// all outputs (each OP_SENDER output with its sig slot emptied) but not
  /// input scriptSigs — so it is computed before input signing.
  Uint8List signatureHashOutput(int nOut, Uint8List scriptCode, int amount) {
    final prevouts = BytesBuilder();
    final sequences = BytesBuilder();
    for (final i in inputs) {
      prevouts.add(txidLe(i.txid));
      prevouts.add(u32le(i.vout));
      sequences.add(u32le(i.sequence));
    }
    final outs = BytesBuilder();
    for (final o in outputs) {
      outs.add(_outputForSigning(o));
    }

    final bb = BytesBuilder();
    bb.add(u32le(version));
    bb.add(dsha256(prevouts.toBytes()));
    bb.add(dsha256(sequences.toBytes()));
    bb.add(_outputForSigning(outputs[nOut]));
    bb.add(varint(scriptCode.length));
    bb.add(scriptCode);
    bb.add(u64le(amount));
    bb.add(dsha256(outs.toBytes()));
    bb.add(u32le(locktime));
    bb.add(u32le(sighashAll));
    return dsha256(bb.toBytes());
  }

  /// Legacy SIGHASH_ALL for a P2PKH input: serialize with every scriptSig
  /// empty except input [nIn], which carries [scriptCode] (the spent
  /// scriptPubKey), then append the 4-byte hash type and double-SHA256.
  Uint8List signatureHashLegacy(int nIn, Uint8List scriptCode) {
    final bb = BytesBuilder();
    bb.add(u32le(version));
    bb.add(varint(inputs.length));
    for (var i = 0; i < inputs.length; i++) {
      final inp = inputs[i];
      bb.add(txidLe(inp.txid));
      bb.add(u32le(inp.vout));
      if (i == nIn) {
        bb.add(varint(scriptCode.length));
        bb.add(scriptCode);
      } else {
        bb.addByte(0);
      }
      bb.add(u32le(inp.sequence));
    }
    bb.add(varint(outputs.length));
    for (final o in outputs) {
      bb.add(_serializeOutput(o.value, o.script));
    }
    bb.add(u32le(locktime));
    bb.add(u32le(sighashAll));
    return dsha256(bb.toBytes());
  }
}

class OpSenderInput {
  final String txid;
  final int vout;
  final Uint8List scriptPubKey; // spent output's script — the sighash scriptCode
  Uint8List scriptSig = Uint8List(0);
  final int sequence;
  OpSenderInput(this.txid, this.vout, this.scriptPubKey,
      {this.sequence = 0xffffffff});
}

class OpSenderOutput {
  final int value;
  Uint8List script;

  /// For OP_SENDER outputs: the same script with an empty sender-sig slot,
  /// used by both sighash algorithms. Null for ordinary outputs.
  Uint8List? scriptWithoutSenderSig;

  OpSenderOutput(this.value, this.script, {this.scriptWithoutSenderSig});
}
