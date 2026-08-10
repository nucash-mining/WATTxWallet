import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;

/// Stratum pool miner for the WATTx merged-mining pool.
///
/// The phone only does what it can do well: sha256d over the 80-byte header the
/// pool hands out. Everything a mobile client cannot get right — the Qtum-style
/// WATTx header (hashStateRoot/hashUTXORoot/prevoutStake/...), the coinbase
/// that pays the miner, the AuxPoW proof and the block submission — happens
/// server-side, exactly as it does for desktop miners on the same port.
///
/// Payout: the WTX address passed to [start] is the stratum username, and the
/// pool credits shares (and the block reward) to it.
enum PoolMinerState { stopped, connecting, running }

class PoolMiningStats {
  final double hashRate; // H/s
  final int totalHashes;
  final int sharesAccepted;
  final int sharesRejected;
  final Duration elapsed;
  final String? lastError;
  final bool connected;

  const PoolMiningStats({
    this.hashRate = 0,
    this.totalHashes = 0,
    this.sharesAccepted = 0,
    this.sharesRejected = 0,
    this.elapsed = Duration.zero,
    this.lastError,
    this.connected = false,
  });
}

class _Job {
  final String jobId;
  final String prevHashLE;   // header bytes 4..36, already in header order
  final String coinb1;
  final String coinb2;
  final List<String> branch;
  final String versionLE;
  final String nbitsLE;
  final String ntimeBE;
  _Job(this.jobId, this.prevHashLE, this.coinb1, this.coinb2, this.branch,
      this.versionLE, this.nbitsLE, this.ntimeBE);
}

class PoolMiner {
  static const defaultHost = 'pools.wattxchange.app';
  static const defaultPort = 3334; // sha256d

  final String host;
  final int port;
  final int threads;

  PoolMiner({this.host = defaultHost, this.port = defaultPort, this.threads = 1});

  Socket? _socket;
  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  StreamSubscription? _socketSub;

  PoolMinerState state = PoolMinerState.stopped;
  String? _extranonce1;
  int _extranonce2Size = 4;
  int _msgId = 10;
  String _buffer = '';
  String _address = '';

  int _sharesAccepted = 0;
  int _sharesRejected = 0;
  int _totalHashes = 0;
  int _hashesThisTick = 0;
  DateTime? _startedAt;
  String? _lastError;
  Timer? _statsTimer;

  final _statsController = StreamController<PoolMiningStats>.broadcast();
  Stream<PoolMiningStats> get statsStream => _statsController.stream;

