import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Displays an avatar face expressing a specific emotion.
/// Acts as a static drop target for emoji tiles.
class FaceCard extends PositionComponent {
  /// The emotion this face is expressing
  final String emotion;

  /// Avatar type to display (e.g., 'girl_A', 'boy_B') — never the user's own type
  final String avatarType;

  /// Whether this face has been matched with the correct emoji
  bool isMatched = false;

  late RectangleComponent _background;

  FaceCard({
    required Vector2 position,
    required Vector2 size,
    required this.emotion,
    required this.avatarType,
  }) : super(
          position: position,
          size: size,
          anchor: Anchor.center,
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Background
    _background = RectangleComponent(
      size: size,
      paint: Paint()
        ..color = const Color(0xFFE3F2FD)
        ..style = PaintingStyle.fill,
    );
    add(_background);

    // Border
    add(RectangleComponent(
      size: size,
      paint: Paint()
        ..color = const Color(0xFF1565C0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0,
    ));

    // Avatar face image
    final path = 'lib/assets/emotion/${avatarType}_$emotion.png';
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    add(SpriteComponent(
      sprite: Sprite(frame.image),
      size: Vector2(size.x - 8, size.y - 8),
      position: Vector2(4, 4),
    ));
  }

  /// Mark this face as matched and highlight it green
  void markMatched() {
    isMatched = true;
    _background.paint = Paint()
      ..color = const Color(0xFF81C784)
      ..style = PaintingStyle.fill;
  }
}
