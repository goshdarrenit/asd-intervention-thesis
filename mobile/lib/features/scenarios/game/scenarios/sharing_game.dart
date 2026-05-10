import 'dart:math';
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/particles.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../base_scenario_game.dart';
import '../components/draggable_item.dart';
import '../components/drop_target.dart';
import '../difficulty_config.dart';
import '../telemetry_tracker.dart';

// ── Asset pools ───────────────────────────────────────────────────────────────

const _kBackground = 'lib/assets/background/outdoor_background.png';

const _kAllItems = [
  'lib/assets/item/toys/toy_ball.png',
  'lib/assets/item/toys/toy_bear.png',
  'lib/assets/item/toys/toy_bear_2.png',
  'lib/assets/item/toys/toy_blocks.png',
  'lib/assets/item/toys/toy_blocks_2.png',
  'lib/assets/item/toys/toy_car.png',
  'lib/assets/item/toys/toy_robot.png',
  'lib/assets/item/toys/toy_tower.png',
  'lib/assets/item/sweets/sweet_blue_1.png',
  'lib/assets/item/sweets/sweet_blue_2.png',
  'lib/assets/item/sweets/sweet_brown_1.png',
  'lib/assets/item/sweets/sweet_purple_1.png',
  'lib/assets/item/sweets/sweet_red_1.png',
  'lib/assets/item/sweets/sweet_red_2.png',
  'lib/assets/item/sweets/sweet_yellow_1.png',
  'lib/assets/item/sweets/sweet_yellow_2.png',
];

// Peer avatar pool keyed by the user's avatar type — excludes user's own type.
const _kPeersByUserType = {
  'boy_A': [
    'lib/assets/avatars/avatar_boy_B_2.png',
    'lib/assets/avatars/avatar_girl_A_2.png',
    'lib/assets/avatars/avatar_girl_B_2.png',
  ],
  'boy_B': [
    'lib/assets/avatars/avatar_boy_A_2.png',
    'lib/assets/avatars/avatar_girl_A_2.png',
    'lib/assets/avatars/avatar_girl_B_2.png',
  ],
  'girl_A': [
    'lib/assets/avatars/avatar_boy_A_2.png',
    'lib/assets/avatars/avatar_boy_B_2.png',
    'lib/assets/avatars/avatar_girl_B_2.png',
  ],
  'girl_B': [
    'lib/assets/avatars/avatar_boy_A_2.png',
    'lib/assets/avatars/avatar_boy_B_2.png',
    'lib/assets/avatars/avatar_girl_A_2.png',
  ],
};

// Maps avatar asset path segment -> avatar type for emotion lookup.
// e.g. 'avatar_boy_B_2.png' -> 'boy_B'
const _kPathToAvatarType = {
  'avatar_boy_A': 'boy_A',
  'avatar_boy_B': 'boy_B',
  'avatar_girl_A': 'girl_A',
  'avatar_girl_B': 'girl_B',
};

const _kPeerNames = ['Alex', 'Sam', 'Jamie'];

// ── Audio ─────────────────────────────────────────────────────────────────────
// flame_audio uses AudioCache; we set prefix='' and pass full asset paths.
const _kAudioPickup  = 'lib/assets/audio/sharing/pickup_pop.mp3';
const _kAudioDrop    = 'lib/assets/audio/sharing/drop_ding.mp3';
const _kAudioMiss    = 'lib/assets/audio/sharing/missed_snare.mp3';
const _kAudioFanfare = 'lib/assets/audio/sharing/fanfare.mp3';

// Speech bubble image
const _kSpeechBubble = 'lib/assets/UI/speechbubble.png';

// Star burst colours for particle effects
const _kStarColors = [
  Color(0xFFFFD700),
  Color(0xFFFF6B6B),
  Color(0xFF4FC3F7),
  Color(0xFFA5D6A7),
  Color(0xFFCE93D8),
];

