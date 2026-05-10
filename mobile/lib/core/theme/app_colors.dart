import 'package:flutter/material.dart';

/// ASD-friendly color palette
///
/// Design principles:
/// - Calm, muted colors (blues and greens)
/// - No harsh red or pure white backgrounds
/// - WCAG AA 4.5:1 contrast ratio for text
/// - Gentle feedback colors (no alarming tones)
class AppColors {
  // Primary palette - calm blues
  static const Color primary = Color(0xFF5B9BD5);       // Soft blue
  static const Color primaryDark = Color(0xFF3A7BC8);    // Deeper blue
  static const Color primaryLight = Color(0xFF8FBDE8);   // Light blue

  // Secondary palette - muted greens
  static const Color secondary = Color(0xFF7CB342);      // Muted green
  static const Color secondaryDark = Color(0xFF558B2F);  // Deeper green
  static const Color secondaryLight = Color(0xFFA5D66E); // Light green

  // Backgrounds - off-white and pale tints (NOT pure white)
  static const Color background = Color(0xFFF5F5F0);     // Warm off-white
  static const Color surface = Color(0xFFE8F4F8);        // Pale blue tint
  static const Color surfaceVariant = Color(0xFFE8F5E9); // Pale green tint

  // Text - high contrast (WCAG AA 4.5:1 against backgrounds)
  static const Color textPrimary = Color(0xFF2C3E50);    // Dark blue-gray
  static const Color textSecondary = Color(0xFF546E7A);  // Medium gray-blue

  // Feedback - gentle, not alarming
  static const Color success = Color(0xFF66BB6A);        // Soft green
  static const Color warning = Color(0xFFFFB74D);        // Warm amber
  static const Color info = Color(0xFF64B5F6);           // Soft blue
  // NO error red - use warning amber for negative feedback

  // Game-specific
  static const Color rewardGold = Color(0xFFFFD54F);     // Warm gold
  static const Color progressFill = Color(0xFF81C784);   // Gentle green

  // Private constructor to prevent instantiation
  AppColors._();
}
