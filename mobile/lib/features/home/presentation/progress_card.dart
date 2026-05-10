import 'package:flutter/material.dart';
import '../../../shared/widgets/accessible_card.dart';
import '../../../core/theme/app_colors.dart';

/// Progress card widget that displays a single progress metric.
///
/// Used on main menu to show scenarios completed, level, and success rate.
/// Provides large, readable text with icon for visual clarity
class ProgressCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const ProgressCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AccessibleCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 36,
            color: AppColors.primary,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