/// Derives the avatar type key (e.g. 'boy_A') from the stored avatar key
/// (e.g. 'avatar_boy_A_1').
String _avatarTypeFromKey(String key) {
  final parts = key.split('_'); // ['avatar', 'boy', 'A', '1']
  if (parts.length >= 3) return '${parts[1]}_${parts[2]}';
  return 'boy_A';
}

/// Derives avatar type from a full asset path such as
/// 'lib/assets/avatars/avatar_girl_B_2.png' -> 'girl_B'
String _avatarTypeFromPath(String path) {
  for (final entry in _kPathToAvatarType.entries) {
    if (path.contains(entry.key)) return entry.value;
  }
  return 'boy_A';
}

// ── Game ──────────────────────────────────────────────────────────────────────

/// Speech bubble instruction from the user avatar
/// Draggable items bounce gently and pop on pickup
/// Drop targets pulse with a glow ring
/// Peer happy-face reveals from emotion assets on delivery
/// Star particle burst on each successful delivery
/// Animated hint arrows after inactivity (difficulty ≤ 2)
/// In-canvas "Well Done!" celebration before OutcomeScreen
class SharingGame extends BaseScenarioGame {
  late final TelemetryTracker _telemetry;
  late final Map<String, dynamic> _config;

  final List<DraggableItem> _toys = [];
  final List<DropTarget> _peers = [];
  int _deliveredCount = 0;
  int _totalToys = 0;

  double? _timeLimitSeconds;
  double _elapsedTime = 0.0;

  // Hint system
  bool _hintsEnabled = false;
  double _idleTimer = 0.0;
  static const _kHintDelay = 3.5; // seconds of inactivity before hints appear
  final List<_HintArrowComponent> _hintArrows = [];
  bool _hintsVisible = false;

  // Celebration
  bool _celebrationStarted = false;

  final _rng = Random();

  SharingGame({required super.config});

