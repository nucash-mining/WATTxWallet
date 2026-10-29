import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha512.dart';

/// Collects entropy from the user dragging a finger around the screen, the way
/// the old paper-wallet generators did.
///
/// A word on what this is and is not. The platform CSPRNG ([Random.secure]) is
/// already a sound source; finger movement is not needed to make a safe key,
/// and on its own it would be *worse* — touch coordinates are far less random
/// than they feel, being smooth, low-resolution and heavily correlated between
/// samples.
///
/// So this never replaces the system generator. The gesture is hashed and then
/// XORed with [Random.secure] output, which means the result is at least as
/// strong as the CSPRNG alone no matter how poor the gesture was, and strictly
/// better if the gesture did carry real unpredictability. That is the honest
/// version of the feature: it can only add.
class TouchEntropy {
  final SHA512Digest _digest = SHA512Digest();
  int _samples = 0;
  double _lastX = double.nan;
  double _lastY = double.nan;

  /// Rough lower bound on bits gathered, used to drive the progress bar.
  double _estimatedBits = 0;

  /// Enough movement to feel deliberate without being tedious.
  static const double targetBits = 256;
  static const double _bitsPerMove = 1.5;
  static const double _minTravelPx = 6;

  int get sampleCount => _samples;

  /// 0..1 against the target, for the UI.
  double get progress => (_estimatedBits / targetBits).clamp(0.0, 1.0);

  bool get isComplete => _estimatedBits >= targetBits;

  /// Feed one touch sample. Timing is included because the interval between
  /// events is a better source than position: it reflects scheduler and
  /// digitiser jitter rather than the smooth path of a finger.
  void add(double x, double y, double pressure) {
    final b = ByteData(28)
      ..setFloat32(0, x)
      ..setFloat32(4, y)
      ..setFloat32(8, pressure)
      ..setUint64(12, DateTime.now().microsecondsSinceEpoch)
      ..setUint32(20, _samples)
      ..setUint32(24, _stopwatch.elapsedMicroseconds & 0xffffffff);
    _digest.update(b.buffer.asUint8List(), 0, 28);
    _samples++;

    // Credit entropy only for genuine direction changes and distance, so
    // holding still or tracing one slow line does not fill the bar.
    if (!_lastX.isNaN) {
      final dx = x - _lastX, dy = y - _lastY;
      if (sqrt(dx * dx + dy * dy) > _minTravelPx) _estimatedBits += _bitsPerMove;
    }
    _lastX = x;
    _lastY = y;
  }

  final Stopwatch _stopwatch = Stopwatch()..start();

  /// Produce [byteCount] bytes of seed material.
  ///
  /// gesture-hash XOR CSPRNG — see the class comment for why the XOR is the
  /// whole point.
  Uint8List mix(int byteCount) {
    // Fold in the clock and the collected count so two identical gestures
    // still differ.
    final tail = ByteData(12)
      ..setUint64(0, DateTime.now().microsecondsSinceEpoch)
      ..setUint32(8, _samples);
    _digest.update(tail.buffer.asUint8List(), 0, 12);

    final gesture = Uint8List(_digest.digestSize);
    // Clone-free: doFinal resets the digest, which is fine — a TouchEntropy is
    // used once and then discarded.
    _digest.doFinal(gesture, 0);

    final out = Uint8List(byteCount);
    final rng = Random.secure();
    for (var i = 0; i < byteCount; i++) {
      out[i] = gesture[i % gesture.length] ^ rng.nextInt(256);
    }
    return out;
  }

  void reset() {
    _digest.reset();
    _samples = 0;
    _estimatedBits = 0;
    _lastX = double.nan;
    _lastY = double.nan;
  }
}
