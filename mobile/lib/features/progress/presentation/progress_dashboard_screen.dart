import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/accessible_card.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../avatar/avatar_provider.dart';
import '../providers.dart';

/// Progress dashboard screen displaying analytics and progression metrics.
///
/// Shows:
/// - Overall statistics (scenarios completed, success rate, level)
/// - Per-scenario breakdown with visual progress bars
/// - Emotional trend summary (frustration, engagement, confidence)
/// - Recent session history
///
class ProgressDashboardScreen extends ConsumerWidget {
  const ProgressDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dashboardAsync = ref.watch(dashboardDataProvider);

    return Scaffold(
      body: SafeArea(
        child: dashboardAsync.when(
          data: (data) => _buildDashboard(context, theme, data),
          loading: () => const Center(child: AppLoadingIndicator()),
          error: (_, __) => _buildDashboard(
            context,
            theme,
            DashboardData.empty(),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboard(
    BuildContext context,
    ThemeData theme,
    DashboardData data,
  ) {
    return CustomScrollView(
      slivers: [
        // Header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Column(
              children: [
                // Back button row
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Back',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Avatar centered at top
                const _AvatarSection(),
                const SizedBox(height: 16),
                Text(
                  'My Progress',
                  style: theme.textTheme.displayMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _getEncouragingMessage(data),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),

        // Overall stats row
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: _buildOverallStats(theme, data),
          ),
        ),

        // Level progress
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: _buildLevelProgress(theme, data),
          ),
        ),

        // Scenario breakdown
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: _buildScenarioBreakdown(theme, data),
          ),
        ),

        // Emotional wellbeing
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: _buildEmotionalWellbeing(theme, data),
          ),
        ),