  @override
  Future<void> loadScenario() async {
    _telemetry = TelemetryTracker();

    // Configure audio cache to use full asset paths
    FlameAudio.audioCache.prefix = '';

    _config = DifficultyConfig.getConfig(
      'sharing',
      config.difficulty,
      config.complexity,
    );

    final dragDistance = (_config['drag_distance'] as num).toDouble();
    _timeLimitSeconds = _config['time_limit_seconds'] != null
        ? (_config['time_limit_seconds'] as num).toDouble()
        : null;
    _totalToys = _config['toys'] as int;
    final numPeers = _config['peers'] as int;

    // Hints only for difficulty 1 and 2
    _hintsEnabled = config.difficulty <= 2;

    final gameWidth = size.x;
    final gameHeight = size.y;

    // ── Background ────────────────────────────────────────────────────────────
    final bgSprite = await _loadSprite(_kBackground);
    add(SpriteComponent(
      sprite: bgSprite,
      size: size,
      anchor: Anchor.topLeft,
      priority: -1,
    ));

    // ── Pick user avatar ──────────────────────────────────────────────────────
    final prefs = await SharedPreferences.getInstance();
    final userAvatarKey = prefs.getString('selected_avatar') ?? 'avatar_boy_A_1';
    final userType = _avatarTypeFromKey(userAvatarKey);

    // ── User avatar (far left) ────────────────────────────────────────────────
    const userAvatarW = 110.0;
    const userAvatarH = 140.0;
    final userAvatarX = gameWidth * 0.11;
    final userAvatarY = gameHeight / 2 - 20;

    final userSprite = await _loadSprite('lib/assets/avatars/$userAvatarKey.png');
    add(SpriteComponent(
      sprite: userSprite,
      size: Vector2(userAvatarW, userAvatarH),
      anchor: Anchor.center,
      position: Vector2(userAvatarX, userAvatarY),
      priority: 1,
    ));
    add(TextComponent(
      text: 'You',
      anchor: Anchor.topCenter,
      position: Vector2(userAvatarX, userAvatarY + userAvatarH / 2 - 4),
      priority: 2,
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
        ),
      ),
    ));

    // ── Speech bubble instruction ─────────────────────────────────────────────
    // Use the speechbubble.png asset; fall back to the drawn component if missing.
    try {
      final bubbleSprite = await _loadSprite(_kSpeechBubble);
      final bubbleW = gameWidth * 0.11;
      const bubbleH = 76.0;
      add(SpriteComponent(
        sprite: bubbleSprite,
        size: Vector2(bubbleW, bubbleH),
        anchor: Anchor.centerLeft,
        position: Vector2(userAvatarX + userAvatarW * 0.5 + 4, userAvatarY - 60),
        priority: 3,
      ));
      add(TextComponent(
        text: 'Share with your friends!',
        anchor: Anchor.centerLeft,
        position: Vector2(userAvatarX + userAvatarW * 0.5 + 19, userAvatarY - 60),
        priority: 4,
        textRenderer: TextPaint(
          style: TextStyle(
            color: const Color(0xFF1565C0),
            fontSize: bubbleH * 0.20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ));
    } catch (_) {
      // Asset missing — fall back to drawn bubble
      add(_SpeechBubbleComponent(
        text: 'Share with\nyour friends!',
        position: Vector2(userAvatarX + userAvatarW * 0.5 + 8, userAvatarY - 70),
        bubbleWidth: gameWidth * 0.38,
        bubbleHeight: 72,
        priority: 3,
      ));
    }

    // ── Pick peer avatars ─────────────────────────────────────────────────────
    final peerPool = List<String>.from(
      _kPeersByUserType[userType] ?? _kPeersByUserType['boy_A']!,
    )..shuffle(_rng);

    // ── Pick items randomly ───────────────────────────────────────────────────
    final itemPool = List<String>.from(_kAllItems)..shuffle(_rng);
    final selectedItems = itemPool.take(_totalToys).toList();

    // ── Item positions (centre column) ────────────────────────────────────────
    const itemSize = 110.0;
    final itemX = gameWidth * 0.31;
    final itemSpacing = (gameHeight - 80) / (_totalToys + 1);

    for (int i = 0; i < _totalToys; i++) {
      final yPos = 80 + itemSpacing * (i + 1) - itemSize / 2;
      final toy = DraggableItem(
        position: Vector2(itemX, yPos),
        size: Vector2(itemSize, itemSize),
        color: const Color(0xFF42A5F5),
        label: '',
        imagePath: selectedItems[i],
        onDropped: _onToyDropped,
        onPickedUp: () => _playAudio(_kAudioPickup),
      );
      _toys.add(toy);
      add(toy);
    }

    // ── Peer positions (right side) ───────────────────────────────────────────
    const peerW = 120.0;
    const peerH = 150.0;
    final peerX = (itemX + dragDistance).clamp(gameWidth * 0.55, gameWidth * 0.87);
    final peerSpacing = (gameHeight - 80) / (numPeers + 1);

    for (int i = 0; i < numPeers; i++) {
      final yPos = 80 + peerSpacing * (i + 1) - peerH / 2;
      final peerAvatarPath = peerPool[i % peerPool.length];
      final peer = DropTarget(
        position: Vector2(peerX, yPos),
        size: Vector2(peerW, peerH),
        color: const Color(0xFF4CAF50),
        label: _kPeerNames[i % _kPeerNames.length],
        acceptId: 'peer$i',
        imagePath: peerAvatarPath,
        avatarType: _avatarTypeFromPath(peerAvatarPath),
      );
      _peers.add(peer);
      add(peer);
    }

    // ── Progress stars strip ──────────────────────────────────────────────────
    add(_ProgressStarsComponent(
      total: _totalToys,
      position: Vector2(gameWidth / 2, gameHeight - 28),
      priority: 3,
    ));

    overlays.add('HintOverlay');
  }

  // ── Drop handling ─────────────────────────────────────────────────────────

  void _dismissHint() {
    if (overlays.isActive('HintOverlay')) {
      overlays.remove('HintOverlay');
    }
  }

  void _onToyDropped(DraggableItem toy, Vector2 dropPos) {
    _dismissHint();
    _telemetry.recordAction('drop', elapsedMs);
    _idleTimer = 0.0;

    for (final peer in _peers) {
      if (peer.checkDrop(dropPos, 95.0)) {
        if (!peer.isMatched) peer.markMatched();
        toy.removeFromParent();
        _toys.remove(toy);
        _deliveredCount++;

        // Update progress stars
        _updateProgressStars();

        // Star burst at drop position
        _spawnStarBurst(dropPos);
        _playAudio(_kAudioDrop);

        _telemetry.recordAction('deliver', elapsedMs);

        // Hide hints while items are being delivered successfully
        _setHintsVisible(false);

        if (_deliveredCount >= _totalToys) {
          _triggerCelebration();
        }
        return;
      }
    }

    toy.snapBack();
    _playAudio(_kAudioMiss);
    _telemetry.recordRetry();
  }

  // ── Audio ─────────────────────────────────────────────────────────────────

  void _playAudio(String path) {
    // Fire-and-forget; ignore errors (e.g. asset missing on simulator)
    FlameAudio.play(path).catchError((_) => AudioPlayer());
  }

  // ── Star particle burst ───────────────────────────────────────────────────

  void _spawnStarBurst(Vector2 origin) {
    add(ParticleSystemComponent(
      position: origin,
      priority: 10,
      particle: Particle.generate(
        count: 14,
        lifespan: 0.8,
        generator: (i) {
          final angle = (i / 14) * pi * 2 + _rng.nextDouble() * 0.4;
          final speed = 80.0 + _rng.nextDouble() * 60.0;
          final color = _kStarColors[_rng.nextInt(_kStarColors.length)];
          final startSize = 6.0 + _rng.nextDouble() * 6.0;
          return AcceleratedParticle(
            speed: Vector2(cos(angle) * speed, sin(angle) * speed),
            acceleration: Vector2(0, 80), // gravity
            child: CircleParticle(
              radius: startSize,
              paint: Paint()..color = color,
            ),
          );
        },
      ),
    ));
  }

  // ── Hint arrows ──────────────────────────────────────────────────────────

  void _rebuildHints() {
    for (final arrow in _hintArrows) {
      arrow.removeFromParent();
    }
    _hintArrows.clear();

    if (_toys.isEmpty || _peers.isEmpty) return;

    for (final toy in _toys) {
      // Point toward the nearest peer
      DropTarget? nearest;
      double bestDist = double.infinity;
      for (final peer in _peers) {
        final d = toy.position.distanceTo(peer.position);
        if (d < bestDist) {
          bestDist = d;
          nearest = peer;
        }
      }
      if (nearest == null) continue;

      final arrow = _HintArrowComponent(
        from: toy.position + Vector2(60, 0),
        to: nearest.position - Vector2(65, 0),
      );
      _hintArrows.add(arrow);
      add(arrow);
    }
  }

  void _setHintsVisible(bool visible) {
    if (_hintsVisible == visible) return;
    _hintsVisible = visible;
    if (visible) {
      _rebuildHints();
    } else {
      for (final arrow in _hintArrows) {
        arrow.removeFromParent();
      }
      _hintArrows.clear();
    }
  }

  // ── Progress stars ────────────────────────────────────────────────────────

  _ProgressStarsComponent? get _progressStars =>
      children.whereType<_ProgressStarsComponent>().firstOrNull;

  void _updateProgressStars() {
    _progressStars?.delivered = _deliveredCount;
  }

  // ── Celebration ───────────────────────────────────────────────────────────

  void _triggerCelebration() {
    if (_celebrationStarted) return;
    _celebrationStarted = true;

    _playAudio(_kAudioFanfare);

    // Spawn a big confetti rain then hand off to OutcomeScreen
    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 200), () {
        _spawnStarBurst(Vector2(size.x * (0.3 + i * 0.2), size.y * 0.4));
      });
    }

    add(_WellDoneBannerComponent(
      center: Vector2(size.x / 2, size.y / 2),
      onDone: () => completeScenario(true, 1.0, telemetry: _telemetry.toJson()),
      priority: 20,
    ));
  }

  // ── Update loop ───────────────────────────────────────────────────────────

  @override
  void updateScenario(double dt) {
    // Time limit
    if (_timeLimitSeconds != null) {
      _elapsedTime += dt;
      if (_elapsedTime >= _timeLimitSeconds!) {
        final reward = _deliveredCount / _totalToys * 0.5;
        completeScenario(false, reward, telemetry: _telemetry.toJson());
        return;
      }
    }

    // Hint system
    if (_hintsEnabled && _toys.isNotEmpty) {
      _idleTimer += dt;
      if (_idleTimer >= _kHintDelay && !_hintsVisible) {
        _setHintsVisible(true);
      }
    }
  }
}

