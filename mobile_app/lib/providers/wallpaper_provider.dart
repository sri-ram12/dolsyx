import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

enum WallpaperType {
  none,
  solidColor,
  pattern,
  customFile,
}

class WallpaperConfig {
  final WallpaperType type;
  final String? value; // hex color for solid, asset path for pattern, file path for custom
  final double blur;
  final double opacity;
  final double brightness;

  WallpaperConfig({
    this.type = WallpaperType.none,
    this.value,
    this.blur = 0.0,
    this.opacity = 1.0,
    this.brightness = 1.0,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': type.toString(),
      'value': value,
      'blur': blur,
      'opacity': opacity,
      'brightness': brightness,
    };
  }

  factory WallpaperConfig.fromJson(Map<String, dynamic> json) {
    return WallpaperConfig(
      type: WallpaperType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => WallpaperType.none,
      ),
      value: json['value'],
      blur: (json['blur'] ?? 0.0).toDouble(),
      opacity: (json['opacity'] ?? 1.0).toDouble(),
      brightness: (json['brightness'] ?? 1.0).toDouble(),
    );
  }
}

class WallpaperProvider extends ChangeNotifier {
  WallpaperConfig _globalWallpaper = WallpaperConfig();
  final Map<String, WallpaperConfig> _chatWallpapers = {};
  
  WallpaperProvider() {
    _loadWallpapers();
  }

  WallpaperConfig get globalWallpaper => _globalWallpaper;

  WallpaperConfig getWallpaperForChat(String conversationId) {
    return _chatWallpapers[conversationId] ?? _globalWallpaper;
  }

  Future<void> _loadWallpapers() async {
    final prefs = await SharedPreferences.getInstance();
    
    final globalData = prefs.getString('wallpaper_global');
    if (globalData != null) {
      try {
        _globalWallpaper = WallpaperConfig.fromJson(jsonDecode(globalData));
      } catch (e) {
        print("Error loading global wallpaper: $e");
      }
    }

    final chatKeys = prefs.getKeys().where((k) => k.startsWith('wallpaper_chat_'));
    for (String key in chatKeys) {
      final data = prefs.getString(key);
      if (data != null) {
        try {
          final conversationId = key.replaceAll('wallpaper_chat_', '');
          _chatWallpapers[conversationId] = WallpaperConfig.fromJson(jsonDecode(data));
        } catch (e) {}
      }
    }
    notifyListeners();
  }

  Future<void> setGlobalWallpaper(WallpaperConfig config) async {
    _globalWallpaper = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wallpaper_global', jsonEncode(config.toJson()));
    notifyListeners();
  }

  Future<void> setChatWallpaper(String conversationId, WallpaperConfig config) async {
    _chatWallpapers[conversationId] = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wallpaper_chat_$conversationId', jsonEncode(config.toJson()));
    notifyListeners();
  }

  Future<void> removeChatWallpaper(String conversationId) async {
    _chatWallpapers.remove(conversationId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('wallpaper_chat_$conversationId');
    notifyListeners();
  }
}
