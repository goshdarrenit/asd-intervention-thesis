import 'dart:math';
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flame/particles.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../base_scenario_game.dart';
import '../components/queue_visualizer.dart';
import '../difficulty_config.dart';
import '../telemetry_tracker.dart';

// ── Asset paths ────────────────────────────────────────────────────────────────

const _kBackground   = 'lib/assets/background/classroom_background.png';
const _kSpeechBubble = 'lib/assets/UI/speechbubble.png';

const _kAudioTick     = 'lib/assets/audio/patience/tick.mp3';
const _kAudioCollect  = 'lib/assets/audio/patience/collect.mp3';
const _kAudioEarlyTap = 'lib/assets/audio/patience/early_tap.mp3';
const _kAudioComplete = 'lib/assets/audio/patience/complete.mp3';

const _kStarColors = [
  Color(0xFFFFD700), Color(0xFFFF6B6B),
  Color(0xFF4FC3F7), Color(0xFFA5D6A7), Color(0xFFCE93D8),
];

/// Peer avatar paths per user type — never the same as the user's own type.
const _kPeersByUserType = {
  'boy_A': [
    'lib/assets/avatars/avatar_girl_A_1.png',
    'lib/assets/avatars/avatar_boy_B_1.png',
    'lib/assets/avatars/avatar_girl_B_1.png',
  ],
  'boy_B': [
    'lib/assets/avatars/avatar_boy_A_1.png',
    'lib/assets/avatars/avatar_girl_A_1.png',
    'lib/assets/avatars/avatar_girl_B_1.png',
  ],
  'girl_A': [
    'lib/assets/avatars/avatar_boy_A_1.png',
    'lib/assets/avatars/avatar_boy_B_1.png',
    'lib/assets/avatars/avatar_girl_B_1.png',
  ],
  'girl_B': [
    'lib/assets/avatars/avatar_boy_A_1.png',
    'lib/assets/avatars/avatar_boy_B_1.png',
    'lib/assets/avatars/avatar_girl_A_1.png',
  ],
};

const _kPathToAvatarType = {
  'avatar_boy_A': 'boy_A',
  'avatar_boy_B': 'boy_B',
  'avatar_girl_A': 'girl_A',
  'avatar_girl_B': 'girl_B',
};

// ── Helpers ────────────────────────────────────────────────────────────────────

String _avatarTypeFromKey(String key) {
  final parts = key.split('_');
  if (parts.length >= 3) return '${parts[1]}_${parts[2]}';
  return 'boy_A';
}

String _avatarTypeFromPath(String path) {
  for (final entry in _kPathToAvatarType.entries) {
    if (path.contains(entry.key)) return entry.value;
  }
  return 'boy_A';
}

Future<Sprite> _loadSprite(String path) async {
  final data = await rootBundle.load(path);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  return Sprite(frame.image);
}

// ── Game ──────────────────────────────────────────────────────────────────────

/// Classroom background
/// Real avatar sprites with idle-bob animation (user + peer)
/// Pulsing ring indicator highlights whoever's turn it is
/// Avatar happy/confused emotion swaps on correct tap / impulse violation
/// Star particle burst on each correct user turn
/// Audio: tick (AI turn), collect (correct tap), early_tap (impulse), fanfare (complete)
/// Well Done celebration banner
class TurnTakingGame extends BaseScenarioGame with TapCallbacks {
  late final TelemetryTracker _telemetry;
  late final Map<String, dynamic> _config;

  late final List<String> _queue;
  late final QueueVisualizer _queueVisualizer;
  int _currentTurnIndex = 0;
  int _impulseViolations = 0;
  bool _celebrationStarted = false;

  double _aiTurnDelaySeconds = 2.0;
  double _aiTurnTimer = 0.0;
  bool _isAiTurn = false;

  _TurnAvatarComponent? _userAvatar;
  _TurnAvatarComponent? _aiAvatar;
  _TurnRingComponent? _activeRing;
  final _rng = Random();

  TurnTakingGame({required super.config});

