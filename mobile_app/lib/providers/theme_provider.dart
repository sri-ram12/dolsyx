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
  static const String _colorIndexKey = 'selected_theme_color_index';
  static const String _themeModeKey = 'selected_theme_mode_preference';

  int _selectedColorIndex = 0; // 0 = WhatsApp Green (Default)
  String _themeModePreference = 'dark'; // 'dark', 'light', 'system'
  bool _isDark = true;

  ChatThemeModel _currentTheme = ThemeManager.createThemeFromColor(
    colorOption: ThemeManager.appThemeColors[0],
    isDark: true,
  );

  double _currentFontSize = 16.0;
  double _wallpaperOpacity = 1.0;
  double _wallpaperBlur = 0.0;

  ChatThemeModel get currentTheme => _currentTheme;
  int get selectedColorIndex => _selectedColorIndex;
  String get themeModePreference => _themeModePreference;
  bool get isDark => _isDark;
  double get currentFontSize => _currentFontSize;
  double get wallpaperOpacity => _wallpaperOpacity;
  double get wallpaperBlur => _wallpaperBlur;

  ThemeProvider() {
    _loadTheme();
  }

  void _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedColorIndex = prefs.getInt(_colorIndexKey) ?? 0;
    if (_selectedColorIndex < 0 || _selectedColorIndex >= ThemeManager.appThemeColors.length) {
      _selectedColorIndex = 0;
    }

    _themeModePreference = prefs.getString(_themeModeKey) ?? 'dark';
    _isDark = _themeModePreference != 'light';

    final savedThemeId = prefs.getString(_themeKey);
    if (savedThemeId != null && !savedThemeId.startsWith('color_') && savedThemeId != 'default_whatsapp') {
      // User previously selected an explicit named legacy theme
      _currentTheme = ThemeManager.getThemeById(savedThemeId, isDark: _isDark);
    } else {
      _currentTheme = ThemeManager.createThemeFromColor(
        colorOption: ThemeManager.appThemeColors[_selectedColorIndex],
        isDark: _isDark,
      );
    }

    _currentFontSize = prefs.getDouble(_fontSizeKey) ?? 16.0;
    _wallpaperOpacity = prefs.getDouble(_opacityKey) ?? 1.0;
    _wallpaperBlur = prefs.getDouble(_blurKey) ?? 0.0;
    
    _applyTheme();
    notifyListeners();
  }

  Future<void> setColorIndex(int index) async {
    if (index < 0 || index >= ThemeManager.appThemeColors.length) return;
    _selectedColorIndex = index;
    _currentTheme = ThemeManager.createThemeFromColor(
      colorOption: ThemeManager.appThemeColors[_selectedColorIndex],
      isDark: _isDark,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_colorIndexKey, index);
    await prefs.setString(_themeKey, _currentTheme.id);

    _applyTheme();
    notifyListeners();
  }

  Future<void> setThemeModePreference(String mode) async {
    _themeModePreference = mode;
    _isDark = mode != 'light';
    _currentTheme = ThemeManager.createThemeFromColor(
      colorOption: ThemeManager.appThemeColors[_selectedColorIndex],
      isDark: _isDark,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode);
    await prefs.setString(_themeKey, _currentTheme.id);

    _applyTheme();
    notifyListeners();
  }

  Future<void> setTheme(String themeId) async {
    _currentTheme = ThemeManager.getThemeById(themeId, isDark: _isDark);
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
    
    // Set isDark flag
    AppTheme.isDark = _isDark;
  }
}
