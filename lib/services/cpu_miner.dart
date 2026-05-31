import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:math';
import 'package:crypto/crypto.dart' as crypto;
import 'rpc_service.dart';

enum MinerState { stopped, running, paused }

class MiningStats {
  final double hashRate;    // H/s
  final int totalHashes;
  final int blocksFound;
  final Duration elapsed;
  final int currentDifficulty;

  const MiningStats({
    this.hashRate = 0,
    this.totalHashes = 0,
    this.blocksFound = 0,
    this.elapsed = Duration.zero,
    this.currentDifficulty = 0,
  });
}

// Message sent to isolate
class _MinerCommand {
  final String type; // 'start', 'stop'
  final Map<String, dynamic>? blockTemplate;
  final int threads;
  _MinerCommand(this.type, {this.blockTemplate, this.threads = 1});
}

// Message sent from isolate
class _MinerResult {
  final String type; // 'hash', 'found', 'error'
  final int hashes;
  final String? blockHex;
  final String? error;
  _MinerResult.hashes(this.hashes) : type = 'hash', blockHex = null, error = null;
  _MinerResult.found(this.blockHex) : type = 'found', hashes = 0, error = null;
  _MinerResult.error(this.error) : type = 'error', hashes = 0, blockHex = null;
}

class CpuMiner {
  final RpcService _rpc;
  MinerState state = MinerState.stopped;
  MiningStats stats = const MiningStats();

  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  Timer? _statsTimer;
  Timer? _templateRefreshTimer;

  int _hashesThisTick = 0;
  final DateTime _startTime = DateTime.now();
  int _totalHashes = 0;
  int _blocksFound = 0;
  int _threads;

  final StreamController<MiningStats> _statsController = StreamController.broadcast();
  Stream<MiningStats> get statsStream => _statsController.stream;

  CpuMiner(this._rpc, {int threads = 1}) : _threads = threads;

  int get threads => _threads;
  set threads(int t) => _threads = t.clamp(1, 4);