  @override
  Future<void> loadScenario() async {
    FlameAudio.audioCache.prefix = '';

    _telemetry = TelemetryTracker();
    _config = DifficultyConfig.getConfig(
      'turn_taking',
      config.difficulty,
      config.complexity,
    );

    final aiTurnDelayMs = _config['ai_turn_delay_ms'] as int;
    _aiTurnDelaySeconds = aiTurnDelayMs / 1000.0;
    final turnCount = _config['turn_count'] as int;

    // Build alternating turn queue: user, ai, user, ai, …
    _queue = [];
    for (int i = 0; i < turnCount; i++) {
      _queue.add(i % 2 == 0 ? 'user' : 'ai');
    }

    final w = size.x;
    final h = size.y;

    // ── Background ─────────────────────────────────────────────────────────────
    try {
      final bgSprite = await _loadSprite(_kBackground);
      add(SpriteComponent(
          sprite: bgSprite, size: size, anchor: Anchor.topLeft, priority: -1));
    } catch (_) {}

    // ── User avatar from prefs ─────────────────────────────────────────────────
    final prefs = await SharedPreferences.getInstance();
    final userAvatarKey = prefs.getString('selected_avatar') ?? 'avatar_boy_A_1';
    final userType = _avatarTypeFromKey(userAvatarKey);

    // ── Peer avatar (different type) ───────────────────────────────────────────
    final peerPool = List<String>.from(
      _kPeersByUserType[userType] ?? _kPeersByUserType['boy_A']!,
    )..shuffle(_rng);
    final peerPath = peerPool.first;
    final peerType = _avatarTypeFromPath(peerPath);

    // ── Level indicator ────────────────────────────────────────────────────────
    add(TextComponent(
      text: 'Level ${config.difficulty}',
      anchor: Anchor.center,
      position: Vector2(w / 2, 18),
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Color(0xFF757575),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    ));

    // ── Instruction ────────────────────────────────────────────────────────────
    // Speech bubble from user avatar gives the instruction; plain text fallback
    add(TextComponent(
      text: 'Tap when it\'s YOUR turn!',
      anchor: Anchor.center,
      position: Vector2(w / 2, 44),
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Color(0xFF1565C0),
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    ));

    // ── Queue visualizer ───────────────────────────────────────────────────────
    _queueVisualizer = QueueVisualizer(
      queue: _queue,
      position: Vector2(w / 2 - (_queue.length * 24), 96),
    );
    add(_queueVisualizer);

    // ── Avatars ────────────────────────────────────────────────────────────────
    const avW = 100.0;
    const avH = 128.0;
    final userPos = Vector2(w * 0.25, h * 0.56);
    final aiPos   = Vector2(w * 0.75, h * 0.56);

    _userAvatar = _TurnAvatarComponent(
      avatarPath: 'lib/assets/avatars/$userAvatarKey.png',
      avatarType: userType,
      label: 'YOU',
      labelColor: const Color(0xFF1565C0),
      position: userPos,
      size: Vector2(avW, avH),
    );
    add(_userAvatar!);

    _aiAvatar = _TurnAvatarComponent(
      avatarPath: peerPath,
      avatarType: peerType,
      label: 'FRIEND',
      labelColor: const Color(0xFFFF9800),
      position: aiPos,
      size: Vector2(avW, avH),
    );
    add(_aiAvatar!);

    // ── Speech bubble for user: short hint ────────────────────────────────────
    const bubbleW = 170.0;
    const bubbleH = 50.0;
    final bx = userPos.x + avW * 0.5 + 4;
    final by = userPos.y - avH * 0.38;
    try {
      final bubbleSprite = await _loadSprite(_kSpeechBubble);
      add(SpriteComponent(
        sprite: bubbleSprite,
        size: Vector2(bubbleW, bubbleH),
        anchor: Anchor.centerLeft,
        position: Vector2(bx, by),
        priority: 3,
      ));
    } catch (_) {}
    add(TextComponent(
      text: 'Wait for the blue ring!',
      anchor: Anchor.centerLeft,
      position: Vector2(bx + 15, by),
      priority: 4,
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Color(0xFF1565C0),
          fontSize: 12,
          fontWeight: FontWeight.bold,
          height: 1.3,
        ),
      ),
    ));

    // ── Active-turn ring (repositioned each turn) ─────────────────────────────
    _activeRing = _TurnRingComponent(
      ringSize: Vector2(avW + 22, avH + 22),
    );
    add(_activeRing!);

    _startNextTurn();
    overlays.add('HintOverlay');
  }

  // ── Turn logic ────────────────────────────────────────────────────────────

  void _startNextTurn() {
    if (_currentTurnIndex >= _queue.length) {
      _endGame();
      return;
    }

    _queueVisualizer.highlightTurn(_currentTurnIndex);
    final turn = _queue[_currentTurnIndex];

    if (turn == 'ai') {
      _activeRing?.moveTo(_aiAvatar!.position, const Color(0xFFFF9800));
      _aiAvatar?.showThinking();
      _isAiTurn = true;
      _aiTurnTimer = 0.0;
      _playAudio(_kAudioTick);
    } else {
      _activeRing?.moveTo(_userAvatar!.position, const Color(0xFF42A5F5));
      _userAvatar?.setIdle();
    }
  }

  void _advanceTurn() {
    _queueVisualizer.markComplete(_currentTurnIndex);
    _telemetry.recordAction('turn_complete', elapsedMs);
    _aiAvatar?.setIdle();
    _isAiTurn = false;
    _currentTurnIndex++;
    _startNextTurn();
  }

  void _endGame() {
    if (_celebrationStarted) return;
    _celebrationStarted = true;

    final success = _impulseViolations == 0;
    final reward  = (1.0 - _impulseViolations * 0.15).clamp(0.0, 1.0);

    _playAudio(_kAudioComplete);
    _activeRing?.removeFromParent();
    _userAvatar?.showHappy();

    if (success) {
      for (int i = 0; i < 3; i++) {
        Future.delayed(Duration(milliseconds: i * 220), () {
          _spawnStarBurst(Vector2(size.x * (0.25 + i * 0.25), size.y * 0.4));
        });
      }
    }

    add(_WellDoneBannerComponent(
      center: Vector2(size.x / 2, size.y / 2),
      subtitle: success ? 'Great turn-taking! 🎉' : 'Good effort! Keep trying! 👏',
      onDone: () {
        _telemetry.toJson()['impulse_violations'] = _impulseViolations;
        _telemetry.toJson()['queue_length'] = _queue.length;
        completeScenario(success, reward, telemetry: _telemetry.toJson());
      },
      priority: 20,
    ));
  }

  // ── Update loop ───────────────────────────────────────────────────────────

  @override
  void updateScenario(double dt) {
    if (_isAiTurn) {
      _aiTurnTimer += dt;
      if (_aiTurnTimer >= _aiTurnDelaySeconds) {
        _advanceTurn();
      }
    }
  }

  // ── Input ─────────────────────────────────────────────────────────────────

  void _dismissHint() {
    if (overlays.isActive('HintOverlay')) {
      overlays.remove('HintOverlay');
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (isComplete || _celebrationStarted) return;
    _dismissHint();

    final currentTurn = _queue[_currentTurnIndex];

    if (currentTurn == 'user') {
      _telemetry.recordAction('user_tap', elapsedMs);
      _userAvatar?.showHappy();
      _spawnStarBurst(_userAvatar!.position);
      _playAudio(_kAudioCollect);
      _advanceTurn();
    } else {
      _impulseViolations++;
      _telemetry.recordAction('impulse_violation', elapsedMs);
      _userAvatar?.showConfused();
      _playAudio(_kAudioEarlyTap);
    }
  }

  // ── Particles ─────────────────────────────────────────────────────────────

  void _spawnStarBurst(Vector2 origin) {
    add(ParticleSystemComponent(
      position: origin,
      priority: 10,
      particle: Particle.generate(
        count: 14,
        lifespan: 0.75,
        generator: (i) {
          final angle = (i / 14) * pi * 2 + _rng.nextDouble() * 0.35;
          final speed = 65.0 + _rng.nextDouble() * 55.0;
          return AcceleratedParticle(
            speed: Vector2(cos(angle) * speed, sin(angle) * speed),
            acceleration: Vector2(0, 75),
            child: ScalingParticle(
              to: 0,
              child: CircleParticle(
                radius: 4 + _rng.nextDouble() * 4,
                paint: Paint()
                  ..color = _kStarColors[_rng.nextInt(_kStarColors.length)],
              ),
            ),
          );
        },
      ),
    ));
  }

  void _playAudio(String path) {
    FlameAudio.play(path).catchError((_) => AudioPlayer());
  }
}

