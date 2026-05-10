import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/session_manager.dart';
import '../providers.dart';
import '../../home/providers.dart';
import '../../auth/providers.dart';
import '../../auth/presentation/login_screen.dart';
import '../../scenarios/presentation/game_screen.dart';
import '../../scenarios/game/game_config.dart';
import '../../scenarios/data/scenario_api_service.dart';
import '../../scenarios/providers.dart';
import '../../profile/data/profile_local_datasource.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/accessible_button.dart';

/// Session wrapper that manages session limits and game play.
///
/// Supports two modes:
/// - New session: [resumeSession] == null — ends any old active session and
///   starts a fresh one, then immediately auto-navigates to the first game.
/// - Resume session: [resumeSession] is the DB row of a paused session —
///   recreates a [SessionManager] with the original start time and scenario
///   count, then shows the between-game UI so the user can choose to continue.
///
/// Profile progress is updated incrementally inside [SessionManager] after every
/// scenario, so navigating back to the menu never loses progress.
class SessionWrapper extends ConsumerStatefulWidget {
  /// When set, resumes an existing paused session instead of creating a new one.
  final Map<String, dynamic>? resumeSession;

  const SessionWrapper({super.key, this.resumeSession});

  @override
  ConsumerState<SessionWrapper> createState() => _SessionWrapperState();
}

class _SessionWrapperState extends ConsumerState<SessionWrapper> {
  SessionManager? _sessionManager;
  ScenarioApiService? _scenarioApiService;
  Timer? _updateTimer;
  String _remainingTimeText = '30:00';
  int _remainingScenariosCount = 20;
  bool _isLoading = true;

  /// Prevents multiple simultaneous navigation pushes.
  bool _isNavigating = false;

  /// True if this is a new session (not a resume) so we auto-start the first game.
  bool _shouldAutoStart = false;

  /// Current scenario config for submit.
  GameConfig? _currentScenarioConfig;

  @override
  void initState() {
    super.initState();
    _initializeSession();
  }

  /// Build the [SessionManager] from either an existing session (resume) or a
  /// brand-new one, and start the countdown timer.
  Future<void> _initializeSession() async {
    try {
      final userId = await ref.read(userIdProvider.future);
      final db = await ref.read(databaseProvider.future);
      final profileDataSource = ProfileLocalDataSource(db);
      final repository = await ref.read(sessionRepositoryProvider.future);
      final apiService = await ref.read(scenarioApiServiceProvider.future);

      String sessionId;
      DateTime startTime;
      int initialCompleted;

      if (widget.resumeSession != null) {
        // ── Resume existing session ─────────────────────────────────────
        final data = widget.resumeSession!;
        final remoteSessionId = data['remote_session_id'] as String?;
        sessionId = (remoteSessionId != null && remoteSessionId.isNotEmpty)
          ? remoteSessionId
          : data['id'] as String;
        startTime =
            DateTime.fromMillisecondsSinceEpoch(data['started_at'] as int);
        initialCompleted = (data['scenarios_completed'] as int?) ?? 0;
        _shouldAutoStart = false; // Let the user decide when to play next
      } else {
        // ── New session ─────────────────────────────────────────────────
        // End any existing open session so the DB stays tidy.
        final existing = await repository.getActiveSession(userId);
        if (existing != null) {
          await repository.endSession(existing['id'] as String);
        }

        sessionId = await repository.startSession(userId);
        startTime = DateTime.now();
        initialCompleted = 0;
        _shouldAutoStart = true; // Jump straight into the first game
      }

      final manager = SessionManager(
        repository: repository,
        profileDataSource: profileDataSource,
        sessionId: sessionId,
        userId: userId,
        startTime: startTime,
        initialCompleted: initialCompleted,
      );
      await manager.start();

      if (mounted) {
        setState(() {
          _sessionManager = manager;
          _scenarioApiService = apiService;
          _isLoading = false;
        });

        // Tick the clock display every second
        _updateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted && _sessionManager != null) {
            setState(() => _updateTimerDisplay());
          }
        });

