import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Button variant types
enum AccessibleButtonVariant {
  primary,
  secondary,
  outline,
}

/// Large accessible button widget
///
/// Features:
/// - Minimum size: 120x56 pixels (exceeds 48x48 touch target)
/// - Font size: 20sp via theme's labelLarge
/// - Semantics wrapper for screen reader support
/// - Loading state with CircularProgressIndicator
/// - Gentle press animation (no flashing)
/// - Rounded corners (radius 16)
class AccessibleButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final AccessibleButtonVariant variant;

  const AccessibleButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.variant = AccessibleButtonVariant.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      enabled: onPressed != null && !isLoading,
      child: _buildButton(context),
    );
  }

  Widget _buildButton(BuildContext context) {
    final buttonContent = isLoading
        ? const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          )
        : _buildButtonContent();

    switch (variant) {
      case AccessibleButtonVariant.primary:
        return ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          child: buttonContent,
        );
      case AccessibleButtonVariant.secondary:
        return ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.secondary,
            foregroundColor: Colors.white,
          ),
          child: buttonContent,
        );
      case AccessibleButtonVariant.outline:
        return OutlinedButton(
          onPressed: isLoading ? null : onPressed,
          child: buttonContent,
        );
    }
  }

  Widget _buildButtonContent() {
    if (icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24),
          const SizedBox(width: 12),
          Text(label),
        ],
      );
    }
    return Text(label);
  }
}