// ── Speech bubble component ───────────────────────────────────────────────────

class _SpeechBubbleComponent extends PositionComponent {
  final String text;
  final double bubbleWidth;
  final double bubbleHeight;

  static const _kRadius = 14.0;
  static const _kTailW = 14.0;
  static const _kTailH = 18.0;
  static const _kPad = 12.0;

  _SpeechBubbleComponent({
    required this.text,
    required Vector2 position,
    required this.bubbleWidth,
    required this.bubbleHeight,
    super.priority,
  }) : super(position: position, size: Vector2(bubbleWidth, bubbleHeight));

  @override
  void render(Canvas canvas) {
    final w = bubbleWidth;
    final h = bubbleHeight;

    // Bubble body
    final bubblePath = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        const Radius.circular(_kRadius),
      ));
    canvas.drawPath(
      bubblePath,
      Paint()..color = const Color(0xF0FFFFFF),
    );

    // Left-pointing tail
    final tailPath = Path()
      ..moveTo(0, h / 2 - _kTailH / 2)
      ..lineTo(-_kTailW, h / 2)
      ..lineTo(0, h / 2 + _kTailH / 2)
      ..close();
    canvas.drawPath(tailPath, Paint()..color = const Color(0xF0FFFFFF));

    // Border
    final borderPaint = Paint()
      ..color = const Color(0xFF1565C0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        const Radius.circular(_kRadius),
      ),
      borderPaint,
    );

    // Text
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Color(0xFF1565C0),
          fontSize: 15,
          fontWeight: FontWeight.bold,
          height: 1.3,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: w - _kPad * 2);

    tp.paint(
      canvas,
      Offset(_kPad, (h - tp.height) / 2),
    );
  }
}