// ── Turn avatar component ─────────────────────────────────────────────────────

/// Self-contained avatar with idle-bob animation and emotion swaps.
class _TurnAvatarComponent extends PositionComponent {
  final String avatarPath;
  final String avatarType;
  final String label;
  final Color labelColor;

  SpriteComponent? _neutral;
  SpriteComponent? _confused;
  SpriteComponent? _happy;
  double _bobT = 0.0;

  _TurnAvatarComponent({
    required this.avatarPath,
    required this.avatarType,
    required this.label,
    required this.labelColor,
    required Vector2 position,
    required Vector2 size,
  }) : super(position: position, size: size, anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    try {
      final s = await _loadSprite(avatarPath);
      _neutral = SpriteComponent(
          sprite: s, size: size, anchor: Anchor.center, position: size / 2);
      add(_neutral!);
    } catch (_) {}

    for (final entry in {
      'confused': (SpriteComponent c) => _confused = c,
      'happy':    (SpriteComponent c) => _happy    = c,
    }.entries) {
      try {
        final s =
            await _loadSprite('lib/assets/emotion/${avatarType}_${entry.key}.png');
        final comp = SpriteComponent(
          sprite: s,
          size: size * 1.1,
          anchor: Anchor.center,
          position: size / 2,
        )..opacity = 0.0;
        add(comp);
        entry.value(comp);
      } catch (_) {}
    }

    // Label below avatar
    add(TextComponent(
      text: label,
      anchor: Anchor.topCenter,
      position: Vector2(size.x / 2, size.y + 6),
      textRenderer: TextPaint(
        style: TextStyle(
          color: labelColor,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          shadows: const [Shadow(color: Colors.black45, blurRadius: 4)],
        ),
      ),
    ));
  }

