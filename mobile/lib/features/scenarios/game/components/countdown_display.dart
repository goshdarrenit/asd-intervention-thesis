import 'dart:math' as math;
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/material.dart';

/// Visual enhancements:
/// - Gradient ring colour: cool blue -> warm orange -> gold as time runs out
/// - Number pulses on each of the final 3 ticks for anticipation
/// - White flash on completion
/// - [onTick] callback fires every whole second (used for tick audio)
class CountdownDisplay extends PositionComponent {
  final int totalSeconds;
  final VoidCallback onComplete;

  /// Optional: called once per whole second (for tick SFX).
  final VoidCallback? onTick;

  late int remainingSeconds;
  double _elapsedSeconds = 0.0;
  bool _isComplete = false;

  // Flash overlay fades in on complete then fades out
  double _flashAlpha = 0.0;
  bool _flashFadingOut = false;

  late final TextComponent _numberText;
  late final double _radius;

  CountdownDisplay({
    required Vector2 position,
    required this.totalSeconds,
    required this.onComplete,
    this.onTick,
  }) : super(position: position, anchor: Anchor.center) {
    remainingSeconds = totalSeconds;
    _radius = 70.0;
    size = Vector2.all(_radius * 2);
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _numberText = TextComponent(
      text: '$remainingSeconds',
      anchor: Anchor.center,
      position: size / 2,
      textRenderer: TextPaint(
        style: TextStyle(
          color: _progressColor(0),
          fontSize: 54,
          fontWeight: FontWeight.w900,
          shadows: const [Shadow(color: Colors.black26, blurRadius: 6)],
        ),
      ),
    );
    add(_numberText);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_isComplete) {
      // Fade out flash overlay
      if (_flashFadingOut && _flashAlpha > 0) {
        _flashAlpha = (_flashAlpha - dt * 2.5).clamp(0.0, 1.0);
      }
      return;
    }

    _elapsedSeconds += dt;

    final newRemaining = (totalSeconds - _elapsedSeconds.floor()).clamp(0, totalSeconds);
    if (newRemaining != remainingSeconds) {
      remainingSeconds = newRemaining;
      _numberText.text = '$remainingSeconds';
      _updateNumberColor();
      onTick?.call();

      // Pulse the number on final 3 seconds
      if (remainingSeconds <= 3 && remainingSeconds > 0) {
        _numberText.children.whereType<ScaleEffect>().forEach((e) => e.removeFromParent());
        _numberText.add(ScaleEffect.to(
          Vector2.all(1.35),
          EffectController(duration: 0.12, reverseDuration: 0.12, curve: Curves.easeOut),
        ));
      }
    }

    if (_elapsedSeconds >= totalSeconds && !_isComplete) {
      _isComplete = true;
      remainingSeconds = 0;
      _numberText.text = '✓';
      _updateNumberColor();
      _flashAlpha = 1.0;
      _flashFadingOut = true;
      onComplete();
    }
  }

  void _updateNumberColor() {
    final progress = _isComplete ? 1.0 : (_elapsedSeconds / totalSeconds).clamp(0.0, 1.0);
    _numberText.textRenderer = TextPaint(
      style: TextStyle(
        color: _progressColor(progress),
        fontSize: 54,
        fontWeight: FontWeight.w900,
        shadows: const [Shadow(color: Colors.black26, blurRadius: 6)],
      ),
    );
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final progress = _isComplete
        ? 1.0
        : math.min(1.0, _elapsedSeconds / totalSeconds);

    final center = Offset(_radius, _radius);
    final ringColor = _progressColor(progress);

    // Track ring (faint)
    canvas.drawCircle(
      center,
      _radius - 5,
      Paint()
        ..color = ringColor.withAlpha(50)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12.0,
    );

    // Progress arc
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: _radius - 5),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        Paint()
          ..color = ringColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12.0
          ..strokeCap = StrokeCap.round,
      );
    }

    // White flash on completion
    if (_flashAlpha > 0) {
      canvas.drawCircle(
        center,
        _radius,
        Paint()..color = Colors.white.withAlpha((_flashAlpha * 200).round()),
      );
    }
  }

  /// Interpolates blue -> orange -> gold as progress goes 0->1.
  Color _progressColor(double progress) {
    if (progress < 0.5) {
      return Color.lerp(
        const Color(0xFF64B5F6), // light blue
        const Color(0xFFFFB74D), // orange
        progress * 2,
      )!;
    } else {
      return Color.lerp(
        const Color(0xFFFFB74D), // orange
        const Color(0xFFFFD700), // gold
        (progress - 0.5) * 2,
      )!;
    }
  }
}