// ── Hint arrow component ──────────────────────────────────────────────────────

class _HintArrowComponent extends PositionComponent {
  final Vector2 from;
  final Vector2 to;
  double _t = 0.0;

  _HintArrowComponent({required this.from, required this.to})
      : super(priority: 5);

  @override
  void update(double dt) => _t += dt * 3.0;

  @override
  void render(Canvas canvas) {
    final pulse = (sin(_t) + 1) / 2; // 0..1
    final alpha = (140 + pulse * 115).round().clamp(0, 255);

    final paint = Paint()
      ..color = const Color(0xFFFFB300).withAlpha(alpha)
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final dx = to.x - from.x;
    final dy = to.y - from.y;
    final len = sqrt(dx * dx + dy * dy);
    if (len < 1) return;

    final ux = dx / len;
    final uy = dy / len;

    // Draw dashed animated line (marching ants effect)
    const dashLen = 12.0;
    const gapLen = 8.0;
    final offset = (pulse * (dashLen + gapLen)) % (dashLen + gapLen);
    double walked = -offset;
    while (walked < len) {
      final start = walked.clamp(0.0, len);
      final end = (walked + dashLen).clamp(0.0, len);
      if (end > start) {
        canvas.drawLine(
          Offset(from.x + ux * start, from.y + uy * start),
          Offset(from.x + ux * end, from.y + uy * end),
          paint,
        );
      }
      walked += dashLen + gapLen;
    }

    // Arrowhead
    const headLen = 16.0;
    const headAngle = 0.45;
    final tip = Offset(to.x, to.y);
    final leftX = tip.dx - headLen * (ux * cos(headAngle) - uy * sin(headAngle));
    final leftY = tip.dy - headLen * (uy * cos(headAngle) + ux * sin(headAngle));
    final rightX = tip.dx - headLen * (ux * cos(headAngle) + uy * sin(headAngle));
    final rightY = tip.dy - headLen * (uy * cos(headAngle) - ux * sin(headAngle));

    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(leftX, leftY)
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(rightX, rightY),
      paint..style = PaintingStyle.stroke,
    );
  }
}

