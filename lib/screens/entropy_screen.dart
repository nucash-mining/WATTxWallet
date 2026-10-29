import 'package:flutter/material.dart';

import '../services/touch_entropy.dart';

/// Drag-to-generate: the user smears a finger around the pad and the movement
/// is folded into the seed.
///
/// The copy is deliberately honest about what this does. The gesture is mixed
/// with the platform CSPRNG rather than replacing it, so a lazy scribble cannot
/// produce a weak wallet — telling the user their finger *is* the randomness
/// would be a lie, and would invite them to distrust a wallet made with a short
/// gesture.
class EntropyScreen extends StatefulWidget {
  const EntropyScreen({super.key});

  @override
  State<EntropyScreen> createState() => _EntropyScreenState();
}

class _EntropyScreenState extends State<EntropyScreen> {
  final TouchEntropy _entropy = TouchEntropy();
  final List<Offset> _trail = [];

  void _sample(Offset p, double pressure) {
    _entropy.add(p.dx, p.dy, pressure);
    setState(() {
      _trail.add(p);
      if (_trail.length > 120) _trail.removeAt(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pct = (_entropy.progress * 100).round();
    return Scaffold(
      appBar: AppBar(title: const Text('Create your wallet')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Draw on the pad below.',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your movement is mixed into the randomness that creates your '
              'recovery phrase. It is combined with the device\'s secure '
              'random generator, never used on its own, so your wallet is '
              'strong either way — this only adds to it.',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Listener(
                onPointerDown: (e) => _sample(e.localPosition, e.pressure),
                onPointerMove: (e) => _sample(e.localPosition, e.pressure),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF11151C),
                    border: Border.all(
                      color: _entropy.isComplete
                          ? const Color(0xFF3FB950)
                          : Colors.white24,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: CustomPaint(
                    painter: _TrailPainter(_trail),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _entropy.progress, minHeight: 8),
            const SizedBox(height: 8),
            Text(
              _entropy.isComplete
                  ? 'Enough collected — you can continue.'
                  : '$pct%  ·  ${_entropy.sampleCount} samples',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
            const SizedBox(height: 12),
            FilledButton(
              // Returning the collector rather than a seed keeps key creation in
              // the store, so the screen never holds the phrase.
              onPressed: _entropy.isComplete
                  ? () => Navigator.of(context).pop(_entropy)
                  : null,
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrailPainter extends CustomPainter {
  final List<Offset> points;
  _TrailPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < points.length; i++) {
      // Fade the tail so the pad reads as "keep going" rather than a drawing.
      paint.color = const Color(0xFF3FB950).withOpacity(i / points.length);
      canvas.drawLine(points[i - 1], points[i], paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TrailPainter old) => true;
}
