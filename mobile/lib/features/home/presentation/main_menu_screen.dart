import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../providers.dart';
import 'progress_card.dart';
import '../../../shared/widgets/accessible_button.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../session/presentation/session_wrapper.dart';
import '../../session/providers.dart';
import '../../progress/presentation/progress_dashboard_screen.dart';
import '../../progress/providers.dart';
import '../../auth/providers.dart';
import '../../auth/presentation/login_screen.dart';
import '../../avatar/avatar_provider.dart';

/// Main menu screen with progress indicators, play button, and optional
/// "Continue Session" button when a resumable session exists.
class MainMenuScreen extends ConsumerStatefulWidget {
  const MainMenuScreen({super.key});

  @override
  ConsumerState<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends ConsumerState<MainMenuScreen> {
  bool _isNavigating = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progressAsync = ref.watch(userProgressProvider);
    final resumableAsync = ref.watch(resumableSessionProvider);
    final avatarAsync = ref.watch(avatarProvider);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),

              // App title
              Row(
                children: [
                  const Spacer(),
                  Expanded(
                    flex: 8,
                    child: Text(
                      'Social Skills Adventure',
                      style: theme.textTheme.displayLarge,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primaryLight.withAlpha(60),
                              border: Border.all(
                                color: AppColors.primary,
                                width: 2,
                              ),
                            ),
                            child: ClipOval(
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Image.asset(
                                  avatarAssetPath(
                                    avatarAsync.asData?.value ?? defaultAvatarKey,
                                  ),
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.logout_rounded, size: 18),
                            tooltip: 'Log Out',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: _onLogoutPressed,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Text(
                "Let's practice together!",
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.normal,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),

              // Progress section
              RepaintBoundary(
                child: progressAsync.when(
                  data: (progress) => _buildProgressSection(progress),
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: AppLoadingIndicator(),
                    ),
                  ),
                  error: (_, __) =>
                      _buildProgressSection(const UserProgress()),
                ),
              ),
              const SizedBox(height: 48),

              // ── Resumable session banner ─────────────────────────────
              resumableAsync.when(
                data: (session) {
                  if (session == null) return const SizedBox.shrink();
                  return _buildResumeBanner(context, session, theme);
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),

              // ── Play / Start button ──────────────────────────────────
              AccessibleButton(
                label: _isNavigating ? 'Loading...' : 'Start New Session',
                icon: Icons.play_arrow_rounded,
                variant: AccessibleButtonVariant.primary,
                onPressed: _isNavigating ? null : () => _onStartPlaying(context),
              ),
              const SizedBox(height: 12),

              // Progress dashboard button
              AccessibleButton(
                label: 'My Progress',
                icon: Icons.bar_chart_rounded,
                variant: AccessibleButtonVariant.outline,
                onPressed: _isNavigating ? null : () => _onViewProgress(context),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  /// Banner shown when a resumable session is available.
  Widget _buildResumeBanner(
    BuildContext context,
    Map<String, dynamic> session,
    ThemeData theme,
  ) {
    final startedAt = (session['started_at'] as int?) ?? 0;
    final elapsedMs = DateTime.now().millisecondsSinceEpoch - startedAt;
    final remainingMs = (30 * 60 * 1000) - elapsedMs;
    final remainingMin = (remainingMs / 60000).ceil().clamp(0, 30);
    final scenariosDone = (session['scenarios_completed'] as int?) ?? 0;
    final scenariosLeft = (20 - scenariosDone).clamp(0, 20);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: Colors.amber.shade50,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.amber.shade300, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.restore_rounded,
                      color: Colors.amber.shade800, size: 24),
                  const SizedBox(width: 10),
                  Text(
                    'Session in progress',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.amber.shade900,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '$remainingMin min remaining • $scenariosLeft scenario${scenariosLeft == 1 ? '' : 's'} left',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.amber.shade800,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.play_circle_outline_rounded),
                  label: const Text('Continue Session'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed:
                      _isNavigating ? null : () => _onResumeSession(context, session),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressSection(UserProgress progress) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Expanded(
          child: ProgressCard(
            label: 'Scenarios',
            value: progress.scenariosCompleted.toString(),
            icon: Icons.emoji_events_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ProgressCard(
            label: 'Level',
            value: progress.currentLevel.toString(),
            icon: Icons.star_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ProgressCard(
            label: 'Success',
            value: '${(progress.successRate * 100).toStringAsFixed(0)}%',
            icon: Icons.trending_up_rounded,
          ),
        ),
      ],
    );
  }

  /// Navigate to a new session. Invalidates the resumable session cache on return.
  Future<void> _onStartPlaying(BuildContext context) async {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SessionWrapper()),
    );

    if (mounted) {
      setState(() => _isNavigating = false);
      // Refresh progress and resumable session check
      ref.invalidate(userProgressProvider);
      ref.invalidate(resumableSessionProvider);
    }
  }

  /// Resume an existing in-progress session.
  Future<void> _onResumeSession(
    BuildContext context,
    Map<String, dynamic> session,
  ) async {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SessionWrapper(resumeSession: session),
      ),
    );

    if (mounted) {
      setState(() => _isNavigating = false);
      ref.invalidate(userProgressProvider);
      ref.invalidate(resumableSessionProvider);
    }
  }

  /// Navigate to the progress dashboard.
  /// Invalidates the cache so the screen always reflects the latest DB state.
  void _onViewProgress(BuildContext context) {
    ref.invalidate(dashboardDataProvider);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ProgressDashboardScreen(),
      ),
    );
  }

  Future<void> _onLogoutPressed() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will return to the sign-in screen.'),
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

    await ref.read(loginProvider.notifier).logout();
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }
}
