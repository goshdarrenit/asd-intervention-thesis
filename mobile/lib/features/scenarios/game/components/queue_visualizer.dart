import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// Blue circles = user turns
/// Orange circles = AI turns
/// Highlighted circle = current turn (enlarged, outlined)
/// Grayed out circles = completed turns
class QueueVisualizer extends PositionComponent {
  /// Queue of turn owners: ['user', 'ai', 'user', 'ai', ...]
  final List<String> queue;

  /// Track completed turns for graying out
  final Set<int> _completedTurns = {};

  /// Circle components for each queue slot
  final List<CircleComponent> _circles = [];

  /// Circle radius
  static const double _radius = 18.0;

  /// Spacing between circles
  static const double _spacing = 12.0;

  QueueVisualizer({
    required this.queue,
    required super.position,
  }) : super(
          anchor: Anchor.topLeft,
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Create circle for each turn in queue
    for (int i = 0; i < queue.length; i++) {
      final turnOwner = queue[i];
      final xPos = i * (_radius * 2 + _spacing);

      final color = turnOwner == 'user'
          ? const Color(0xFF42A5F5) // Blue for user
          : const Color(0xFFFF9800); // Orange for AI

      final circle = CircleComponent(
        radius: _radius,
        paint: Paint()..color = color,
        position: Vector2(xPos, 0),
        anchor: Anchor.topLeft,
      );

      _circles.add(circle);
      add(circle);
    }
  }

  /// Highlight the current turn (enlarge and outline)
  void highlightTurn(int index) {
    if (index < 0 || index >= _circles.length) return;

    // Reset all circles to normal size
    for (var circle in _circles) {
      circle.radius = _radius;
      circle.paint.strokeWidth = 0;
      circle.paint.style = PaintingStyle.fill;
    }

    // Highlight current turn
    final currentCircle = _circles[index];
    currentCircle.radius = _radius * 1.3; // Enlarge
    currentCircle.paint
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..color = queue[index] == 'user'
          ? const Color(0xFF1565C0) // Darker blue outline
          : const Color(0xFFF57C00); // Darker orange outline
  }

  /// Mark a turn as complete (gray it out)
  void markComplete(int index) {
    if (index < 0 || index >= _circles.length) return;

    _completedTurns.add(index);

    final circle = _circles[index];
    circle.radius = _radius; // Reset to normal size
    circle.paint
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFBDBDBD); // Gray
  }
}