  Future<void> start(String wtxAddress, {String worker = 'android'}) async {
    if (state != PoolMinerState.stopped) return;
    if (wtxAddress.isEmpty) {
      throw StateError('A WATTx address is required so the pool knows who to pay.');
    }
    _address = worker.isEmpty ? wtxAddress : '$wtxAddress.$worker';
    state = PoolMinerState.connecting;
    _lastError = null;
    _startedAt = DateTime.now();

    _socket = await Socket.connect(host, port, timeout: const Duration(seconds: 20));
    _socketSub = _socket!.listen(_onData,
        onError: (e) => _fail('connection error: $e'),
        onDone: () => _fail('pool closed the connection'));

    _send({'id': 1, 'method': 'mining.subscribe', 'params': <String>[]});
    _send({'id': 2, 'method': 'mining.authorize', 'params': [_address, 'x']});

    await _spawnIsolate();
    state = PoolMinerState.running;
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) => _emitStats());
  }

  void stop() {
    _statsTimer?.cancel();
    _socketSub?.cancel();
    _socket?.destroy();
    _socket = null;
    _sendPort?.send({'type': 'stop'});
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _receivePort?.close();
    state = PoolMinerState.stopped;
    _emitStats();
  }

  void dispose() {
    stop();
    _statsController.close();
  }

  void _fail(String message) {
    _lastError = message;
    _emitStats();
  }

  void _send(Map<String, dynamic> msg) {
    _socket?.write('${jsonEncode(msg)}\n');
  }

  void _onData(List<int> data) {
    _buffer += utf8.decode(data, allowMalformed: true);
    while (true) {
      final nl = _buffer.indexOf('\n');
      if (nl < 0) break;
      final line = _buffer.substring(0, nl).trim();
      _buffer = _buffer.substring(nl + 1);
      if (line.isEmpty) continue;
      try {
        _handleMessage(jsonDecode(line) as Map<String, dynamic>);
      } catch (_) {
        // ignore anything that isn't well-formed stratum JSON
      }
    }
  }

  void _handleMessage(Map<String, dynamic> msg) {
    final result = msg['result'];

    // subscribe response: [[...], extranonce1, extranonce2_size]
    if (result is List && result.length == 3 && result[1] is String) {
      _extranonce1 = result[1] as String;
      _extranonce2Size = (result[2] as num).toInt();
      return;
    }

    if (msg['method'] == 'mining.notify') {
      final p = msg['params'] as List;
      // prevhash arrives as 8 big-endian words; reverse each word to get the
      // little-endian bytes the header wants.
      final rawPrev = p[1] as String;
      final sb = StringBuffer();
      for (int w = 0; w < 8; w++) {
        final word = rawPrev.substring(w * 8, w * 8 + 8);
        for (int b = 3; b >= 0; b--) {
          sb.write(word.substring(b * 2, b * 2 + 2));
        }
      }
      final job = _Job(
        p[0] as String,
        sb.toString(),
        p[2] as String,
        p[3] as String,
        (p[4] as List).cast<String>(),
        _reverseHex(p[5] as String),
        _reverseHex(p[6] as String),
        p[7] as String,
      );
      _sendPort?.send({
        'type': 'job',
        'jobId': job.jobId,
        'prevHashLE': job.prevHashLE,
        'coinb1': job.coinb1,
        'coinb2': job.coinb2,
        'branch': job.branch,
        'versionLE': job.versionLE,
        'nbitsLE': job.nbitsLE,
        'ntimeBE': job.ntimeBE,
        'extranonce1': _extranonce1 ?? '',
        'extranonce2Size': _extranonce2Size,
      });
      return;
    }

    if (result == true) {
      _sharesAccepted++;
      _emitStats();
    } else if (msg['error'] != null && msg['id'] != 1 && msg['id'] != 2) {
      _sharesRejected++;
      _lastError = jsonEncode(msg['error']);
      _emitStats();
    }
  }

  static String _reverseHex(String hex) {
    final sb = StringBuffer();
    for (int i = hex.length - 2; i >= 0; i -= 2) {
      sb.write(hex.substring(i, i + 2));
    }
    return sb.toString();
  }

  Future<void> _spawnIsolate() async {
    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(_mineLoop, [_receivePort!.sendPort, threads]);
    _receivePort!.listen((msg) {
      if (msg is SendPort) {
        _sendPort = msg;
      } else if (msg is Map) {
        if (msg['type'] == 'hashes') {
          final n = msg['count'] as int;
          _hashesThisTick += n;
          _totalHashes += n;
        } else if (msg['type'] == 'share') {
          _send({
            'id': _msgId++,
            'method': 'mining.submit',
            'params': [
              _address,
              msg['jobId'],
              msg['extranonce2'],
              msg['ntime'],
              msg['nonce'],
            ],
          });
        }
      }
    });
  }

  void _emitStats() {
    final elapsed = _startedAt == null
        ? Duration.zero
        : DateTime.now().difference(_startedAt!);
    _statsController.add(PoolMiningStats(
      hashRate: _hashesThisTick / 2.0,
      totalHashes: _totalHashes,
      sharesAccepted: _sharesAccepted,
      sharesRejected: _sharesRejected,
      elapsed: elapsed,
      lastError: _lastError,
      connected: _socket != null && state == PoolMinerState.running,
    ));
    _hashesThisTick = 0;
  }

  // ── isolate: sha256d grind ────────────────────────────────────────────────
  static void _mineLoop(List<dynamic> args) {
    final SendPort main = args[0] as SendPort;
    final port = ReceivePort();
    main.send(port.sendPort);

    Map<String, dynamic>? job;
    bool stopped = false;
    final rng = Random.secure();

    port.listen((msg) {
      if (msg is Map && msg['type'] == 'job') {
        job = Map<String, dynamic>.from(msg);
      } else if (msg is Map && msg['type'] == 'stop') {
        stopped = true;
      }
    });

    Future<void> grind() async {
      while (!stopped) {
        final j = job;
        if (j == null) {
          await Future.delayed(const Duration(milliseconds: 200));
          continue;
        }
        final jobId = j['jobId'] as String;
        final en2Size = j['extranonce2Size'] as int;
        final en2 = List<int>.generate(en2Size, (_) => rng.nextInt(256))
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();

        final coinbase = _hexToBytes(
            (j['coinb1'] as String) + (j['extranonce1'] as String) + en2 + (j['coinb2'] as String));
        var root = _sha256d(coinbase);
        for (final b in (j['branch'] as List).cast<String>()) {
          root = _sha256d(Uint8List.fromList([...root, ..._hexToBytes(b)]));
        }

        final header = Uint8List(80);
        header.setRange(0, 4, _hexToBytes(j['versionLE'] as String));
        header.setRange(4, 36, _hexToBytes(j['prevHashLE'] as String));
        header.setRange(36, 68, root);
        header.setRange(68, 72, _hexToBytes(_reverseHex(j['ntimeBE'] as String)));
        header.setRange(72, 76, _hexToBytes(j['nbitsLE'] as String));
        final view = ByteData.view(header.buffer);

        int nonce = rng.nextInt(0xFFFFFFFF);
        int done = 0;
        // Grind in slices so a new job (or stop) is picked up promptly and the
        // UI isolate keeps getting hashrate updates.
        while (!stopped && job != null && (job!['jobId'] as String) == jobId) {
          for (int i = 0; i < 500; i++) {
            view.setUint32(76, nonce & 0xFFFFFFFF, Endian.little);
            final h = _sha256d(header);
            // pool share gate: top 16 bits zero (the server re-checks the real
            // target, so a loose local filter only costs a rejected share)
            if (h[31] == 0 && h[30] == 0) {
              final nonceBE = _bytesToHex(
                  Uint8List.fromList(header.sublist(76, 80).reversed.toList()));
              main.send({
                'type': 'share',
                'jobId': jobId,
                'extranonce2': en2,
                'ntime': j['ntimeBE'],
                'nonce': nonceBE,
              });
            }
            nonce = (nonce + 1) & 0xFFFFFFFF;
            done++;
          }
          main.send({'type': 'hashes', 'count': done});
          done = 0;
          await Future.delayed(Duration.zero);
        }
      }
    }

    grind();
  }

  static Uint8List _sha256d(Uint8List data) {
    final h1 = crypto.sha256.convert(data).bytes;
    return Uint8List.fromList(crypto.sha256.convert(h1).bytes);
  }

  static Uint8List _hexToBytes(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (int i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static String _bytesToHex(Uint8List b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
}
