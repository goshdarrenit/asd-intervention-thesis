import 'dart:math';
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Idle bounce: sprite child bobs gently when not being dragged
/// Pickup pop: brief scale-up when drag starts, restores on release
/// Snap-back: item returns to origin when dropped on invalid target
class DraggableItem extends PositionComponent with DragCallbacks {
  final Color color;
  final String label;

  /// Optional asset path for an image sprite (e.g. toy/sweet PNG).
  final String? imagePath;

  int dragCount = 0;
  int totalPauseTimeMs = 0;
  Function(DraggableItem, Vector2)? onDropped;
  VoidCallback? onPickedUp;

  bool get isDragging => _isDragging;

  late final Vector2 _originalPosition;
  int? _lastDragEndMs;
  bool _isDragging = false;

  // Bounce animation
  double _bounceT = 0.0;
  SpriteComponent? _spriteChild;

  DraggableItem({
    required Vector2 position,
    required Vector2 size,
    required this.color,
    required this.label,
    this.imagePath,
    this.onDropped,
    this.onPickedUp,
  }) : super(position: position, size: size, anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _originalPosition = position.clone();

    if (imagePath != null) {
      final sprite = await _loadSprite(imagePath!);
      _spriteChild = SpriteComponent(
        sprite: sprite,
        size: size,
        anchor: Anchor.topLeft,
      );
      add(_spriteChild!);
    } else {
      add(RectangleComponent(
        size: size,
        paint: Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      ));
      add(TextComponent(
        text: label,
        anchor: Anchor.center,
        position: size / 2,
        textRenderer: TextPaint(
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ));
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    // Gentle idle bounce on the sprite child only (doesn't affect drag hitbox)
    if (!_isDragging && _spriteChild != null) {
      _bounceT += dt * 2.5; // ~0.4s per cycle
      final offsetY = sin(_bounceT) * 4.0;
      _spriteChild!.position.y = offsetY;
    }
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    dragCount++;
    if (_lastDragEndMs != null) {
      final pauseMs = DateTime.now().millisecondsSinceEpoch - _lastDragEndMs!;
      if (pauseMs > 500) totalPauseTimeMs += pauseMs;
    }
    _isDragging = true;
    priority = 100;
    onPickedUp?.call();

    // Reset sprite child offset so it doesn't jump
    _spriteChild?.position.y = 0;

    // Pop scale effect on pickup
    add(ScaleEffect.to(
      Vector2.all(1.18),
      EffectController(duration: 0.12, curve: Curves.easeOut),
    ));
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    super.onDragUpdate(event);
    position.add(event.localDelta);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    _lastDragEndMs = DateTime.now().millisecondsSinceEpoch;
    _isDragging = false;
    priority = 0;

    // Restore scale
    add(ScaleEffect.to(
      Vector2.all(1.0),
      EffectController(duration: 0.1, curve: Curves.easeIn),
    ));

    if (onDropped != null) onDropped!(this, position.clone());
  }

  void snapBack() {
    position = _originalPosition.clone();
    _bounceT = 0.0;
  }
}

Future<Sprite> _loadSprite(String assetPath) async {
  final data = await rootBundle.load(assetPath);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  return Sprite(frame.image);
}
