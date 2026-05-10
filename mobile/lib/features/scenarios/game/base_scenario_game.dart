import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'game_config.dart';

/// Base Flame game class for scenario games
///
/// Features:
/// - Performance-optimized game loop with pre-allocated objects (60 FPS target)
/// - Lifecycle management: pause on app background, resume on foreground
/// - Overlay management: pause menu, outcome screen
///
/// Performance patterns:
/// - Pre-allocated Vector2 objects prevent GC jank in update loop
/// - Never create Vector2(x, y) inside update() or render()
/// - Use _tempVelocity.setValues(x, y) instead for temp calculations
abstract class BaseScenarioGame extends FlameGame with HasCollisionDetection {
  /// Game configuration
  final GameConfig config;

  /// Whether the game is currently paused
  bool _isPaused = false;

  /// Whether the scenario is complete
  bool _isComplete = false;

  /// Outcome data when scenario completes
  ScenarioOutcome? outcome;

  /// Game timer for tracking elapsed time
  late final Stopwatch _gameTimer;

  /// Elapsed time in milliseconds
  int _elapsedMs = 0;

  // Pre-allocated Vector2 objects for performance
  // Use these in subclasses instead of creating new Vector2 instances in update loop
  late final Vector2 _tempVelocity;
  late final Vector2 _tempPosition;

  /// Create a new scenario game with the given configuration
  BaseScenarioGame({required this.config});

  /// Getter for pre-allocated velocity vector
  /// Use this in update() instead of creating new Vector2 instances
  Vector2 get tempVelocity => _tempVelocity;

  /// Getter for pre-allocated position vector
  /// Use this in update() instead of creating new Vector2 instances
  Vector2 get tempPosition => _tempPosition;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Initialize game timer
    _gameTimer = Stopwatch()..start();

    // Pre-allocate reusable Vector2 objects
    _tempVelocity = Vector2.zero();
    _tempPosition = Vector2.zero();

    // Subclasses override loadScenario() to add their specific components
    await loadScenario();
  }

  @override
  void update(double dt) {
    // Skip update if game is paused or complete
    if (_isPaused || _isComplete) return;

    super.update(dt);

    // Update elapsed time
    _elapsedMs = _gameTimer.elapsedMilliseconds;

    // Subclasses override updateScenario(dt) for game-specific logic
    updateScenario(dt);
  }

  @override
  void lifecycleStateChange(AppLifecycleState state) {
    super.lifecycleStateChange(state);

    // Pause game when app goes to background
    if (state == AppLifecycleState.paused) {
      if (!_isPaused && !_isComplete) {
        showPauseMenu();
      }
    }
    // Do NOT auto-resume - user must tap resume button
  }

  /// Show the pause menu overlay
  void showPauseMenu() {
    if (_isComplete) return; // Don't pause if already complete

    _isPaused = true;
    _gameTimer.stop();
    overlays.add('PauseMenu');
    pauseEngine();
  }

  /// Hide the pause menu overlay and resume game
  void hidePauseMenu() {
    _isPaused = false;
    _gameTimer.start();
    overlays.remove('PauseMenu');
    resumeEngine();
  }

  /// Complete the scenario and show outcome overlay
  ///
  /// [success] - Whether the scenario was completed successfully
  /// [reward] - Reward value from 0.0 to 1.0
  /// [telemetry] - Optional behavioral telemetry data for emotion inference
  void completeScenario(
    bool success,
    double reward, {
    Map<String, dynamic> telemetry = const {},
  }) {
    if (_isComplete) return; // Already complete

    _isComplete = true;
    _gameTimer.stop();

    final completionTime = _gameTimer.elapsedMilliseconds;

    outcome = ScenarioOutcome(
      success: success,
      reward: reward,
      completionTimeMs: completionTime,
      scenarioType: config.scenarioType,
      difficulty: config.difficulty,
      telemetry: telemetry,
    );

    overlays.add('OutcomeScreen');
    pauseEngine();
  }

  /// Whether the game is currently paused
  bool get isPaused => _isPaused;

  /// Whether the scenario is complete
  bool get isComplete => _isComplete;

  /// Elapsed time in milliseconds
  int get elapsedMs => _elapsedMs;


  /// Override to load scenario-specific components
  /// Called once during onLoad()
  Future<void> loadScenario() async {
    // Subclasses override this
  }

  /// Override for scenario-specific update logic
  /// Called every frame during update() when not paused/complete
  void updateScenario(double dt) {
    // Subclasses override this
  }

  /// Override to handle user interactions
  /// Called by UI components when user takes an action
  void onUserAction(String action) {
    // Subclasses override this
  }

  // Test helpers - only for use in unit tests
  @visibleForTesting
  void setIsPausedForTest(bool value) {
    _isPaused = value;
  }

  @visibleForTesting
  void setIsCompleteForTest(bool value) {
    _isComplete = value;
  }
}
