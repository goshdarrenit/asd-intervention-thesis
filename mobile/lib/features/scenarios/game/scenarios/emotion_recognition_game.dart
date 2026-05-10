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
import '../components/face_card.dart';
import '../components/emotion_label.dart';
import '../difficulty_config.dart';
import '../telemetry_tracker.dart';

// ── Asset paths ────────────────────────────────────────────────────────────────

const _kBackground   = 'lib/assets/background/classroom_background_2.png';
const _kSpeechBubble = 'lib/assets/UI/speechbubble.png';

const _kAudioCorrect = 'lib/assets/audio/sharing/drop_ding.mp3';
const _kAudioWrong   = 'lib/assets/audio/sharing/missed_snare.mp3';
const _kAudioFanfare = 'lib/assets/audio/sharing/fanfare.mp3';

const _kStarColors = [
  Color(0xFFFFD700), Color(0xFFFF6B6B),
  Color(0xFF4FC3F7), Color(0xFFA5D6A7), Color(0xFFCE93D8),
];

/// Avatar types available for face display, keyed by the user's own type.
/// The game always shows a face that is NOT the user's own avatar type.
const _kFaceTypesByUserType = {
  'boy_A': ['girl_A', 'boy_B', 'girl_B'],
  'boy_B': ['boy_A', 'girl_A', 'girl_B'],
  'girl_A': ['boy_A', 'boy_B', 'girl_B'],
  'girl_B': ['boy_A', 'boy_B', 'girl_A'],
};

// ── Helpers ────────────────────────────────────────────────────────────────────