        if (_shouldAutoStart) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _onPlayNextScenario();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorDialog();
      }
    }
  }

  /// Refresh the top-bar time and scenario counters.
  void _updateTimerDisplay() {
    if (_sessionManager == null) return;

    final remaining = _sessionManager!.remainingTime;
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;

    _remainingTimeText =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    _remainingScenariosCount = _sessionManager!.remainingScenarios;

    // Time expired — show dialog
    if (!_sessionManager!.canPlayNextScenario() && remaining.inSeconds <= 0) {
      _updateTimer?.cancel();
      _showEndOfSessionDialog(SessionStatus.timeLimitReached);
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    // Do NOT call endSession() here.
    // The session stays open in the DB so it can be resumed from the main menu.
    // It is ended explicitly when: the time/scenario limit is reached, or the
    // user starts a brand-new session (which ends any open session first).
    _sessionManager?.dispose(); // cancels the internal timer only
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                widget.resumeSession != null
                    ? 'Resuming your session...'
                    : 'Setting up your session...',
              ),
            ],
          ),
        ),
      );
    }

    if (_sessionManager == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Failed to start session'),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Back to Menu'),
              ),
            ],
          ),
        ),
      );
    }

    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.background,
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.textSecondary.withAlpha(51),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Home button
                  IconButton(
                    icon: const Icon(Icons.home_rounded),
                    tooltip: 'Main Menu',
                    onPressed: () => Navigator.pop(context),
                    style: IconButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                    ),
                  ),

                  IconButton(
                    icon: const Icon(Icons.stop_circle_outlined),
                    tooltip: 'End Session',
                    onPressed: _onEndSessionPressed,
                    style: IconButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                    ),
                  ),

                  IconButton(
                    icon: const Icon(Icons.logout_rounded),
                    tooltip: 'Log Out',
                    onPressed: _onLogoutPressed,
                    style: IconButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                    ),
                  ),

                  const Spacer(),

                  // Time remaining
                  Row(
                    children: [
                      Icon(Icons.timer_outlined,
                          color: AppColors.textPrimary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        _remainingTimeText,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(width: 24),

                  // Scenarios remaining
                  Row(
                    children: [
                      Icon(Icons.grid_view_rounded,
                          color: AppColors.textPrimary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '$_remainingScenariosCount/20',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Content ──────────────────────────────────────────────────
            Expanded(
              child: _isNavigating
                  ? const Center(child: CircularProgressIndicator())
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Ready for the next scenario?',
                            style: theme.textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 32),

                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 24),
                            child: AccessibleButton(
                              label: 'Play Next Scenario',
                              icon: Icons.play_arrow_rounded,
                              variant: AccessibleButtonVariant.primary,
                              onPressed: _onPlayNextScenario,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Request next scenario from backend and launch game.
  Future<void> _onPlayNextScenario() async {
    if (_isNavigating) return;
    if (_sessionManager == null || _scenarioApiService == null) return;

    if (!_sessionManager!.canPlayNextScenario()) {
      _showEndOfSessionDialog(SessionStatus.scenarioLimitReached);
      return;
    }

    setState(() => _isNavigating = true);

    try {
      final userId = await ref.read(userIdProvider.future);

      // Pass forceEasier flag after 3 consecutive failures
      final shouldForce = _sessionManager!.shouldForceEasier;
      final config = await _scenarioApiService!.getNextScenario(
        userId,
        _sessionManager!.sessionId,
        forceEasier: shouldForce,
      );

      // Reset counter after we've applied the force-easier intervention
      if (shouldForce) {
        _sessionManager!.resetConsecutiveFailures();
      }

      _currentScenarioConfig = config;

      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GameScreen(
              config: config,
              onGameComplete: _onGameComplete,
              onQuit: () async {                   // graceful exit from pause
                await _sessionManager!.endSession();
                if (context.mounted) {
                  Navigator.popUntil(context, (r) => r.isFirst);
                }
              },
            ),
          ),
        );

        if (mounted) setState(() => _isNavigating = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isNavigating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to load scenario. Please try again.')),
        );
      }
    }
  }

  Future<void> _onEndSessionPressed() async {
    final shouldEnd = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End session now?'),
        content: const Text('Your current session will be ended and you will return to the menu.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('End Session'),
          ),
        ],
      ),
    );

    if (shouldEnd != true || _sessionManager == null) return;

    await _sessionManager!.endSession();
    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _onLogoutPressed() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('This will end your current session and return you to the sign-in screen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (shouldLogout != true) return;

    if (_sessionManager != null && !_sessionManager!.isEnded) {
      await _sessionManager!.endSession();
    }

    await ref.read(loginProvider.notifier).logout();

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  /// Handle game completion callback.
  Future<void> _onGameComplete(ScenarioOutcome outcome) async {
    if (_sessionManager == null || _scenarioApiService == null) return;

    Map<String, dynamic>? submitResponse;
    try {
      final userId = await ref.read(userIdProvider.future);
      submitResponse = await _scenarioApiService!.submitResult(
        userId: userId,
        sessionId: _sessionManager!.sessionId,
        outcome: outcome,
        complexity: _currentScenarioConfig?.complexity ?? 'low',
        reinforcementMode:
            _currentScenarioConfig?.reinforcementMode ?? 'positive',
      );
    } catch (e) {
      // Offline — already saved locally
    }

    // Backend ended session after 3 consecutive failures — handle locally
    if (submitResponse != null && submitResponse['force_ended'] == true) {
      await _sessionManager!.endSession();
      if (mounted) {
        _showForceEndedDialog();  // inform user before navigating
      }
      return;  // do NOT record completion — session already closed server-side
    }

    // Frustration detection — only when online response available
    if (submitResponse != null && mounted) {
      final emotions = submitResponse['emotions'] as Map<String, dynamic>?;
      final frustration = (emotions?['frustration'] as num?)?.toDouble() ?? 0.0;
      if (frustration > 0.7) {
        final tookBreak = await _showBreakOfferDialog();
        if (tookBreak) return;  // user took break; endSession() already called inside dialog
      }
    }

    final status = await _sessionManager!.recordScenarioCompletion(outcome);

    // Consecutive failure intervention info
    if (_sessionManager!.shouldForceEasier && mounted) {
      _showConsecutiveFailureDialog();
      // NOTE: do NOT reset here — reset happens in _onPlayNextScenario when fetching next scenario
    }

    if (status == SessionStatus.continuePlay) {
      if (mounted) setState(() => _updateTimerDisplay());
    } else {
      if (mounted) _showEndOfSessionDialog(status);
    }
  }

  /// Show break offer dialog.
  ///
  /// Returns true if user chose to take a break (session ended).
  /// Returns false if user chose to keep playing.
  /// Uses ASD-friendly non-stigmatizing language.
  Future<bool> _showBreakOfferDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('How are you feeling?'),
        content: const Text(
          'This one is tricky! Would you like to take a short break?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Playing'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Take a Break'),
          ),
        ],
      ),
    );

    final tookBreak = result ?? false;
    if (tookBreak) {
      await _sessionManager!.endSession();
      if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
    }
    return tookBreak;
  }

  /// Show consecutive failure info dialog.
  ///
  /// Informs user we're trying a different (easier) scenario next.
  /// ASD-friendly language: consequence-framing, not stigmatizing.
  void _showConsecutiveFailureDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Let's try something different"),
        content: const Text(
          "We'll try an easier version next. You've got this!",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Inform the user that the session has ended due to 3 consecutive failures.
  ///
  /// This dialog is shown when the backend sets ended_reason='intervention'.
  /// After dismissal, navigate to main menu. Session already ended locally above.
  /// Uses ASD-friendly consequence-framing language.
  void _showForceEndedDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Time for a rest!"),
        content: const Text(
          "You've worked really hard today. Let's take a break and try again later.",
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Show end-of-session dialog.
  void _showEndOfSessionDialog(SessionStatus status) {
    String title;
    String message;

    switch (status) {
      case SessionStatus.timeLimitReached:
        title = 'Time\'s Up!';
        message = 'Great job playing for 30 minutes today! 🎉';
        break;
      case SessionStatus.scenarioLimitReached:
        title = 'Amazing Work!';
        message = 'You completed 20 scenarios! That\'s fantastic! 🌟';
        break;
      default:
        title = 'Great Session!';
        message = 'You did wonderful today! 👏';
    }

    if (_sessionManager != null) {
      final completed = _sessionManager!.scenariosCompleted;
      final elapsed = _sessionManager!.elapsedTime;
      message +=
          '\n\nYou completed $completed scenario${completed == 1 ? '' : 's'} in ${elapsed.inMinutes} minute${elapsed.inMinutes == 1 ? '' : 's'}.';
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Return to main menu
            },
            child: const Text('Back to Menu'),
          ),
        ],
      ),
    );
  }

  /// Show error dialog and return to menu.
  void _showErrorDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Session Error'),
        content: const Text('Failed to start session. Please try again.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
