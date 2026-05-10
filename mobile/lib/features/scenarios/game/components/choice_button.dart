import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';

/// Large touch target 
/// Rounded rectangle with centered text
/// Visual feedback on tap (brief scale animation)
/// ASD-friendly: calm colors, clear text, no time pressure indicators
class ChoiceButton extends PositionComponent with TapCallbacks {
  /// Button label text
  final String text;

  /// Background color
  final Color color;

  /// Callback when button is tapped
  final VoidCallback onTap;

  /// Rectangle component for button background
  late final RectangleComponent _background;

  /// Text component for button label
  late final TextComponent _label;

  ChoiceButton({
    required this.text,
    required Vector2 position,
    required Vector2 size,
    this.color = const Color(0xFF42A5F5),
    required this.onTap,
  }) : super(
          position: position,
          size: size,
          anchor: Anchor.center,
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Rounded rectangle background — topLeft anchor fills the component bounds
    _background = RectangleComponent(
      size: size,
      paint: Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
    add(_background);

    // Centered text label — position at size/2 (centre of local space)
    _label = TextComponent(
      text: text,
      anchor: Anchor.center,
      position: size / 2,
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    add(_label);
  }

  @override
  void onTapDown(TapDownEvent event) {
    // Scale down slightly for visual feedback
    scale = Vector2.all(0.95);
  }

  @override
  void onTapUp(TapUpEvent event) {
    scale = Vector2.all(1.0);
    onTap();
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    scale = Vector2.all(1.0);
  }
}
