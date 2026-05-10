import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Displays an emoji image representing an emotion.
/// Draggable by the user to match with a face card drop target.
class EmotionLabel extends PositionComponent with DragCallbacks {
  /// The emotion this emoji represents
  final String emotion;

  /// Callback when tile is dropped
  Function(EmotionLabel, Vector2)? onTileDropped;

  /// Original position for snap-back on wrong match
  late Vector2 _originalPosition;

  /// Maps emotion name to emoji asset filename (without extension)
  static const Map<String, String> _emojiFileMap = {
    'happy': 'happy_emoji',
    'sad': 'sad_emoji',
    'angry': 'anger_emoji',
    'confused': 'confused_emoji',
    'sorry': 'sorry_emoji',
  };

  EmotionLabel({
    required Vector2 position,
    required Vector2 size,
    required this.emotion,
    this.onTileDropped,
  }) : super(
          position: position,
          size: size,
          anchor: Anchor.center,
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _originalPosition = position.clone();

    // Background
    add(RectangleComponent(
      size: size,
      paint: Paint()
        ..color = const Color(0xFFFFF9C4)
        ..style = PaintingStyle.fill,
    ));

    // Border
    add(RectangleComponent(
      size: size,
      paint: Paint()
        ..color = const Color(0xFFF9A825)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    ));

    // Emoji image
    final fileName = _emojiFileMap[emotion] ?? 'happy_emoji';
    final path = 'lib/assets/emotion/$fileName.png';
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    add(SpriteComponent(
      sprite: Sprite(frame.image),
      size: Vector2(size.x - 10, size.y - 10),
      position: Vector2(5, 5),
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
    onTileDropped?.call(this, position.clone());
  }

  /// Snap back to original position
  void resetPosition() {
    position = _originalPosition.clone();
  }
}
