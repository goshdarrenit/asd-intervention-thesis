import 'dart:math';
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Pulsing glow ring while waiting for a drop
/// Happy face reveal (from emotion assets) on match, with a pop animation
class DropTarget extends PositionComponent {
  final Color color;
  final String label;
  final String acceptId;

  /// Optional avatar image asset path (e.g. avatars/avatar_boy_A_2.png).
  final String? imagePath;

  /// Avatar type key (e.g. 'boy_A', 'girl_B') used to load the happy emotion.
  final String? avatarType;

  bool isMatched = false;

  late RectangleComponent _background;
  late TextComponent _textComponent;
  SpriteComponent? _avatarSprite;
  SpriteComponent? _happySprite;
  _GlowRingComponent? _glowRing;

  DropTarget({
    required Vector2 position,
    required Vector2 size,
    required this.color,
    required this.label,
    required this.acceptId,
    this.imagePath,
    this.avatarType,
  }) : super(position: position, size: size, anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Pulsing glow ring (behind everything)
    _glowRing = _GlowRingComponent(size: size, color: color);
    add(_glowRing!);

    // Drop-zone highlight
    _background = RectangleComponent(
      size: size,
      paint: Paint()
        ..color = color.withAlpha(30)
        ..style = PaintingStyle.fill,
    );
    add(_background);

    if (imagePath != null) {
      final sprite = await _loadSprite(imagePath!);
      final avatarSize = Vector2(size.x * 0.85, size.y * 0.72);
      _avatarSprite = SpriteComponent(
        sprite: sprite,
        size: avatarSize,
        anchor: Anchor.topCenter,
        position: Vector2(size.x / 2, 4),
      );
      add(_avatarSprite!);

      // Pre-load the happy face sprite (hidden initially)
      if (avatarType != null) {
        final happyPath = 'lib/assets/emotion/${avatarType}_happy.png';
        try {
          final happySprite = await _loadSprite(happyPath);
          _happySprite = SpriteComponent(
            sprite: happySprite,
            size: avatarSize * 1.15,
            anchor: Anchor.topCenter,
            position: Vector2(size.x / 2, -4),
          )..opacity = 0.0;
          add(_happySprite!);
        } catch (_) {
          // Happy asset missing — degrade gracefully
        }
      }
    }

    // Name label at bottom
    _textComponent = TextComponent(
      text: label,
      anchor: Anchor.bottomCenter,
      position: Vector2(size.x / 2, size.y - 2),
      textRenderer: TextPaint(
        style: TextStyle(
          color: imagePath != null ? Colors.white : color,
          fontSize: 15,
          fontWeight: FontWeight.bold,
          shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
        ),
      ),
    );
    add(_textComponent);
  }

  bool checkDrop(Vector2 dropPos, double threshold) =>
      position.distanceTo(dropPos) <= threshold;

  void markMatched() {
    isMatched = true;
    _glowRing?.stopPulsing();

    // Green success background
    _background.paint = Paint()
      ..color = Colors.green.withAlpha(80)
      ..style = PaintingStyle.fill;

    // Reveal happy face with a pop scale effect
    if (_happySprite != null && _avatarSprite != null) {
      _avatarSprite!.add(
        OpacityEffect.to(0.0, EffectController(duration: 0.15)),
      );
      _happySprite!.opacity = 1.0;
      _happySprite!.scale = Vector2.all(0.6);
      _happySprite!.add(
        ScaleEffect.to(
          Vector2.all(1.0),
          EffectController(duration: 0.25, curve: Curves.elasticOut),
        ),
      );
    } else {
      // Fallback: just colour the background
      _textComponent.textRenderer = TextPaint(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
        ),
      );
    }
  }
}

// ── Glow ring ────────────────────────────────────────────────────────────────

class _GlowRingComponent extends PositionComponent {
  final Color color;
  double _t = 0.0;
  bool _active = true;

  _GlowRingComponent({required Vector2 size, required this.color})
      : super(size: size);

  void stopPulsing() => _active = false;

  @override
  void update(double dt) {
    if (_active) _t += dt * 2.0;
  }

  @override
  void render(Canvas canvas) {
    if (!_active) return;
    final pulse = (sin(_t) + 1) / 2; // 0..1
    final alpha = (60 + pulse * 120).round(); // 60..180
    final expansion = pulse * 6.0; // 0..6 px outward

    final rect = Rect.fromLTWH(
      -expansion,
      -expansion,
      size.x + expansion * 2,
      size.y + expansion * 2,
    );
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(14));

    canvas.drawRRect(
      rr,
      Paint()
        ..color = color.withAlpha(alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5,
    );
  }
}

// ── Asset loader ─────────────────────────────────────────────────────────────

Future<Sprite> _loadSprite(String assetPath) async {
  final data = await rootBundle.load(assetPath);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  return Sprite(frame.image);
}