        // Recent sessions
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: _buildRecentSessions(theme, data),
          ),
        ),

        // Achievements
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: _buildAchievements(theme, data),
          ),
        ),
      ],
    );
  }

  // ── Overall Stats ───────────────────────────────────────────────────

  Widget _buildOverallStats(ThemeData theme, DashboardData data) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.emoji_events_rounded,
            value: '${data.totalScenarios}',
            label: 'Completed',
            color: AppColors.rewardGold,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.trending_up_rounded,
            value: '${(data.overallSuccessRate * 100).toStringAsFixed(0)}%',
            label: 'Success',
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.timer_rounded,
            value: '${data.totalSessionsPlayed}',
            label: 'Sessions',
            color: AppColors.info,
          ),
        ),
      ],
    );
  }

  // ── Level Progress ──────────────────────────────────────────────────

  Widget _buildLevelProgress(ThemeData theme, DashboardData data) {
    final scenariosInLevel = data.totalScenarios % 10;
    final progress = scenariosInLevel / 10.0;

    return AccessibleCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star_rounded, color: AppColors.rewardGold, size: 28),
              const SizedBox(width: 12),
              Text('Level ${data.currentLevel}', style: theme.textTheme.titleLarge),
              const Spacer(),
              Text(
                '$scenariosInLevel / 10',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: AppColors.primaryLight.withAlpha(60),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.progressFill),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${10 - scenariosInLevel} more scenarios to Level ${data.currentLevel + 1}!',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ── Scenario Breakdown ──────────────────────────────────────────────

  Widget _buildScenarioBreakdown(ThemeData theme, DashboardData data) {
    return AccessibleCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Scenario Progress', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          ...data.scenarioStats.map(
            (stat) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _buildScenarioRow(theme, stat),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScenarioRow(ThemeData theme, ScenarioStat stat) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(stat.icon, size: 24, color: stat.color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                stat.displayName,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '${stat.completed} done',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const SizedBox(width: 34), // Align with text above
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: stat.successRate,
                  minHeight: 8,
                  backgroundColor: stat.color.withAlpha(40),
                  valueColor: AlwaysStoppedAnimation<Color>(stat.color),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 44,
              child: Text(
                '${(stat.successRate * 100).toStringAsFixed(0)}%',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: stat.color,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Emotional Wellbeing ─────────────────────────────────────────────

  Widget _buildEmotionalWellbeing(ThemeData theme, DashboardData data) {
    return AccessibleCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.favorite_rounded, color: AppColors.warning, size: 28),
              const SizedBox(width: 12),
              Text('Wellbeing', style: theme.textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 20),
          _buildEmotionBar(theme, 'Engagement', data.avgEngagement, AppColors.success),
          const SizedBox(height: 14),
          _buildEmotionBar(theme, 'Confidence', data.avgConfidence, AppColors.info),
          const SizedBox(height: 14),
          _buildEmotionBar(theme, 'Calm', 1.0 - data.avgFrustration, AppColors.secondary),
        ],
      ),
    );
  }

  Widget _buildEmotionBar(ThemeData theme, String label, double value, Color color) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: theme.textTheme.bodyLarge,
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: color.withAlpha(40),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 44,
          child: Text(
            '${(value.clamp(0.0, 1.0) * 100).toStringAsFixed(0)}%',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  // ── Recent Sessions ─────────────────────────────────────────────────

  Widget _buildRecentSessions(ThemeData theme, DashboardData data) {
    if (data.recentSessions.isEmpty) {
      return AccessibleCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(
              Icons.history_rounded,
              size: 40,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              'No sessions yet',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Start playing to see your history here!',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return AccessibleCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recent Sessions', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          ...data.recentSessions.map(
            (session) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildSessionRow(theme, session),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionRow(ThemeData theme, SessionSummary session) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primaryLight.withAlpha(80),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.play_circle_rounded,
            color: AppColors.primary,
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.dateLabel,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${session.scenariosPlayed} scenarios • ${session.durationMinutes} min',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _getSuccessColor(session.successRate).withAlpha(30),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${(session.successRate * 100).toStringAsFixed(0)}%',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: _getSuccessColor(session.successRate),
            ),
          ),
        ),
      ],
    );
  }

  Color _getSuccessColor(double rate) {
    if (rate >= 0.7) return AppColors.success;
    if (rate >= 0.4) return AppColors.warning;
    return AppColors.textSecondary;
  }

  // ── Achievements ────────────────────────────────────────────────────

  Widget _buildAchievements(ThemeData theme, DashboardData data) {
    final achievements = _calculateAchievements(data);

    return AccessibleCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_rounded, color: AppColors.rewardGold, size: 28),
              const SizedBox(width: 12),
              Text('Achievements', style: theme.textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: achievements.map((a) => _buildAchievementBadge(theme, a)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAchievementBadge(ThemeData theme, _Achievement achievement) {
    return Semantics(
      label: '${achievement.label}: ${achievement.unlocked ? "Unlocked" : "Locked"}',
      child: Opacity(
        opacity: achievement.unlocked ? 1.0 : 0.35,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: achievement.unlocked
                    ? achievement.color.withAlpha(40)
                    : AppColors.textSecondary.withAlpha(20),
                shape: BoxShape.circle,
                border: Border.all(
                  color: achievement.unlocked
                      ? achievement.color
                      : AppColors.textSecondary.withAlpha(50),
                  width: 2,
                ),
              ),
              child: Icon(
                achievement.icon,
                color: achievement.unlocked ? achievement.color : AppColors.textSecondary,
                size: 28,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 70,
              child: Text(
                achievement.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 12,
                  color: achievement.unlocked
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_Achievement> _calculateAchievements(DashboardData data) {
    return [
      _Achievement(
        icon: Icons.rocket_launch_rounded,
        label: 'First Step',
        color: AppColors.primary,
        unlocked: data.totalScenarios >= 1,
      ),
      _Achievement(
        icon: Icons.star_rounded,
        label: '10 Done',
        color: AppColors.rewardGold,
        unlocked: data.totalScenarios >= 10,
      ),
      _Achievement(
        icon: Icons.local_fire_department_rounded,
        label: '50 Done',
        color: AppColors.warning,
        unlocked: data.totalScenarios >= 50,
      ),
      _Achievement(
        icon: Icons.thumb_up_rounded,
        label: '70% Rate',
        color: AppColors.success,
        unlocked: data.overallSuccessRate >= 0.7 && data.totalScenarios >= 5,
      ),
      _Achievement(
        icon: Icons.diversity_3_rounded,
        label: 'All Types',
        color: AppColors.secondary,
        unlocked: data.scenarioStats.every((s) => s.completed > 0),
      ),
      _Achievement(
        icon: Icons.favorite_rounded,
        label: 'Stay Calm',
        color: AppColors.info,
        unlocked: data.avgFrustration < 0.3 && data.totalScenarios >= 5,
      ),
    ];
  }

  String _getEncouragingMessage(DashboardData data) {
    if (data.totalScenarios == 0) {
      return "Ready to start your adventure? Let's go!";
    }
    if (data.overallSuccessRate >= 0.8) {
      return "Amazing work! You're doing brilliantly! 🌟";
    }
    if (data.overallSuccessRate >= 0.5) {
      return "Great progress! Keep it up! 💪";
    }
    return "Every try helps you learn and grow! 🌱";
  }
}

// ── Private helper widgets ──────────────────────────────────────────────

/// Displays the selected avatar and a "Change Avatar" button.
class _AvatarSection extends ConsumerWidget {
  const _AvatarSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avatarKey = ref.watch(avatarProvider).asData?.value ?? defaultAvatarKey;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primaryLight.withAlpha(60),
            border: Border.all(color: AppColors.primary, width: 3),
          ),
          child: ClipOval(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Image.asset(
                avatarAssetPath(avatarKey),
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          icon: const Icon(Icons.edit_rounded, size: 16),
          label: const Text('Change Avatar'),
          onPressed: () => _showAvatarPicker(context, ref, avatarKey),
        ),
      ],
    );
  }

  void _showAvatarPicker(BuildContext context, WidgetRef ref, String currentKey) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AvatarPickerSheet(
        currentKey: currentKey,
        onSelected: (key) {
          ref.read(avatarProvider.notifier).setAvatar(key);
          Navigator.pop(context);
        },
      ),
    );
  }
}

class _AvatarPickerSheet extends StatefulWidget {
  final String currentKey;
  final void Function(String key) onSelected;

  const _AvatarPickerSheet({
    required this.currentKey,
    required this.onSelected,
  });

  @override
  State<_AvatarPickerSheet> createState() => _AvatarPickerSheetState();
}

class _AvatarPickerSheetState extends State<_AvatarPickerSheet> {
  late String _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentKey;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Choose your avatar', style: theme.textTheme.titleLarge),
          const SizedBox(height: 20),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 4,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.0,
            children: avatarKeys.map((key) {
              final isSelected = _selected == key;
              return GestureDetector(
                onTap: () => setState(() => _selected = key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: isSelected ? AppColors.surface : Colors.white,
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.primaryLight.withAlpha(100),
                      width: isSelected ? 3 : 1,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withAlpha(40),
                              blurRadius: 6,
                            )
                          ]
                        : null,
                  ),
                  padding: const EdgeInsets.all(8),
                  child: Image.asset(
                    avatarAssetPath(key),
                    fit: BoxFit.contain,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => widget.onSelected(_selected),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Save', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AccessibleCard(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Achievement {
  final IconData icon;
  final String label;
  final Color color;
  final bool unlocked;

  const _Achievement({
    required this.icon,
    required this.label,
    required this.color,
    required this.unlocked,
  });
}
