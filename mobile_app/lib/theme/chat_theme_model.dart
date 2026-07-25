import 'package:flutter/material.dart';

class ChatThemeModel {
  final String id;
  final String name;
  final Color primaryColor;
  final Color secondaryColor;
  final Color backgroundColor;
  final Color surfaceColor;
  final Color bubbleSender;
  final Color bubbleReceiver;
  final Color textPrimary;
  final Color textSecondary;
  final Color inputBarColor;
  final Color dividerColor;
  final String? wallpaperUrl;

  const ChatThemeModel({
    required this.id,
    required this.name,
    required this.primaryColor,
    required this.secondaryColor,
    required this.backgroundColor,
    required this.surfaceColor,
    required this.bubbleSender,
    required this.bubbleReceiver,
    required this.textPrimary,
    required this.textSecondary,
    required this.inputBarColor,
    required this.dividerColor,
    this.wallpaperUrl,
  });
}
