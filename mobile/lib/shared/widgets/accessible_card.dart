import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Accessible card widget with rounded corners and optional tap handling
///
/// Features:
/// - Rounded corners (radius 16)
/// - Subtle elevation (2)
/// - Uses ASD-friendly surface color
/// - Optional tap handling with InkWell
/// - Semantics annotation for accessibility
class AccessibleCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  const AccessibleCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final card = Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      color: AppColors.surface,
      child: Padding(
        padding: padding,
        child: child,
      ),
    );

    if (onTap != null) {
      return Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: AppColors.primary.withAlpha(51), // 0.2 opacity
          highlightColor: AppColors.primary.withAlpha(26), // 0.1 opacity
          child: card,
        ),
      );
    }

    return card;
  }
}