String _avatarTypeFromKey(String key) {
  final parts = key.split('_');
  if (parts.length >= 3) return '${parts[1]}_${parts[2]}';
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
/// User avatar (idle bob) with speech bubble instruction
/// Star particle burst on each correct match
/// Avatar happy/confused reaction on correct/wrong
/// Audio: ding on correct, snare on wrong, fanfare on completion
/// Well Done celebration banner
class EmotionRecognitionGame extends BaseScenarioGame {
  late final TelemetryTracker _telemetry;
  late final Map<String, dynamic> _config;

  final List<FaceCard> _faceCards = [];
  final List<EmotionLabel> _emojiTiles = [];
  int _correctMatches = 0;
  int _incorrectAttempts = 0;
  int _totalPairs = 0;
  bool _celebrationStarted = false;

  _PlayerAvatarComponent? _playerAvatar;
  final _rng = Random();

  EmotionRecognitionGame({required super.config});

  @override
  Color backgroundColor() => const Color(0xFFF5F5F5);

  @override
  Future<void> loadScenario() async {
    FlameAudio.audioCache.prefix = '';

    _telemetry = TelemetryTracker();
    _config = DifficultyConfig.getConfig(
      'emotion_recognition',
      config.difficulty,
      config.complexity,
    );

    final emotionSet = List<String>.from(_config['emotion_set'] as List);
    final configuredFaceCount = _config['face_count'] as int;
    final faceCount = min(configuredFaceCount, emotionSet.length);
    _totalPairs = faceCount;

    final gameWidth  = size.x;
    final gameHeight = size.y;
    final rng = Random();

    // Select emotions randomly for this round
    final selectedEmotions = List<String>.from(emotionSet)..shuffle(rng);
    final emotions = selectedEmotions.take(faceCount).toList();

    // Pick face avatar type — must differ from user's own avatar
    final prefs = await SharedPreferences.getInstance();
    final userAvatarKey = prefs.getString('selected_avatar') ?? 'avatar_boy_A_1';
    final userType = _avatarTypeFromKey(userAvatarKey);
    final facePool = List<String>.from(
      _kFaceTypesByUserType[userType] ?? _kFaceTypesByUserType['boy_A']!,
    )..shuffle(rng);
    final faceAvatarType = facePool.first;

    // Background
    try {
      final bgSprite = await _loadSprite(_kBackground);
      add(SpriteComponent(
        sprite: bgSprite,
        size: size,
        anchor: Anchor.topLeft,
        priority: -1,
      ));
    } catch (_) {}

    // Player avatar — bottom-left, idle bob
    const avW = 80.0;
    const avH = 100.0;
    final avX = gameWidth * 0.10;
    final avY = gameHeight * 0.87;
    _playerAvatar = _PlayerAvatarComponent(
      avatarKey: userAvatarKey,
      avatarType: userType,
      position: Vector2(avX, avY),
      size: Vector2(avW, avH),
    );
    add(_playerAvatar!);

    // Speech bubble from player avatar
    const bubbleW = 175.0;
    const bubbleH = 56.0;
    final bubbleX = avX + avW * 0.5 + 6;
    final bubbleY = avY - avH * 0.32;
    try {
      final bubbleSprite = await _loadSprite(_kSpeechBubble);
      add(SpriteComponent(
        sprite: bubbleSprite,
        size: Vector2(bubbleW, bubbleH),
        anchor: Anchor.centerLeft,
        position: Vector2(bubbleX, bubbleY),
        priority: 3,
      ));
    } catch (_) {
      add(_DrawnBubble(
        position: Vector2(bubbleX, bubbleY - bubbleH / 2),
        bubbleWidth: bubbleW,
        bubbleHeight: bubbleH,
        priority: 3,
      ));
    }
    add(TextComponent(
      text: 'Match the feeling!',
      anchor: Anchor.centerLeft,
      position: Vector2(bubbleX + 16, bubbleY),
      priority: 4,
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Color(0xFF1565C0),
          fontSize: 13,
          fontWeight: FontWeight.bold,
          height: 1.3,
        ),
      ),
    ));

    // Level indicator
    add(TextComponent(
      text: 'Level ${config.difficulty}',
      anchor: Anchor.center,
      position: Vector2(gameWidth / 2, 18),
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Color(0xFF757575),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    ));

    // Instruction
    add(TextComponent(
      text: 'Drag the emoji to the matching face!',
      anchor: Anchor.center,
      position: Vector2(gameWidth / 2, 44),
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Color(0xFF1565C0),
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    ));

    // Face cards as drop targets (upper area)
    const faceW = 85.0;
    const faceH = 105.0;
    final faceSpacing = (gameWidth - faceCount * faceW) / (faceCount + 1);

    for (int i = 0; i < faceCount; i++) {
      final xPos = faceSpacing + i * (faceW + faceSpacing) + faceW / 2;
      final card = FaceCard(
        position: Vector2(xPos, gameHeight * 0.33),
        size: Vector2(faceW, faceH),
        emotion: emotions[i],
        avatarType: faceAvatarType,
      );
      _faceCards.add(card);
      add(card);
    }

    // Emoji tiles as draggable items (lower area, shuffled order)
    // Moved slightly up from 0.75 -> 0.68 to leave room for player avatar
    final shuffledEmotions = List<String>.from(emotions)..shuffle(rng);
    const tileSize = 70.0;
    final tileSpacing = (gameWidth - faceCount * tileSize) / (faceCount + 1);

    for (int i = 0; i < faceCount; i++) {
      final xPos = tileSpacing + i * (tileSize + tileSpacing) + tileSize / 2;
      final tile = EmotionLabel(
        position: Vector2(xPos, gameHeight * 0.68),
        size: Vector2(tileSize, tileSize),
        emotion: shuffledEmotions[i],
        onTileDropped: _onTileDropped,
      );
      _emojiTiles.add(tile);
      add(tile);
    }

    overlays.add('HintOverlay');
  }

  void _dismissHint() {
    if (overlays.isActive('HintOverlay')) {
      overlays.remove('HintOverlay');
    }
  }

  void _onTileDropped(EmotionLabel tile, Vector2 dropPos) {
    _dismissHint();
    _telemetry.recordAction('drop', elapsedMs);

    // Find nearest unmatched face card
    FaceCard? nearestFace;
    double nearestDist = double.infinity;

    for (final face in _faceCards) {
      if (face.isMatched) continue;
      final dist = face.position.distanceTo(dropPos);
      if (dist < nearestDist) {
        nearestDist = dist;
        nearestFace = face;
      }
    }

    if (nearestFace != null && nearestDist <= 90.0) {
      if (tile.emotion == nearestFace.emotion) {
        // Correct match
        _correctMatches++;
        nearestFace.markMatched();
        tile.removeFromParent();
        _emojiTiles.remove(tile);
        _telemetry.recordAction('correct_match', elapsedMs);
        _spawnStarBurst(dropPos);
        _playAudio(_kAudioCorrect);
        _playerAvatar?.showHappy();

        if (_correctMatches >= _totalPairs) {
          _triggerCelebration();
        }
      } else {
        // Wrong match — snap back
        _incorrectAttempts++;
        _telemetry.recordRetry();
        tile.resetPosition();
        _playAudio(_kAudioWrong);
        _playerAvatar?.showConfused();
      }
    } else {
      // Dropped too far from any face — snap back
      tile.resetPosition();
    }
  }

  void _spawnStarBurst(Vector2 origin) {
    add(ParticleSystemComponent(
      position: origin,
      priority: 10,
      particle: Particle.generate(
        count: 16,
        lifespan: 0.8,
        generator: (i) {
          final angle = (i / 16) * pi * 2 + _rng.nextDouble() * 0.4;
          final speed = 75.0 + _rng.nextDouble() * 65.0;
          return AcceleratedParticle(
            speed: Vector2(cos(angle) * speed, sin(angle) * speed),
            acceleration: Vector2(0, 80),
            child: ScalingParticle(
              to: 0,
              child: CircleParticle(
                radius: 5 + _rng.nextDouble() * 5,
                paint: Paint()
                  ..color = _kStarColors[_rng.nextInt(_kStarColors.length)],
              ),
            ),
          );
        },
      ),
    ));
  }

  void _triggerCelebration() {
    if (_celebrationStarted) return;
    _celebrationStarted = true;
    _playAudio(_kAudioFanfare);
    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 200), () {
        if (!isComplete) {
          _spawnStarBurst(Vector2(size.x * (0.25 + i * 0.25), size.y * 0.45));
        }
      });
    }
    _playerAvatar?.showHappy();
    add(_WellDoneBannerComponent(
      center: Vector2(size.x / 2, size.y / 2),
      subtitle: 'Great matching! 🎉',
      onDone: () {
        final total = _correctMatches + _incorrectAttempts;
        final reward = total > 0
            ? (_correctMatches / total).clamp(0.0, 1.0)
            : 1.0;
        completeScenario(true, reward, telemetry: _telemetry.toJson());
      },
      priority: 20,
    ));
  }

  void _playAudio(String path) {
    FlameAudio.play(path).catchError((_) => AudioPlayer());
  }

  @override
  void updateScenario(double dt) {
    // Drag-and-drop is event-driven; no per-frame logic needed
  }
}