  Future<void> start() async {
    if (state == MinerState.running) return;

    final template = await _rpc.getBlockTemplate();
    await _spawnIsolate(template);

    state = MinerState.running;
    _statsTimer = Timer.periodic(const Duration(seconds: 2), _updateStats);

    // Refresh template every 15 seconds (new block or transactions)
    _templateRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      try {
        final t = await _rpc.getBlockTemplate();
        _sendPort?.send(_MinerCommand('template', blockTemplate: t));
      } catch (_) {}
    });
  }

  Future<void> _spawnIsolate(Map<String, dynamic> template) async {
    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(
      _mineLoop,
      [_receivePort!.sendPort, template, _threads],
    );

    _receivePort!.listen((msg) {
      if (msg is SendPort) {
        _sendPort = msg;
      } else if (msg is _MinerResult) {
        if (msg.type == 'hash') {
          _hashesThisTick += msg.hashes;
          _totalHashes += msg.hashes;
        } else if (msg.type == 'found') {
          _blocksFound++;
          _rpc.submitBlock(msg.blockHex!).ignore();
        }
      }
    });
  }

  void _updateStats(Timer _) {
    final elapsed = DateTime.now().difference(_startTime);
    final secs = elapsed.inSeconds == 0 ? 1 : elapsed.inSeconds;
    final hr = _totalHashes / secs;
    stats = MiningStats(
      hashRate: hr,
      totalHashes: _totalHashes,
      blocksFound: _blocksFound,
      elapsed: elapsed,
    );
    _hashesThisTick = 0;
    _statsController.add(stats);
  }

  void stop() {
    state = MinerState.stopped;
    _statsTimer?.cancel();
    _templateRefreshTimer?.cancel();
    _sendPort?.send(_MinerCommand('stop'));
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _receivePort?.close();
    _receivePort = null;
  }

  void dispose() {
    stop();
    _statsController.close();
  }

  // SHA-256d CPU mining isolate — runs in a background isolate, never on UI thread
  static void _mineLoop(List<dynamic> args) {
    final sendPort = args[0] as SendPort;
    var template = args[1] as Map<String, dynamic>;
    final threads = args[2] as int;

    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);

    bool running = true;
    receivePort.listen((msg) {
      if (msg is _MinerCommand) {
        if (msg.type == 'stop') running = false;
        if (msg.type == 'template') template = msg.blockTemplate!;
      }
    });

    final rng = Random.secure();
    var nonce = rng.nextInt(0xFFFFFFFF);
    int batchSize = 1000;

    while (running) {
      // Build a minimal header from template fields
      try {
        final version = (template['version'] as int?) ?? 1;
        final prevHash = template['previousblockhash'] as String? ?? '';
        final merkleRoot = template['transactions'] != null ? _buildMerkleRoot(template) : '';
        final time = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final bits = template['bits'] as String? ?? '1f00ffff';
        final target = _bitsToTarget(bits);

        for (int i = 0; i < batchSize && running; i++) {
          nonce = (nonce + 1) & 0xFFFFFFFF;
          final header = _buildHeader(version, prevHash, merkleRoot, time, bits, nonce);
          final hash = _sha256d(header);

          if (_hashMeetsTarget(hash, target)) {
            // Found a valid block — submit
            final blockHex = _buildBlockHex(template, header, nonce);
            sendPort.send(_MinerResult.found(blockHex));
            nonce = rng.nextInt(0xFFFFFFFF);
          }
        }
        sendPort.send(_MinerResult.hashes(batchSize));
      } catch (_) {
        // Template malformed — wait for refresh
        _sleep(500);
      }
    }
  }

  static void _sleep(int ms) {
    final end = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(end)) {}
  }

  static String _buildMerkleRoot(Map<String, dynamic> template) {
    final txns = template['transactions'] as List? ?? [];
    if (txns.isEmpty) return '0' * 64;
    // Simple: just return first txid as placeholder (real impl would compute full merkle)
    final first = txns.first as Map;
    return first['txid'] as String? ?? '0' * 64;
  }

  static Uint8List _bitsToTarget(String bits) {
    final b = int.parse(bits, radix: 16);
    final exp = (b >> 24) & 0xFF;
    final mant = b & 0xFFFFFF;
    final target = Uint8List(32);
    if (exp >= 3) {
      final pos = 32 - exp;
      if (pos >= 0 && pos < 32) {
        target[pos] = (mant >> 16) & 0xFF;
        if (pos + 1 < 32) target[pos + 1] = (mant >> 8) & 0xFF;
        if (pos + 2 < 32) target[pos + 2] = mant & 0xFF;
      }
    }
    return target;
  }

  static Uint8List _buildHeader(int version, String prevHash, String merkleRoot,
      int time, String bits, int nonce) {
    final buf = Uint8List(80);
    final bdata = ByteData.view(buf.buffer);
    bdata.setUint32(0, version, Endian.little);
    _writeHashLE(buf, 4, prevHash);
    _writeHashLE(buf, 36, merkleRoot);
    bdata.setUint32(68, time, Endian.little);
    bdata.setUint32(72, int.parse(bits, radix: 16), Endian.big);
    bdata.setUint32(76, nonce, Endian.little);
    return buf;
  }

  static void _writeHashLE(Uint8List buf, int offset, String hex) {
    if (hex.length < 64) return;
    for (int i = 0; i < 32; i++) {
      buf[offset + i] = int.parse(hex.substring((31 - i) * 2, (31 - i) * 2 + 2), radix: 16);
    }
  }

  static Uint8List _sha256d(Uint8List data) {
    final h1 = crypto.sha256.convert(data).bytes;
    return Uint8List.fromList(crypto.sha256.convert(h1).bytes);
  }

  static bool _hashMeetsTarget(Uint8List hash, Uint8List target) {
    // Hash is LE, compare big-endian
    for (int i = 31; i >= 0; i--) {
      if (hash[i] < target[i]) return true;
      if (hash[i] > target[i]) return false;
    }
    return true;
  }

  static String _buildBlockHex(Map<String, dynamic> template, Uint8List header, int nonce) {
    // Return serialized header + tx count + coinbase tx
    final sb = StringBuffer();
    for (final b in header) sb.write(b.toRadixString(16).padLeft(2, '0'));
    // Append empty tx list placeholder
    sb.write('00');
    return sb.toString();
  }
}
