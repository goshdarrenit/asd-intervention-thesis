import 'dart:math';
import 'package:flutter/material.dart';
import '../game/base_scenario_game.dart';

/// HintOverlay — full-screen animated gesture hint
///
/// Displayed at the start of every scenario run to demonstrate the required
/// gesture.  Tap anywhere to dismiss immediately; the game files also dismiss
/// it on the first valid interaction.
///
/// Usage (registered in GameScreen's overlayBuilderMap):
///   overlays.add('HintOverlay');   // show
///   overlays.remove('HintOverlay'); // dismiss
class HintOverlay extends StatefulWidget {
  final BaseScenarioGame game;

  const HintOverlay({super.key, required this.game});

  @override
  State<HintOverlay> createState() => _HintOverlayState();
}

class _HintOverlayState extends State<HintOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _progress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (!mounted) return;
    widget.game.overlays.remove('HintOverlay');
  }

  String get _scenarioType => widget.game.config.scenarioType;

  String get _instructionText {
    switch (_scenarioType) {
      case 'sharing':
        return 'Swipe the toy to your friend!';
      case 'turn_taking':
        return 'Tap when it\'s YOUR turn!';
      case 'emotion_recognition':
        return 'Drag the emoji to the matching face!';
      case 'patience':
        return 'Wait for the glow, then tap!';
      default:
        return 'Follow the gesture!';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _dismiss(),
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: Colors.black54,
        child: Stack(
          children: [
            // Centered gesture animation
            Center(
              child: AnimatedBuilder(
                animation: _progress,
                builder: (context, _) => CustomPaint(
                  size: const Size(280, 280),
                  painter: _GesturePainter(
                    scenarioType: _scenarioType,
                    progress: _progress.value,
                  ),
                ),
              ),
            ),

            // Instruction text pinned to bottom
            Positioned(
              bottom: 48,
              left: 24,
              right: 24,
              child: Text(
                _instructionText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      color: Colors.black,
                      blurRadius: 6,
                      offset: Offset(1, 1),
                    ),
                  ],
                ),
              ),
            ),

            // Tap-to-skip label at top
            const Positioned(
              top: 48,
              left: 0,
              right: 0,
              child: Text(
                'Tap anywhere to skip',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  shadows: [
                    Shadow(
                      color: Colors.black,
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Gesture CustomPainter
// ---------------------------------------------------------------------------

class _GesturePainter extends CustomPainter {
  final String scenarioType;
  final double progress; // 0.0 – 1.0

  const _GesturePainter({
    required this.scenarioType,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    switch (scenarioType) {
      case 'sharing':
        _paintSharing(canvas, size);
      case 'turn_taking':
        _paintTurnTaking(canvas, size);
      case 'emotion_recognition':
        _paintEmotionRecognition(canvas, size);
      case 'patience':
        _paintPatience(canvas, size);
      default:
        _paintSharing(canvas, size); // fallback
    }
  }

  // ─── sharing: swipe finger left -> right ────────────────────────────────

  void _paintSharing(Canvas canvas, Size size) {
    const color = Color(0xFFFFB300); // amber
    final tipX = 60.0 + progress * 160.0;
    const tipY = 140.0;
    final tip = Offset(tipX, tipY);

    // Draw arc trail behind the finger
    if (progress > 0.05) {
      final trailPaint = Paint()
        ..color = color.withAlpha(((1 - progress) * 120).round().clamp(0, 120))
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final path = Path()
        ..moveTo(60, tipY)
        ..lineTo(tipX - 10, tipY);
      canvas.drawPath(path, trailPaint);
    }

    final paint = Paint()..color = color;
    // _drawFinger(canvas, paint, tip, 1.0);
    _drawEmojiFinger(canvas, tip, 1.0);
  }

  // ─── turn_taking: tap finger on centre circle ──────────────────────────

  void _paintTurnTaking(Canvas canvas, Size size) {
    const color = Color(0xFF42A5F5); // blue
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Pulsing target circle
    final pulse = sin(progress * pi);
    final circlePaint = Paint()
      ..color = color.withAlpha(60)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), 50 + pulse * 10, circlePaint);

    final circleBorder = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(Offset(cx, cy), 50 + pulse * 10, circleBorder);

    // Finger taps down toward center then lifts
    final fingerOffsetY = -(1 - pulse) * 40; // descends then rises
    final tip = Offset(cx, cy - 20 + fingerOffsetY);
    final paint = Paint()..color = color;
    // _drawFinger(canvas, paint, tip, 1.0);
    _drawEmojiFinger(canvas, tip, 1.0);

  }

  // ─── emotion_recognition: drag finger from face area to emoji ──────────

  void _paintEmotionRecognition(Canvas canvas, Size size) {
    const color = Color(0xFF26A69A); // teal
    final tipX = 70.0 + progress * 130.0;
    final tipY = 80.0 + progress * 120.0;
    final tip = Offset(tipX, tipY);

    // Dashed trail
    if (progress > 0.05) {
      final trailPaint = Paint()
        ..color = color.withAlpha(160)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      _drawDashedLine(canvas, const Offset(70, 80), tip, trailPaint, 8, 5);
    }

    final paint = Paint()..color = color;
    _drawEmojiFinger(canvas, tip, 1.0);
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
    double dashLen,
    double gapLen,
  ) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final dist = sqrt(dx * dx + dy * dy);
    if (dist == 0) return;
    final stepX = dx / dist;
    final stepY = dy / dist;

    double traveled = 0;
    bool drawing = true;
    var cur = start;

    while (traveled < dist) {
      final segLen = drawing ? dashLen : gapLen;
      final next = traveled + segLen;
      final clampedNext = next > dist ? dist : next;
      final nextPt = Offset(
        start.dx + stepX * clampedNext,
        start.dy + stepY * clampedNext,
      );
      if (drawing) canvas.drawLine(cur, nextPt, paint);
      cur = nextPt;
      traveled = clampedNext;
      drawing = !drawing;
    }
  }

  void _drawEmojiFinger(Canvas canvas, Offset center, double scale) {
    final textPainter = TextPainter(
      text: const TextSpan(
        text: '👆',
        style: TextStyle(fontSize: 34),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );
  }

  // ─── patience: palm hold -> finger tap ──────────────────────────────────

  void _drawPalmEmoji(Canvas canvas, Offset center, double scale) {
    final textPainter = TextPainter(
      text: const TextSpan(
        text: '🖐️',
        style: TextStyle(fontSize: 42),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );
  }

  void _paintPatience(Canvas canvas, Size size) {
    const palmColor = Color(0xFFFF7043); // deep orange
    const fingerColor = Color(0xFFFFB300); // amber

    final cx = size.width / 2;
    final cy = size.height / 2;

    if (progress < 0.5) {
      final floatY = sin(progress * pi * 4) * 4;
      final center = Offset(cx, cy + floatY);
      _drawPalmEmoji(canvas, center, 1.0);
    } else {
      final palmOpacity = ((0.7 - progress) / 0.2).clamp(0.0, 1.0);
      if (palmOpacity > 0) {
        // _drawPalm(canvas, Paint(), Offset(cx, cy), palmOpacity, palmColor);
        _drawPalmEmoji(canvas, Offset(cx, cy), 1.0);
      }

      final fingerOpacity = ((progress - 0.6) / 0.2).clamp(0.0, 1.0);
      if (fingerOpacity > 0) {
        final fingerY = progress < 0.8
            ? 80.0
            : 80.0 + ((progress - 0.8) / 0.2) * 80.0; // taps downward
        final tip = Offset(cx, fingerY);
        final paint = Paint()..color = fingerColor.withAlpha((fingerOpacity * 255).round());
        _drawEmojiFinger(canvas, tip, 1.0);
      }
    }
  }

  // ─── Drawing helpers ────────────────────────────────────────────────────

  void _drawFinger(Canvas canvas, Paint paint, Offset tip, double scale) {
    // Filled oval for index finger
    canvas.drawOval(
      Rect.fromCenter(
        center: tip,
        width: 22 * scale,
        height: 36 * scale,
      ),
      paint,
    );
    // Small circle highlight at fingertip
    final highlightPaint = Paint()..color = Colors.white.withAlpha(160);
    canvas.drawCircle(
      Offset(tip.dx, tip.dy - 10 * scale),
      4 * scale,
      highlightPaint,
    );
  }

  void _drawPalm(
    Canvas canvas,
    Paint _,
    Offset center,
    double opacity,
    Color color,
  ) {
    final paint = Paint()..color = color.withAlpha((opacity * 255).round());
    final fingerWidth = 14.0;
    final fingerHeight = 40.0;
    final palmWidth = 70.0;
    final palmHeight = 30.0;

    // 5 fingers above palm base
    final fingerSpacing = palmWidth / 4;
    for (int i = 0; i < 5; i++) {
      final fx = center.dx - palmWidth / 2 + i * fingerSpacing;
      final fy = center.dy - palmHeight / 2 - fingerHeight / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(fx, fy),
            width: fingerWidth,
            height: fingerHeight,
          ),
          const Radius.circular(7),
        ),
        paint,
      );
    }

    // Palm base
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center,
          width: palmWidth,
          height: palmHeight,
        ),
        const Radius.circular(10),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_GesturePainter old) =>
      old.progress != progress || old.scenarioType != scenarioType;
}
