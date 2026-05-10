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
import '../components/countdown_display.dart';
import '../difficulty_config.dart';
import '../telemetry_tracker.dart';

// ── Asset paths ───────────────────────────────────────────────────────────────

const _kBackground   = 'lib/assets/background/classroom_background.png';
const _kGiftBox      = 'lib/assets/item/reward/gift_box.png';
const _kSpeechBubble = 'lib/assets/UI/speechbubble.png';

const _kFallbackItems = [
  'lib/assets/item/toys/toy_ball.png',
  'lib/assets/item/toys/toy_bear.png',
  'lib/assets/item/toys/toy_car.png',
  'lib/assets/item/toys/toy_robot.png',
  'lib/assets/item/sweets/sweet_blue_1.png',
  'lib/assets/item/sweets/sweet_red_1.png',
  'lib/assets/item/sweets/sweet_yellow_1.png',
];

const _kAudioTick     = 'lib/assets/audio/patience/tick.mp3';
const _kAudioReady    = 'lib/assets/audio/patience/ready.mp3';
const _kAudioCollect  = 'lib/assets/audio/patience/collect.mp3';
const _kAudioEarlyTap = 'lib/assets/audio/patience/early_tap.mp3';
const _kAudioComplete = 'lib/assets/audio/patience/complete.mp3';

const _kStarColors = [
  Color(0xFFFFD700), Color(0xFFFF6B6B),
  Color(0xFF4FC3F7), Color(0xFFA5D6A7), Color(0xFFCE93D8),
];

// ── Helpers ───────────────────────────────────────────────────────────────────

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
/// User avatar (idle bob) with confused/happy emotion swap
/// Reward item sprite: dimmed while waiting, reveals with sparkle burst
/// Countdown ring: blue->orange->gold gradient, pulse on final 3 ticks
/// Ambient sparkles orbit the reward when ready
/// Shake feedback on early tap
/// Collect particle burst + avatar happy reaction
/// Speech bubble instruction, progress stars, Well Done banner
/// Audio: tick, ready chime, collect, early-tap boing, fanfare
class PatienceGame extends BaseScenarioGame with TapCallbacks {
  late final TelemetryTracker _telemetry;
  late final Map<String, dynamic> _config;

  int _earlyTapCount = 0;
  int _rewardCount = 0;
  int _collectedRewards = 0;
  bool _timerComplete = false;
  bool _celebrationStarted = false;
  double _earlyTapPenalty = 0.0;

  double _sparkleTimer = 0.0;
  bool _sparkling = false;

  CountdownDisplay? _countdown;
  _RewardItemComponent? _rewardItem;
  _WaitingAvatarComponent? _avatarComp;
  _ProgressStarsComponent? _progressStars;
  TextComponent? _bubbleText;

  Vector2 _rewardCenter = Vector2.zero();
  final _rng = Random();

  PatienceGame({required super.config});

