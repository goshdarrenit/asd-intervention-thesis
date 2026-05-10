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
import '../components/choice_button.dart';
import '../components/choice_node.dart';
import '../difficulty_config.dart';
import '../telemetry_tracker.dart';

// ── Asset paths ────────────────────────────────────────────────────────────────

const _kBackground   = 'lib/assets/background/classroom_background_2.png';
const _kSpeechBubble = 'lib/assets/UI/speechbubble.png';

const _kAudioGood    = 'lib/assets/audio/sharing/drop_ding.mp3';
const _kAudioBad     = 'lib/assets/audio/sharing/missed_snare.mp3';
const _kAudioFanfare = 'lib/assets/audio/sharing/fanfare.mp3';

const _kStarColors = [
  Color(0xFFFFD700), Color(0xFFFF6B6B),
  Color(0xFF4FC3F7), Color(0xFFA5D6A7), Color(0xFFCE93D8),
];

/// Button colours per choice type — calm, ASD-friendly palette.
const _kGoodChoiceColor = Color(0xFF43A047);   // green
const _kBadChoiceColor  = Color(0xFFFF8F00);   // amber (not alarming red)

/// Peer avatars per user type.
const _kPeersByUserType = {
  'boy_A': [
    'lib/assets/avatars/avatar_girl_A_2.png',
    'lib/assets/avatars/avatar_boy_B_2.png',
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
/// User avatar (left) and friend avatar (right) visible in the scene
/// Speech bubble from friend shows the situation context
/// Choice buttons colour-coded: green = de-escalation, amber = escalation
/// Star particle burst on good choices; shake + amber flash on bad
/// Audio: ding (good), snare (bad), fanfare (success)
/// Well Done / Try Again banner at completion
class ConflictResolutionGame extends BaseScenarioGame {
  late final TelemetryTracker _telemetry;
  late final Map<String, dynamic> _config;

  late final ChoiceNode _rootNode;
  ChoiceNode? _currentNode;

  final List<String> _choiceHistory = [];
  int _deEscalationCount = 0;
  int _totalChoices = 0;

  double? _timeLimitSeconds;
  double _choiceElapsedTime = 0.0;

  // UI components
  final List<ChoiceButton> _currentButtons = [];
  late TextComponent _promptText;

  // Scene avatars
  _SceneAvatarComponent? _userAvatarComp;
  _SceneAvatarComponent? _friendAvatarComp;

  bool _celebrationStarted = false;
  final _rng = Random();

  ConflictResolutionGame({required super.config});

  @override
  Future<void> loadScenario() async {
    FlameAudio.audioCache.prefix = '';

    _telemetry = TelemetryTracker();
    _config = DifficultyConfig.getConfig(
      'conflict_resolution',
      config.difficulty,
      config.complexity,
    );

    _timeLimitSeconds = _config['time_limit_seconds'] != null
        ? (_config['time_limit_seconds'] as num).toDouble()
        : null;

    final choicesPerLevel = _config['choices_per_level'] as int;
    final levels = _config['levels'] as int;

    _rootNode = _buildChoiceTree(choicesPerLevel, levels);
    _currentNode = _rootNode;

    final w = size.x;
    final h = size.y;

    // ── Background ─────────────────────────────────────────────────────────────
    try {
      final bgSprite = await _loadSprite(_kBackground);
      add(SpriteComponent(
          sprite: bgSprite, size: size, anchor: Anchor.topLeft, priority: -1));
    } catch (_) {}

    // ── User & friend avatars ──────────────────────────────────────────────────
    final prefs = await SharedPreferences.getInstance();
    final userAvatarKey = prefs.getString('selected_avatar') ?? 'avatar_boy_A_1';
    final userType = _avatarTypeFromKey(userAvatarKey);

    final peerPool = List<String>.from(
      _kPeersByUserType[userType] ?? _kPeersByUserType['boy_A']!,
    )..shuffle(_rng);
    final peerPath = peerPool.first;
    final peerType = _avatarTypeFromPath(peerPath);

    const avW = 72.0;
    const avH = 92.0;
    // Avatars sit below the prompt panel
    final avY = h * 0.35;

    _userAvatarComp = _SceneAvatarComponent(
      spritePath: 'lib/assets/avatars/$userAvatarKey.png',
      avatarType: userType,
      label: 'You',
      labelColor: const Color(0xFF1565C0),
      position: Vector2(w * 0.12, avY),
      size: Vector2(avW, avH),
    );
    add(_userAvatarComp!);

    _friendAvatarComp = _SceneAvatarComponent(
      spritePath: peerPath,
      avatarType: peerType,
      label: 'Friend',
      labelColor: const Color(0xFFFF8F00),
      position: Vector2(w * 0.82, avY),
      size: Vector2(avW, avH),
    );
    add(_friendAvatarComp!);

    // Speech bubble from friend — static context hint
    const bubbleW = 200.0;
    const bubbleH = 58.0;
    final bx = w * 0.82 - avW * 0.5 - bubbleW - 6;
    final by = avY - avH * 0.3;
    try {
      final bubbleSprite = await _loadSprite(_kSpeechBubble);
      // Flip horizontally: scale x by -1, then shift right by bubbleW
      add(_FlippedBubbleComponent(
        sprite: bubbleSprite,
        size: Vector2(bubbleW, bubbleH),
        position: Vector2(bx, by),
        priority: 3,
      ));
    } catch (_) {
      add(_DrawnBubbleRight(
        position: Vector2(bx, by - bubbleH / 2),
        bubbleWidth: bubbleW,
        bubbleHeight: bubbleH,
        priority: 3,
      ));
    }
    add(TextComponent(
      text: 'Uh oh! There\'s a conflict!',
      anchor: Anchor.centerRight,
      position: Vector2(bx + bubbleW - 12, by),
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

    // ── "Choose how to respond" label ──────────────────────────────────────────
    add(TextComponent(
      text: 'Choose how to respond:',
      anchor: Anchor.center,
      position: Vector2(w / 2, h * 0.53),
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Color(0xFF1565C0),
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    ));

    // ── Situation prompt panel ─────────────────────────────────────────────────
    // Semi-transparent white card behind the prompt text for readability
    // add(_PromptPanelComponent(
    //   position: Vector2(w / 2, h * 0.15),
    //   panelWidth: w * 0.82,
    //   panelHeight: 72,
    //   priority: 1,
    // ));

    _promptText = TextComponent(
      text: '',
      anchor: Anchor.center,
      position: Vector2(w / 2, h * 0.15),
      priority: 2,
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Color(0xFF1A237E),
          fontSize: 17,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
    );
    add(_promptText);

    // ── Display first choices ──────────────────────────────────────────────────
    _displayChoices(_currentNode!);
  }

  // ── Choice tree ───────────────────────────────────────────────────────────

  ChoiceNode _buildChoiceTree(int choicesPerLevel, int levels) {
    if (levels == 1) {
      return ChoiceNode(
        prompt: 'Your friend took the toy\nyou were playing with.\nWhat do you do?',
        choices: [
          ChoiceOption(
            id: 'ask_nicely',
            text: 'Ask nicely to share',
            isDeEscalation: true,
            nextNode: null,
          ),
          ChoiceOption(
            id: 'grab_back',
            text: 'Grab it back',
            isDeEscalation: false,
            nextNode: null,
          ),
        ],
      );
    } else if (levels == 2) {
      final level2PositiveNode = ChoiceNode(
        prompt: 'Your friend says OK!\nHow do you share?',
        choices: [
          ChoiceOption(
            id: 'take_turns',
            text: 'Take turns',
            isDeEscalation: true,
            nextNode: null,
          ),
          ChoiceOption(
            id: 'play_together',
            text: 'Play together',
            isDeEscalation: true,
            nextNode: null,
          ),
          ChoiceOption(
            id: 'ask_for_all',
            text: 'Ask for the whole toy',
            isDeEscalation: false,
            nextNode: null,
          ),
        ],
      );

      final level2NeutralNode = ChoiceNode(
        prompt: 'The teacher talks to\nboth of you.\nWhat do you say?',
        choices: [
          ChoiceOption(
            id: 'explain_calmly',
            text: 'Explain calmly',
            isDeEscalation: true,
            nextNode: null,
          ),
          ChoiceOption(
            id: 'blame_friend',
            text: 'Blame your friend',
            isDeEscalation: false,
            nextNode: null,
          ),
          ChoiceOption(
            id: 'say_nothing',
            text: 'Say nothing',
            isDeEscalation: false,
            nextNode: null,
          ),
        ],
      );

      return ChoiceNode(
        prompt: 'Your friend took the toy\nyou were playing with.\nWhat do you do?',
        choices: [
          ChoiceOption(
            id: 'ask_nicely',
            text: 'Ask nicely to share',
            isDeEscalation: true,
            nextNode: level2PositiveNode,
          ),
          ChoiceOption(
            id: 'tell_teacher',
            text: 'Tell the teacher',
            isDeEscalation: false,
            nextNode: level2NeutralNode,
          ),
          ChoiceOption(
            id: 'grab_back',
            text: 'Grab it back',
            isDeEscalation: false,
            nextNode: null,
          ),
        ],
      );
    } else {
      // Complexity high: 3 choices, 3 levels
      final level3Node = ChoiceNode(
        prompt: 'Your friend smiles!\nNow what?',
        choices: [
          ChoiceOption(
            id: 'thank_friend',
            text: 'Thank them',
            isDeEscalation: true,
            nextNode: null,
          ),
          ChoiceOption(
            id: 'keep_playing',
            text: 'Keep playing nicely',
            isDeEscalation: true,
            nextNode: null,
          ),
          ChoiceOption(
            id: 'take_more_toys',
            text: 'Take other toys too',
            isDeEscalation: false,
            nextNode: null,
          ),
        ],
      );

      final level2PositiveNode = ChoiceNode(
        prompt: 'Your friend says OK!\nHow do you share?',
        choices: [
          ChoiceOption(
            id: 'take_turns',
            text: 'Take turns',
            isDeEscalation: true,
            nextNode: level3Node,
          ),
          ChoiceOption(
            id: 'play_together',
            text: 'Play together',
            isDeEscalation: true,
            nextNode: level3Node,
          ),
          ChoiceOption(
            id: 'ask_for_all',
            text: 'Ask for the whole toy',
            isDeEscalation: false,
            nextNode: null,
          ),
        ],
      );

      final level2NeutralNode = ChoiceNode(
        prompt: 'The teacher talks to\nboth of you.\nWhat do you say?',
        choices: [
          ChoiceOption(
            id: 'explain_calmly',
            text: 'Explain calmly',
            isDeEscalation: true,
            nextNode: null,
          ),
          ChoiceOption(
            id: 'blame_friend',
            text: 'Blame your friend',
            isDeEscalation: false,
            nextNode: null,
          ),
          ChoiceOption(
            id: 'say_nothing',
            text: 'Say nothing',
            isDeEscalation: false,
            nextNode: null,
          ),
        ],
      );

      return ChoiceNode(
        prompt: 'Your friend took the toy\nyou were playing with.\nWhat do you do?',
        choices: [
          ChoiceOption(
            id: 'ask_nicely',
            text: 'Ask nicely to share',
            isDeEscalation: true,
            nextNode: level2PositiveNode,
          ),
          ChoiceOption(
            id: 'tell_teacher',
            text: 'Tell the teacher',
            isDeEscalation: false,
            nextNode: level2NeutralNode,
          ),
          ChoiceOption(
            id: 'grab_back',
            text: 'Grab it back',
            isDeEscalation: false,
            nextNode: null,
          ),
        ],
      );
    }
  }

  // ── Display ───────────────────────────────────────────────────────────────

  void _displayChoices(ChoiceNode node) {
    _promptText.text = node.prompt;

    for (final button in _currentButtons) {
      button.removeFromParent();
    }
    _currentButtons.clear();
    _choiceElapsedTime = 0.0;

    final w = size.x;
    final h = size.y;

    const buttonH  = 62.0;
    const buttonSpacing = 16.0;
    // Buttons start below the "Choose how to respond" label
    final startY = h * 0.58;

    for (int i = 0; i < node.choices.length; i++) {
      final choice = node.choices[i];
      final yPos = startY + i * (buttonH + buttonSpacing);

      final button = ChoiceButton(
        text: choice.text,
        position: Vector2(w / 2, yPos),
        size: Vector2(w * 0.72, buttonH),
        // Green for de-escalation, amber for escalation
        color: choice.isDeEscalation ? _kGoodChoiceColor : _kBadChoiceColor,
        onTap: () => _onChoiceSelected(i),
      );

      _currentButtons.add(button);
      add(button);
    }
  }

  // ── Choice handling ───────────────────────────────────────────────────────

  void _onChoiceSelected(int choiceIndex) {
    if (isComplete || _celebrationStarted) return;

    final node = _currentNode!;
    final choice = node.choices[choiceIndex];

    _choiceHistory.add(choice.id);
    _telemetry.recordAction('choice_${choice.id}', elapsedMs);
    _totalChoices++;

    if (choice.isDeEscalation) {
      _deEscalationCount++;
      _spawnGoodBurst();
      _playAudio(_kAudioGood);
      _userAvatarComp?.showHappy();
      _friendAvatarComp?.showHappy();
    } else {
      _flashBadChoice();
      _playAudio(_kAudioBad);
      _userAvatarComp?.showSad();
      _friendAvatarComp?.showAngry();
    }

    if (choice.nextNode != null) {
      // Slight delay so the reaction is visible before the next prompt
      Future.delayed(const Duration(milliseconds: 420), () {
        if (!isComplete && !_celebrationStarted) {
          _currentNode = choice.nextNode;
          _displayChoices(_currentNode!);
        }
      });
    } else {
      Future.delayed(const Duration(milliseconds: 420), _evaluateOutcome);
    }
  }

  void _spawnGoodBurst() {
    final origin = Vector2(size.x / 2, size.y * 0.35);
    add(ParticleSystemComponent(
      position: origin,
      priority: 10,
      particle: Particle.generate(
        count: 14,
        lifespan: 0.75,
        generator: (i) {
          final angle = (i / 14) * pi * 2 + _rng.nextDouble() * 0.4;
          final speed = 65.0 + _rng.nextDouble() * 55.0;
          return AcceleratedParticle(
            speed: Vector2(cos(angle) * speed, sin(angle) * speed),
            acceleration: Vector2(0, 80),
            child: ScalingParticle(
              to: 0,
              child: CircleParticle(
                radius: 5 + _rng.nextDouble() * 4,
                paint: Paint()
                  ..color = _kStarColors[_rng.nextInt(_kStarColors.length)],
              ),
            ),
          );
        },
      ),
    ));
  }

  void _flashBadChoice() {
    // Brief amber overlay flash using a short-lived rect
    final flash = _FlashRectComponent(
      size: size.clone(),
      color: const Color(0x55FF8F00),
      durationSeconds: 0.35,
      priority: 15,
    );
    add(flash);
  }

  // ── Outcome ───────────────────────────────────────────────────────────────

  void _evaluateOutcome() {
    if (_celebrationStarted) return;
    _celebrationStarted = true;

    final cooperationRatio =
        _totalChoices > 0 ? _deEscalationCount / _totalChoices : 0.0;
    final success = cooperationRatio > 0.5;
    final reward  = cooperationRatio.clamp(0.0, 1.0);

    _telemetry.toJson()['choice_history']      = _choiceHistory;
    _telemetry.toJson()['cooperation_ratio']   = cooperationRatio;
    _telemetry.toJson()['total_choices']       = _totalChoices;
    _telemetry.toJson()['de_escalation_count'] = _deEscalationCount;

    if (success) {
      _playAudio(_kAudioFanfare);
      _userAvatarComp?.showHappy();
      _friendAvatarComp?.showHappy();
      for (int i = 0; i < 3; i++) {
        Future.delayed(Duration(milliseconds: i * 210), () {
          _spawnGoodBurst();
        });
      }
    }

    add(_ResultBannerComponent(
      center: Vector2(size.x / 2, size.y / 2),
      success: success,
      onDone: () => completeScenario(success, reward, telemetry: _telemetry.toJson()),
      priority: 20,
    ));
  }

  @override
  void updateScenario(double dt) {
    if (_timeLimitSeconds != null && !isComplete && !_celebrationStarted) {
      _choiceElapsedTime += dt;
      if (_choiceElapsedTime >= _timeLimitSeconds!) {
        _telemetry.recordAction('timeout', elapsedMs);
        _totalChoices++;
        _evaluateOutcome();
      }
    }
  }

  void _playAudio(String path) {
    FlameAudio.play(path).catchError((_) => AudioPlayer());
  }
}

// ── Scene avatar component ────────────────────────────────────────────────────

/// Small avatar sprite with idle bob and basic emotion swaps.
class _SceneAvatarComponent extends PositionComponent {
  final String spritePath;
  final String avatarType;
  final String label;
  final Color labelColor;

  SpriteComponent? _neutral;
  SpriteComponent? _happy;
  SpriteComponent? _sad;
  SpriteComponent? _angry;
  double _bobT = 0.0;

  _SceneAvatarComponent({
    required this.spritePath,
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
      final s = await _loadSprite(spritePath);
      _neutral = SpriteComponent(
          sprite: s, size: size, anchor: Anchor.center, position: size / 2);
      add(_neutral!);
    } catch (_) {}

    for (final entry in {
      'happy':  (SpriteComponent c) => _happy  = c,
      'sad':    (SpriteComponent c) => _sad    = c,
      'angry':  (SpriteComponent c) => _angry  = c,
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

    add(TextComponent(
      text: label,
      anchor: Anchor.topCenter,
      position: Vector2(size.x / 2, size.y + 4),
      textRenderer: TextPaint(
        style: TextStyle(
          color: labelColor,
          fontSize: 13,
          fontWeight: FontWeight.bold,
          shadows: const [Shadow(color: Colors.black45, blurRadius: 3)],
        ),
      ),
    ));
  }

  @override
  void update(double dt) {
    super.update(dt);
    _bobT += dt * 1.4;
    final bob = sin(_bobT) * 2.5;
    for (final c in [_neutral, _happy, _sad, _angry]) {
      if (c != null) c.position.y = size.y / 2 + bob;
    }
  }

  void showHappy()  => _swapTo(_happy,  autoResetMs: 1400);
  void showSad()    => _swapTo(_sad,    autoResetMs: 1400);
  void showAngry()  => _swapTo(_angry,  autoResetMs: 1400);

  void _swapTo(SpriteComponent? target, {int? autoResetMs}) {
    _neutral?.opacity = 0.0;
    _happy?.opacity   = 0.0;
    _sad?.opacity     = 0.0;
    _angry?.opacity   = 0.0;
    target?.opacity   = 1.0;
    target?.add(ScaleEffect.to(
      Vector2.all(1.14),
      EffectController(duration: 0.2, reverseDuration: 0.2, curve: Curves.elasticOut),
    ));
    if (autoResetMs != null) {
      Future.delayed(Duration(milliseconds: autoResetMs), () {
        _neutral?.opacity = 1.0;
        _happy?.opacity   = 0.0;
        _sad?.opacity     = 0.0;
        _angry?.opacity   = 0.0;
      });
    }
  }
}

// ── Prompt panel (semi-transparent card behind prompt text) ───────────────────

class _PromptPanelComponent extends PositionComponent {
  final double panelWidth;
  final double panelHeight;

  _PromptPanelComponent({
    required Vector2 position,
    required this.panelWidth,
    required this.panelHeight,
    super.priority,
  }) : super(
          position: position,
          size: Vector2(panelWidth, panelHeight),
          anchor: Anchor.center,
        );

  @override
  void render(Canvas canvas) {
    final rect =
        Rect.fromCenter(center: Offset.zero, width: panelWidth, height: panelHeight);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(16)),
      Paint()..color = const Color(0xD0FFFFFF),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(16)),
      Paint()
        ..color = const Color(0x551565C0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }
}

// ── Flash rect (briefly overlays screen on bad choice) ────────────────────────

class _FlashRectComponent extends PositionComponent {
  final Color color;
  final double durationSeconds;
  double _elapsed = 0.0;

  _FlashRectComponent({
    required Vector2 size,
    required this.color,
    required this.durationSeconds,
    super.priority,
  }) : super(position: Vector2.zero(), size: size);

  @override
  void update(double dt) {
    _elapsed += dt;
    if (_elapsed >= durationSeconds) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final progress = _elapsed / durationSeconds;
    final alpha = (color.a * (1.0 - progress)).clamp(0.0, 1.0);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.x, size.y),
      Paint()..color = color.withValues(alpha: alpha),
    );
  }
}

// ── Result banner ─────────────────────────────────────────────────────────────

class _ResultBannerComponent extends PositionComponent {
  final VoidCallback onDone;
  final bool success;
  double _elapsed = 0.0;
  bool _doneFired = false;
  static const _kShow = 2.4;

  _ResultBannerComponent({
    required Vector2 center,
    required this.onDone,
    required this.success,
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
    final bgColor = success
        ? const Color(0xF01565C0)  // blue
        : const Color(0xF0E65100); // deep orange

    final rect =
        Rect.fromCenter(center: Offset.zero, width: size.x, height: size.y);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(24)),
      Paint()..color = bgColor,
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
      success ? '🌟 Well Done! 🌟' : '😬 Try Again!',
      const TextStyle(
        color: Colors.white,
        fontSize: 30,
        fontWeight: FontWeight.w900,
        shadows: [Shadow(color: Colors.black38, blurRadius: 6)],
      ),
      -size.y / 2 + 28,
    );
    drawText(
      success
          ? 'Great de-escalation! 🎉'
          : 'Kind words help! 💛',
      const TextStyle(
        color: Color(0xFFBBDEFB),
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
      10,
    );
  }
}

// ── Flipped speech bubble (tail points right) ─────────────────────────────────

class _FlippedBubbleComponent extends PositionComponent {
  final Sprite sprite;

  _FlippedBubbleComponent({
    required this.sprite,
    required Vector2 size,
    required Vector2 position,
    super.priority,
  }) : super(position: position, size: size, anchor: Anchor.centerLeft);

  @override
  void render(Canvas canvas) {
    canvas.save();
    // Mirror horizontally around the component centre so the tail points right
    canvas.translate(size.x, 0);
    canvas.scale(-1, 1);
    sprite.render(canvas, size: size);
    canvas.restore();
  }
}

// ── Drawn right-pointing bubble fallback ─────────────────────────────────────

class _DrawnBubbleRight extends PositionComponent {
  final double bubbleWidth;
  final double bubbleHeight;

  _DrawnBubbleRight({
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
      ..addRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), const Radius.circular(12)));
    canvas.drawPath(path, Paint()..color = const Color(0xF0FFFFFF));
    // Right-pointing tail
    final tail = Path()
      ..moveTo(w, h / 2 - 10)
      ..lineTo(w + 14, h / 2)
      ..lineTo(w, h / 2 + 10)
      ..close();
    canvas.drawPath(tail, Paint()..color = const Color(0xF0FFFFFF));
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), const Radius.circular(12)),
      Paint()
        ..color = const Color(0xFF1565C0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
  }
}
