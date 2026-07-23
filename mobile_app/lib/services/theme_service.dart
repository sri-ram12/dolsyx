import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ThemeService extends ChangeNotifier {
  static const String _themeKey = 'selected_theme';
  static const String _fontSizeKey = 'selected_font_size';

  String _currentTheme = 'Dark';
  double _currentFontSize = 15.0;

  String get currentTheme => _currentTheme;
  double get currentFontSize => _currentFontSize;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _currentTheme = prefs.getString(_themeKey) ?? 'Dark';
    _currentFontSize = prefs.getDouble(_fontSizeKey) ?? 15.0;
    _applyTheme();
  }

  Future<void> setTheme(String themeName) async {
    _currentTheme = themeName;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, themeName);
    _applyTheme();
    notifyListeners();
  }

  Future<void> setFontSize(double size) async {
    _currentFontSize = size;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, size);
    notifyListeners();
  }

  void _applyTheme() {
    switch (_currentTheme) {
      case 'Light':
        AppTheme.isDark = false;
        AppTheme.primaryColor = const Color(0xFF6366F1); // Indigo
        AppTheme.backgroundColor = const Color(0xFFF8FAFC);
        AppTheme.surfaceColor = Colors.white;
        AppTheme.textPrimary = const Color(0xFF0F172A);
        AppTheme.textSecondary = const Color(0xFF64748B);
        break;
      case 'Aqua Sky Blue':
        AppTheme.isDark = false;
        AppTheme.primaryColor = const Color(0xFF00B4D8);
        AppTheme.backgroundColor = const Color(0xFFE0FBFC);
        AppTheme.surfaceColor = Colors.white;
        AppTheme.textPrimary = const Color(0xFF023E8A);
        AppTheme.textSecondary = const Color(0xFF0077B6);
        break;
      case 'Violet':
        AppTheme.isDark = true;
        AppTheme.primaryColor = const Color(0xFF9D4EDD);
        AppTheme.backgroundColor = const Color(0xFF10002B);
        AppTheme.surfaceColor = const Color(0xFF240046);
        AppTheme.textPrimary = Colors.white;
        AppTheme.textSecondary = const Color(0xFFC77DFF);
        break;
      case 'Dark':
      default:
        AppTheme.isDark = true;
        AppTheme.primaryColor = const Color(0xFF6366F1); // Indigo
        AppTheme.backgroundColor = const Color(0xFF0F172A);
        AppTheme.surfaceColor = const Color(0xFF1E293B);
        AppTheme.textPrimary = Colors.white;
        AppTheme.textSecondary = const Color(0xFF94A3B8);
        break;
    }
  }
}