  @override
  Future<void> loadScenario() async {
    FlameAudio.audioCache.prefix = '';

    _telemetry = TelemetryTracker();
    _config = DifficultyConfig.getConfig('patience', config.difficulty, config.complexity);
    _rewardCount = _config['reward_count'] as int;
    _earlyTapPenalty = (_config['early_tap_penalty'] as num).toDouble();

    final w = size.x;
    final h = size.y;

    // Background
    final bgSprite = await _loadSprite(_kBackground);
    add(SpriteComponent(sprite: bgSprite, size: size, anchor: Anchor.topLeft, priority: -1));

    // User avatar
    final prefs = await SharedPreferences.getInstance();
    final avatarKey = prefs.getString('selected_avatar') ?? 'avatar_boy_A_1';
    final avatarType = _avatarTypeFromKey(avatarKey);

    const avW = 100.0;
    const avH = 130.0;
    final avX = w * 0.14;
    final avY = h * 0.52;

    _avatarComp = _WaitingAvatarComponent(
      avatarKey: avatarKey,
      avatarType: avatarType,
      position: Vector2(avX, avY),
      size: Vector2(avW, avH),
    );
    add(_avatarComp!);

    // Speech bubble (PNG sprite + text overlay)
    const bubbleW = 190.0;
    const bubbleH = 68.0;
    final bubbleX = avX + avW * 0.5 + 6;
    final bubbleY = avY - avH * 0.38;
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
      add(_DrawnBubbleComponent(
        position: Vector2(bubbleX, bubbleY - bubbleH / 2),
        bubbleWidth: bubbleW, bubbleHeight: bubbleH, priority: 3,
      ));
    }
    _bubbleText = TextComponent(
      text: 'Wait for the glow,\nthen tap!',
      anchor: Anchor.centerLeft,
      position: Vector2(bubbleX + 14, bubbleY),
      priority: 4,
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Color(0xFF1565C0), fontSize: 13,
          fontWeight: FontWeight.bold, height: 1.3,
        ),
      ),
    );
    add(_bubbleText!);

    // Progress stars (bottom strip, only when multiple rewards)
    if (_rewardCount > 1) {
      _progressStars = _ProgressStarsComponent(
        total: _rewardCount,
        position: Vector2(w / 2, h - 28),
        priority: 3,
      );
      add(_progressStars!);
    }

    _startNextReward();
    overlays.add('HintOverlay');
  }

  void _startNextReward() {
    _timerComplete = false;
    _sparkling = false;
    _sparkleTimer = 0;

    final waitSeconds = _config['wait_seconds'] as int;
    final w = size.x;
    final h = size.y;

    _countdown?.removeFromParent();
    _rewardItem?.removeFromParent();

    _countdown = CountdownDisplay(
      position: Vector2(w * 0.62, h * 0.33),
      totalSeconds: waitSeconds,
      onComplete: _onTimerComplete,
      onTick: () => _playAudio(_kAudioTick),
    );
    add(_countdown!);

    _rewardCenter = Vector2(w * 0.62, h * 0.67);
    _rewardItem = _RewardItemComponent(
      position: _rewardCenter.clone(),
      size: Vector2(120, 120),
      primaryPath: _kGiftBox,
      fallbackPath: _kFallbackItems[_rng.nextInt(_kFallbackItems.length)],
    );
    add(_rewardItem!);
  }

  void _onTimerComplete() {
    _timerComplete = true;
    _sparkling = true;
    _rewardItem?.revealReady();
    _avatarComp?.resetToNeutral();
    _playAudio(_kAudioReady);
    _bubbleText?.text = 'Tap it now!';
  }

  void _dismissHint() {
    if (overlays.isActive('HintOverlay')) {
      overlays.remove('HintOverlay');
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    _dismissHint();
    _telemetry.recordAction('tap', elapsedMs);

    if (!_timerComplete) {
      _earlyTapCount++;
      _telemetry.recordRetry();
      _rewardItem?.shake();
      _avatarComp?.showConfused();
      _playAudio(_kAudioEarlyTap);
      _bubbleText?.text = 'Not yet...\nwait for it!';
    } else {
      _sparkling = false;
      _collectedRewards++;
      _rewardItem?.collect();
      _avatarComp?.showHappy();
      _spawnCollectBurst(_rewardCenter);
      _playAudio(_kAudioCollect);
      _progressStars?.delivered = _collectedRewards;

      if (_collectedRewards >= _rewardCount) {
        _triggerCelebration();
      } else {
        Future.delayed(const Duration(milliseconds: 650), () {
          if (!_celebrationStarted && !isComplete) {
            _avatarComp?.resetToNeutral();
            _bubbleText?.text = 'Wait for the glow,\nthen tap!';
            _startNextReward();
          }
        });
      }
    }
  }

  @override
  void updateScenario(double dt) {
    if (_sparkling && !_celebrationStarted) {
      _sparkleTimer += dt;
      if (_sparkleTimer >= 0.14) {
        _sparkleTimer = 0;
        _spawnAmbientSparkle();
      }
    }
  }

  void _spawnAmbientSparkle() {
    final angle = _rng.nextDouble() * pi * 2;
    const orbitR = 72.0;
    final pos = _rewardCenter + Vector2(cos(angle) * orbitR, sin(angle) * orbitR);
    add(ParticleSystemComponent(
      position: pos,
      priority: 8,
      particle: AcceleratedParticle(
        acceleration: Vector2(0, -25),
        speed: Vector2(_rng.nextDouble() * 18 - 9, -35 - _rng.nextDouble() * 20),
        lifespan: 0.75,
        child: ScalingParticle(
          to: 0,
          child: CircleParticle(
            radius: 3 + _rng.nextDouble() * 3,
            paint: Paint()..color = const Color(0xFFFFD700),
          ),
        ),
      ),
    ));
  }

  void _spawnCollectBurst(Vector2 origin) {
    add(ParticleSystemComponent(
      position: origin,
      priority: 10,
      particle: Particle.generate(
        count: 18,
        lifespan: 0.85,
        generator: (i) {
          final angle = (i / 18) * pi * 2 + _rng.nextDouble() * 0.3;
          final speed = 85.0 + _rng.nextDouble() * 65;
          return AcceleratedParticle(
            speed: Vector2(cos(angle) * speed, sin(angle) * speed),
            acceleration: Vector2(0, 80),
            child: ScalingParticle(
              to: 0,
              child: CircleParticle(
                radius: 5 + _rng.nextDouble() * 5,
                paint: Paint()..color = _kStarColors[_rng.nextInt(_kStarColors.length)],
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
    _playAudio(_kAudioComplete);
    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 220), () {
        _spawnCollectBurst(Vector2(size.x * (0.3 + i * 0.2), size.y * 0.4));
      });
    }
    _avatarComp?.showHappy();
    add(_WellDoneBannerComponent(
      center: Vector2(size.x / 2, size.y / 2),
      onDone: () {
        final success = _earlyTapCount == 0;
        final reward = success
            ? 1.0
            : (1.0 - _earlyTapCount * _earlyTapPenalty).clamp(0.0, 1.0);
        completeScenario(success, reward, telemetry: _telemetry.toJson());
      },
      priority: 20,
    ));
  }

  void _playAudio(String path) {
    FlameAudio.play(path).catchError((_) => AudioPlayer());
  }
}

// ── Reward item ───────────────────────────────────────────────────────────────

class _RewardItemComponent extends PositionComponent {
  final String primaryPath;
  final String fallbackPath;

  bool _isReady = false;
  bool _collected = false;
  double _bobT = 0.0;
  SpriteComponent? _sprite;

  _RewardItemComponent({
    required Vector2 position,
    required Vector2 size,
    required this.primaryPath,
    required this.fallbackPath,
  }) : super(position: position, size: size, anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    Sprite? sprite;
    try {
      sprite = await _loadSprite(primaryPath);
    } catch (_) {
      try {
        sprite = await _loadSprite(fallbackPath);
      } catch (_) {}
    }
    if (sprite != null) {
      _sprite = SpriteComponent(
        sprite: sprite,
        size: size * 0.88,
        anchor: Anchor.center,
        position: size / 2,
      )..opacity = 0.28;
      add(_sprite!);
    }

    // Decorative dimmed question-mark until revealed
    add(TextComponent(
      text: '?',
      anchor: Anchor.center,
      position: size / 2,
      priority: 1,
      textRenderer: TextPaint(
        style: TextStyle(
          fontSize: size.x * 0.55,
          color: Colors.white.withAlpha(60),
          fontWeight: FontWeight.w900,
        ),
      ),
    ));
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_collected || _isReady) return;
    _bobT += dt * 1.8;
    if (_sprite != null) _sprite!.position.y = size.y / 2 + sin(_bobT) * 4;
  }

  void revealReady() {
    _isReady = true;
    // Remove the "?" overlay
    children.whereType<TextComponent>().forEach((c) => c.removeFromParent());
    _sprite?.add(OpacityEffect.to(1.0, EffectController(duration: 0.45, curve: Curves.easeOut)));
    add(ScaleEffect.to(
      Vector2.all(1.12),
      EffectController(duration: 0.3, curve: Curves.elasticOut),
    ));
  }

  void shake() {
    children.whereType<MoveEffect>().forEach((e) => e.removeFromParent());
    add(SequenceEffect([
      MoveEffect.by(Vector2(-10, 0), EffectController(duration: 0.04)),
      MoveEffect.by(Vector2(20, 0),  EffectController(duration: 0.04)),
      MoveEffect.by(Vector2(-20, 0), EffectController(duration: 0.04)),
      MoveEffect.by(Vector2(10, 0),  EffectController(duration: 0.04)),
    ]));
  }

  void collect() {
    _collected = true;
    add(SequenceEffect(
      [
        ScaleEffect.to(Vector2.all(1.4), EffectController(duration: 0.14, curve: Curves.easeOut)),
        ScaleEffect.to(Vector2.all(0.0), EffectController(duration: 0.18, curve: Curves.easeIn)),
      ],
      onComplete: removeFromParent,
    ));
  }
}

// ── Waiting avatar ────────────────────────────────────────────────────────────

class _WaitingAvatarComponent extends PositionComponent {
  final String avatarKey;
  final String avatarType;

  SpriteComponent? _neutral;
  SpriteComponent? _confused;
  SpriteComponent? _happy;
  double _bobT = 0.0;

  _WaitingAvatarComponent({
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
      _neutral = SpriteComponent(sprite: s, size: size, anchor: Anchor.center, position: size / 2);
      add(_neutral!);
    } catch (_) {}

    for (final entry in {
      'confused': (SpriteComponent c) => _confused = c,
      'happy':    (SpriteComponent c) => _happy    = c,
    }.entries) {
      try {
        final s = await _loadSprite('lib/assets/emotion/${avatarType}_${entry.key}.png');
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
    final bob = sin(_bobT) * 4.0;
    for (final c in [_neutral, _confused, _happy]) {
      if (c != null) c.position.y = size.y / 2 + bob;
    }
  }

  void showConfused() => _swapTo(_confused, autoResetMs: 1600);
  void showHappy()    => _swapTo(_happy);

  void resetToNeutral() {
    _neutral?.opacity = 1.0;
    _confused?.opacity = 0.0;
    _happy?.opacity = 0.0;
  }

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
      Future.delayed(Duration(milliseconds: autoResetMs), resetToNeutral);
    }
  }
}

// ── Progress stars ────────────────────────────────────────────────────────────

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
      _drawStar(canvas, Offset(x + starSize / 2, 0), starSize / 2,
          filled ? const Color(0xFFFFD700) : const Color(0x55FFFFFF),
          filled ? const Color(0xFFFF8F00) : const Color(0x33FFFFFF));
      x += starSize + gap;
    }
  }

  void _drawStar(Canvas canvas, Offset center, double r, Color fill, Color stroke) {
    const pts = 5;
    final inner = r * 0.42;
    final path = Path();
    for (int i = 0; i < pts * 2; i++) {
      final rad = i.isEven ? r : inner;
      final a = (i * pi / pts) - pi / 2;
      final pt = Offset(center.dx + rad * cos(a), center.dy + rad * sin(a));
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(path, Paint()..color = stroke..style = PaintingStyle.stroke..strokeWidth = 1.5);
  }
}

// ── Well Done banner ──────────────────────────────────────────────────────────

class _WellDoneBannerComponent extends PositionComponent {
  final VoidCallback onDone;
  double _elapsed = 0.0;
  bool _doneFired = false;
  static const _kShow = 2.2;

  _WellDoneBannerComponent({
    required Vector2 center,
    required this.onDone,
    super.priority,
  }) : super(position: center, anchor: Anchor.center, size: Vector2(320, 160));

  @override
  void onLoad() {
    scale = Vector2.all(0.4);
    add(ScaleEffect.to(Vector2.all(1.0),
        EffectController(duration: 0.35, curve: Curves.elasticOut)));
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
    final rect = Rect.fromCenter(center: Offset.zero, width: size.x, height: size.y);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(24)),
        Paint()..color = const Color(0xF01565C0));

    void drawText(String text, TextStyle style, double dy) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: size.x - 24);
      tp.paint(canvas, Offset(-tp.width / 2, dy));
    }

    drawText('🌟 Well Done! 🌟',
        const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900,
            shadows: [Shadow(color: Colors.black38, blurRadius: 6)]),
        -size.y / 2 + 28);

    drawText('Great patience! 🎉',
        const TextStyle(color: Color(0xFFBBDEFB), fontSize: 19, fontWeight: FontWeight.bold),
        10);
  }
}

// ── Drawn speech bubble fallback ──────────────────────────────────────────────

class _DrawnBubbleComponent extends PositionComponent {
  final double bubbleWidth;
  final double bubbleHeight;

  _DrawnBubbleComponent({
    required Vector2 position,
    required this.bubbleWidth,
    required this.bubbleHeight,
    super.priority,
  }) : super(position: position, size: Vector2(bubbleWidth, bubbleHeight));

  @override
  void render(Canvas canvas) {
    final w = bubbleWidth;
    final h = bubbleHeight;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), const Radius.circular(12)));
    canvas.drawPath(path, Paint()..color = const Color(0xF0FFFFFF));
    final tail = Path()
      ..moveTo(0, h / 2 - 10)
      ..lineTo(-14, h / 2)
      ..lineTo(0, h / 2 + 10)
      ..close();
    canvas.drawPath(tail, Paint()..color = const Color(0xF0FFFFFF));
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), const Radius.circular(12)),
        Paint()
          ..color = const Color(0xFF1565C0)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0);
  }
}