// ── Player avatar component ────────────────────────────────────────────────────

class _PlayerAvatarComponent extends PositionComponent {
  final String avatarKey;
  final String avatarType;

  SpriteComponent? _neutral;
  SpriteComponent? _confused;
  SpriteComponent? _happy;
  double _bobT = 0.0;

  _PlayerAvatarComponent({
    required this.avatarKey,
    required this.avatarType,
    required Vector2 position,
    required Vector2 size,
  }) : super(position: position, size: size, anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    try {
      final s = await _loadSprite('lib/assets/avatars/$avatarKey.png');
      _neutral = SpriteComponent(
          sprite: s, size: size, anchor: Anchor.center, position: size / 2);
      add(_neutral!);
    } catch (_) {}

    for (final entry in {
      'confused': (SpriteComponent c) => _confused = c,
      'happy': (SpriteComponent c) => _happy = c,
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
  }

  @override
  void update(double dt) {
    super.update(dt);
    _bobT += dt * 1.6;
    final bob = sin(_bobT) * 3.5;
    for (final c in [_neutral, _confused, _happy]) {
      if (c != null) c.position.y = size.y / 2 + bob;
    }
  }

  void showHappy() => _swapTo(_happy, autoResetMs: 1400);
  void showConfused() => _swapTo(_confused, autoResetMs: 1200);

  void _swapTo(SpriteComponent? target, {int? autoResetMs}) {
    _neutral?.opacity = 0.0;
    _confused?.opacity = 0.0;
    _happy?.opacity = 0.0;
    target?.opacity = 1.0;
    target?.add(ScaleEffect.to(
      Vector2.all(1.15),
      EffectController(duration: 0.2, reverseDuration: 0.2, curve: Curves.elasticOut),
    ));
    if (autoResetMs != null) {
      Future.delayed(Duration(milliseconds: autoResetMs), () {
        _neutral?.opacity = 1.0;
        _confused?.opacity = 0.0;
        _happy?.opacity = 0.0;
      });
    }
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
        fontSize: 19,
        fontWeight: FontWeight.bold,
      ),
      10,
    );
  }
}

// ── Drawn speech bubble fallback ──────────────────────────────────────────────

class _DrawnBubble extends PositionComponent {
  final double bubbleWidth;
  final double bubbleHeight;

  _DrawnBubble({
    required Vector2 position,
    required this.bubbleWidth,
    required this.bubbleHeight,
    super.priority,
  }) : super(position: position, size: Vector2(bubbleWidth, bubbleHeight));

  @override
  void render(Canvas canvas) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, bubbleWidth, bubbleHeight),
          const Radius.circular(12)));
    canvas.drawPath(path, Paint()..color = const Color(0xF0FFFFFF));
    final tail = Path()
      ..moveTo(0, bubbleHeight / 2 - 10)
      ..lineTo(-14, bubbleHeight / 2)
      ..lineTo(0, bubbleHeight / 2 + 10)
      ..close();
    canvas.drawPath(tail, Paint()..color = const Color(0xF0FFFFFF));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, bubbleWidth, bubbleHeight),
          const Radius.circular(12)),
      Paint()
        ..color = const Color(0xFF1565C0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
  }
}
