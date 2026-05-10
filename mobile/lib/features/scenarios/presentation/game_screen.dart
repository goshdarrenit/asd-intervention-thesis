import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import '../game/base_scenario_game.dart';
import '../game/game_config.dart';
import '../game/scenarios/sharing_game.dart';
import '../game/scenarios/patience_game.dart';
import '../game/scenarios/emotion_recognition_game.dart';
import '../game/scenarios/turn_taking_game.dart';
import '../game/scenarios/conflict_resolution_game.dart';
import 'pause_overlay.dart';
import 'outcome_overlay.dart';
import 'hint_overlay.dart';


/// GameWidget.controlled for proper lifecycle management (not build-time instantiation)
/// RepaintBoundary for performance optimization
/// Overlay system: PauseMenu and OutcomeScreen
/// Always-visible exit button in top-right corner
/// SafeArea wrapper for notch/status bar handling
class GameScreen extends StatefulWidget {
  /// Game configuration
  final GameConfig config;

  /// Callback when game completes with outcome data
  final Function(ScenarioOutcome) onGameComplete;

  /// Optional callback when user quits from pause menu.
  /// If null, defaults to Navigator.popUntil(isFirst).
  /// SessionWrapper provides this to call endSession() first.
  final VoidCallback? onQuit;

  const GameScreen({
    super.key,
    required this.config,
    required this.onGameComplete,
    this.onQuit,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final BaseScenarioGame _game;

  @override
  void initState() {
    super.initState();
    // Create game instance once in initState (not in build)
    _game = _createGameFromConfig(widget.config);
  }

  /// Factory method to create game from configuration
  BaseScenarioGame _createGameFromConfig(GameConfig config) {
    switch (config.scenarioType) {
      case 'sharing':
        return SharingGame(config: config);
      case 'patience':
        return PatienceGame(config: config);
      case 'emotion_recognition':
        return EmotionRecognitionGame(config: config);
      case 'turn_taking':
        return TurnTakingGame(config: config);
      case 'conflict_resolution':
        return ConflictResolutionGame(config: config);
      default:
        return _StubScenarioGame(config: config);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // Flame GameWidget with RepaintBoundary for performance
            RepaintBoundary(
              child: GameWidget<BaseScenarioGame>.controlled(
                gameFactory: () => _game,
                overlayBuilderMap: {
                  'PauseMenu': (context, game) => PauseOverlay(
                        game: game,
                        onResume: () => game.hidePauseMenu(),
                        // Pop all the way back to main menu (pops game + session wrapper)
                        onQuit: widget.onQuit ?? () => Navigator.popUntil(context, (route) => route.isFirst),
                      ),
                  'OutcomeScreen': (context, game) => OutcomeOverlay(
                        game: game,
                        onContinue: () {
                          final outcome = game.outcome!;
                          Navigator.pop(context);
                          widget.onGameComplete(outcome);
                        },
                      ),
                  'HintOverlay': (context, game) => HintOverlay(game: game),
                },
              ),
            ),

            // Always-visible exit button
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, size: 32),
                onPressed: () => _game.showPauseMenu(),
                tooltip: 'Pause',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withAlpha(204), // 0.8 opacity
                  foregroundColor: Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// This allows testing the game infrastructure without actual scenario logic
class _StubScenarioGame extends BaseScenarioGame {
  _StubScenarioGame({required super.config});

  @override
  Future<void> loadScenario() async {
    await super.loadScenario();
  }

  @override
  void updateScenario(double dt) {
    super.updateScenario(dt);
  }
}