// ── Progress stars component ──────────────────────────────────────────────────

class _ProgressStarsComponent extends PositionComponent {
  final int total;
  int delivered = 0;

  _ProgressStarsComponent({
    required this.total,
    required Vector2 position,
    super.priority,
  }) : super(position: position, anchor: Anchor.center);

  @override
  void render(Canvas canvas) {
    const starSize = 22.0;
    const gap = 6.0;
    final totalWidth = total * starSize + (total - 1) * gap;
    double x = -totalWidth / 2;

    for (int i = 0; i < total; i++) {
      final filled = i < delivered;
      _drawStar(
        canvas,
        Offset(x + starSize / 2, 0),
        starSize / 2,
        filled ? const Color(0xFFFFD700) : const Color(0x55FFFFFF),
        filled ? const Color(0xFFFF8F00) : const Color(0x33FFFFFF),
      );
      x += starSize + gap;
    }
  }

  void _drawStar(Canvas canvas, Offset center, double radius, Color fill, Color stroke) {
    const points = 5;
    final innerRadius = radius * 0.42;
    final path = Path();
    for (int i = 0; i < points * 2; i++) {
      final r = i.isEven ? radius : innerRadius;
      final angle = (i * pi / points) - pi / 2;
      final x = center.dx + r * cos(angle);
      final y = center.dy + r * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }
}

// ── Well Done banner ──────────────────────────────────────────────────────────

class _WellDoneBannerComponent extends PositionComponent {
  final VoidCallback onDone;
  double _elapsed = 0.0;
  bool _doneFired = false;
  static const _kDisplaySeconds = 2.2;

  _WellDoneBannerComponent({
    required Vector2 center,
    required this.onDone,
    super.priority,
  }) : super(position: center, anchor: Anchor.center, size: Vector2(320, 160));

  @override
  void onLoad() {
    // Animate in with a scale effect
    scale = Vector2.all(0.4);
    add(ScaleEffect.to(
      Vector2.all(1.0),
      EffectController(duration: 0.35, curve: Curves.elasticOut),
    ));
  }

  @override
  void update(double dt) {
    _elapsed += dt;
    if (!_doneFired && _elapsed >= _kDisplaySeconds) {
      _doneFired = true;
      onDone();
    }
  }

  @override
  void render(Canvas canvas) {
    // Panel
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: size.x,
      height: size.y,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(24)),
      Paint()..color = const Color(0xF01565C0),
    );

    // "Well Done!" text
    final tp1 = TextPainter(
      text: const TextSpan(
        text: '🌟 Well Done! 🌟',
        style: TextStyle(
          color: Colors.white,
          fontSize: 30,
          fontWeight: FontWeight.w900,
          shadows: [Shadow(color: Colors.black38, blurRadius: 6)],
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: size.x - 24);

    tp1.paint(
      canvas,
      Offset(-tp1.width / 2, -size.y / 2 + 28),
    );

    // Sub-text
    final tp2 = TextPainter(
      text: const TextSpan(
        text: 'Great sharing! 🎉',
        style: TextStyle(
          color: Color(0xFFBBDEFB),
          fontSize: 19,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: size.x - 24);

    tp2.paint(
      canvas,
      Offset(-tp2.width / 2, 10),
    );
  }
}

// ── Asset loader ──────────────────────────────────────────────────────────────

Future<Sprite> _loadSprite(String assetPath) async {
  final data = await rootBundle.load(assetPath);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  return Sprite(frame.image);
}