  @override
  void update(double dt) {
    super.update(dt);
    _bobT += dt * 1.5;
    final bob = sin(_bobT) * 3.5;
    for (final c in [_neutral, _confused, _happy]) {
      if (c != null) c.position.y = size.y / 2 + bob;
    }
  }

  void setIdle() {
    _neutral?.opacity = 1.0;
    _confused?.opacity = 0.0;
    _happy?.opacity = 0.0;
  }

  void showHappy() => _swapTo(_happy, autoResetMs: 1200);
  void showConfused() => _swapTo(_confused, autoResetMs: 1400);

  /// AI "thinking" face — stays until explicitly reset via setIdle()
  void showThinking() => _swapTo(_confused, autoResetMs: null);

  void _swapTo(SpriteComponent? target, {int? autoResetMs}) {
    _neutral?.opacity = 0.0;
    _confused?.opacity = 0.0;
    _happy?.opacity = 0.0;
    target?.opacity = 1.0;
    target?.add(ScaleEffect.to(
      Vector2.all(1.14),
      EffectController(duration: 0.2, reverseDuration: 0.2, curve: Curves.elasticOut),
    ));
    if (autoResetMs != null) {
      Future.delayed(Duration(milliseconds: autoResetMs), setIdle);
    }
  }
}

// ── Animated turn-ring indicator ──────────────────────────────────────────────

/// Pulsing rounded-rect ring that indicates whose turn it is.
class _TurnRingComponent extends PositionComponent {
  Color _color;
  double _t = 0.0;

  _TurnRingComponent({required Vector2 ringSize})
      : _color = const Color(0xFF42A5F5),
        super(size: ringSize, anchor: Anchor.center, priority: 2);

  void moveTo(Vector2 avatarCenter, Color color) {
    position = avatarCenter.clone();
    _color = color;
    _t = 0.0;
  }

  @override
  void update(double dt) => _t += dt * 3.0;

  @override
  void render(Canvas canvas) {
    final pulse = (sin(_t) + 1) / 2; // 0..1
    final alpha = (155 + pulse * 100).round().clamp(0, 255);
    final strokeW = 3.0 + pulse * 2.5;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: size.x, height: size.y),
        const Radius.circular(16),
      ),
      Paint()
        ..color = _color.withAlpha(alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW,
    );
  }
}

// ── Well Done banner ──────────────────────────────────────────────────────────

class _WellDoneBannerComponent extends PositionComponent {
  final VoidCallback onDone;
  final String subtitle;
  double _elapsed = 0.0;
  bool _doneFired = false;
  static const _kShow = 2.2;

  _WellDoneBannerComponent({
    required Vector2 center,
    required this.onDone,
    required this.subtitle,
    super.priority,
  }) : super(position: center, anchor: Anchor.center, size: Vector2(320, 160));

  @override
  void onLoad() {
    scale = Vector2.all(0.4);
    add(ScaleEffect.to(
      Vector2.all(1.0),
      EffectController(duration: 0.35, curve: Curves.elasticOut),
    ));
  }

  @override
  void update(double dt) {
    _elapsed += dt;
    if (!_doneFired && _elapsed >= _kShow) {
      _doneFired = true;
      onDone();
    }
  }

  @override
  void render(Canvas canvas) {
    final rect =
        Rect.fromCenter(center: Offset.zero, width: size.x, height: size.y);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(24)),
      Paint()..color = const Color(0xF01565C0),
    );

    void drawText(String text, TextStyle style, double dy) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: size.x - 24);
      tp.paint(canvas, Offset(-tp.width / 2, dy));
    }

    drawText(
      '🌟 Well Done! 🌟',
      const TextStyle(
        color: Colors.white,
        fontSize: 30,
        fontWeight: FontWeight.w900,
        shadows: [Shadow(color: Colors.black38, blurRadius: 6)],
      ),
      -size.y / 2 + 28,
    );
    drawText(
      subtitle,
      const TextStyle(
        color: Color(0xFFBBDEFB),
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
      10,
    );
  }
}
