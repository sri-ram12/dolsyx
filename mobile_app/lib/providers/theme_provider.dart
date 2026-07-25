import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../theme/chat_theme_model.dart';
import '../theme/theme_manager.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _themeKey = 'selected_chat_theme';
  static const String _fontSizeKey = 'selected_font_size';
  static const String _opacityKey = 'wallpaper_opacity';
  static const String _blurKey = 'wallpaper_blur';

  ChatThemeModel _currentTheme = ThemeManager.builtInThemes[0];
  double _currentFontSize = 15.0;
  double _wallpaperOpacity = 1.0;
  double _wallpaperBlur = 0.0;

  ChatThemeModel get currentTheme => _currentTheme;
  double get currentFontSize => _currentFontSize;
  double get wallpaperOpacity => _wallpaperOpacity;
  double get wallpaperBlur => _wallpaperBlur;

  ThemeProvider() {
    _loadTheme();
  }

  void _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeId = prefs.getString(_themeKey) ?? ThemeManager.builtInThemes[0].id;
    _currentTheme = ThemeManager.getThemeById(themeId);
    _currentFontSize = prefs.getDouble(_fontSizeKey) ?? 15.0;
    _wallpaperOpacity = prefs.getDouble(_opacityKey) ?? 1.0;
    _wallpaperBlur = prefs.getDouble(_blurKey) ?? 0.0;
    
    _applyTheme();
    notifyListeners();
  }

  Future<void> setTheme(String themeId) async {
    _currentTheme = ThemeManager.getThemeById(themeId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, themeId);
    _applyTheme();
    notifyListeners();
  }

  Future<void> setFontSize(double size) async {
    _currentFontSize = size;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, size);
    notifyListeners();
  }
  
  Future<void> setWallpaperOpacity(double opacity) async {
    _wallpaperOpacity = opacity;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_opacityKey, opacity);
    notifyListeners();
  }

  Future<void> setWallpaperBlur(double blur) async {
    _wallpaperBlur = blur;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_blurKey, blur);
    notifyListeners();
  }

  void _applyTheme() {
    // Dynamic Application to static AppTheme properties
    AppTheme.primaryColor = _currentTheme.primaryColor;
    AppTheme.backgroundColor = _currentTheme.backgroundColor;
    AppTheme.surfaceColor = _currentTheme.surfaceColor;
    AppTheme.textPrimary = _currentTheme.textPrimary;
    AppTheme.textSecondary = _currentTheme.textSecondary;
    AppTheme.bubbleSender = _currentTheme.bubbleSender;
    AppTheme.bubbleReceiver = _currentTheme.bubbleReceiver;
    
    // Determine if the background is dark based on luminance to set isDark flag
    AppTheme.isDark = _currentTheme.backgroundColor.computeLuminance() < 0.5;
  }
}
