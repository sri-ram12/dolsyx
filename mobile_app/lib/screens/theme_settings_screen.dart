import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../theme/theme_manager.dart';
import '../theme/app_theme.dart';

class ThemeSettingsScreen extends StatelessWidget {
  const ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final currentTheme = themeProvider.currentTheme;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Chat Themes'),
        backgroundColor: AppTheme.surfaceColor,
        elevation: 0,
        iconTheme: IconThemeData(color: AppTheme.textPrimary),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Select a Theme',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.85,
              ),
              itemCount: ThemeManager.builtInThemes.length,
              itemBuilder: (context, index) {
                final theme = ThemeManager.builtInThemes[index];
                final isSelected = theme.id == currentTheme.id;

                return GestureDetector(
                  onTap: () {
                    themeProvider.setTheme(theme.id);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: theme.surfaceColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? theme.primaryColor : Colors.transparent,
                        width: 3,
                      ),
                      boxShadow: [
                        if (isSelected)
                          BoxShadow(
                            color: theme.primaryColor.withOpacity(0.3),
                            blurRadius: 8,
                            spreadRadius: 1,
                          )
                      ],
                    ),
                    child: Column(
                      children: [
                        // Chat Preview
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: theme.backgroundColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Receiver Bubble
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    margin: const EdgeInsets.only(left: 8, bottom: 8, right: 24),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: theme.bubbleReceiver,
                                      borderRadius: BorderRadius.circular(12).copyWith(bottomLeft: const Radius.circular(0)),
                                    ),
                                    child: Text(
                                      'Hello!',
                                      style: TextStyle(color: theme.textPrimary, fontSize: 12),
                                    ),
                                  ),
                                ),
                                // Sender Bubble
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 8, bottom: 8, left: 24),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: theme.bubbleSender,
                                      borderRadius: BorderRadius.circular(12).copyWith(bottomRight: const Radius.circular(0)),
                                    ),
                                    child: Text(
                                      'Hi there!',
                                      style: TextStyle(color: theme.textPrimary, fontSize: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: Text(
                            theme.name,
                            style: TextStyle(
                              color: theme.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: theme.primaryColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Selected',
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // Wallpaper Settings Placeholder
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Wallpaper Settings',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.opacity, color: AppTheme.textSecondary, size: 20),
                    const SizedBox(width: 8),
                    Text('Opacity', style: TextStyle(color: AppTheme.textPrimary)),
                    Expanded(
                      child: Slider(
                        value: themeProvider.wallpaperOpacity,
                        activeColor: currentTheme.primaryColor,
                        onChanged: (val) {
                          themeProvider.setWallpaperOpacity(val);
                        },
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Icon(Icons.blur_on, color: AppTheme.textSecondary, size: 20),
                    const SizedBox(width: 8),
                    Text('Blur', style: TextStyle(color: AppTheme.textPrimary)),
                    Expanded(
                      child: Slider(
                        value: themeProvider.wallpaperBlur,
                        activeColor: currentTheme.primaryColor,
                        max: 10,
                        onChanged: (val) {
                          themeProvider.setWallpaperBlur(val);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
