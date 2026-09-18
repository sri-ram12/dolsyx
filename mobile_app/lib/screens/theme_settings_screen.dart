import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../theme/theme_manager.dart';
import '../theme/app_theme.dart';

class ThemeSettingsScreen extends StatefulWidget {
  const ThemeSettingsScreen({super.key});

  @override
  State<ThemeSettingsScreen> createState() => _ThemeSettingsScreenState();
}

class _ThemeSettingsScreenState extends State<ThemeSettingsScreen> {
  bool _showWallpaperControls = false;

  String _getModeLabel(String mode) {
    switch (mode) {
      case 'light':
        return 'Light';
      case 'system':
        return 'System default';
      case 'dark':
      default:
        return 'Dark';
    }
  }

  void _showDarkModeDialog(BuildContext context, ThemeProvider themeProvider) {
    String tempSelection = themeProvider.themeModePreference;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppTheme.isDark ? const Color(0xFF202C33) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text(
              'Dark mode',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<String>(
                  title: Text(
                    'System default',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 15),
                  ),
                  value: 'system',
                  groupValue: tempSelection,
                  activeColor: AppTheme.primaryColor,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => tempSelection = val);
                      themeProvider.setThemeModePreference(val);
                      Navigator.pop(ctx);
                    }
                  },
                ),
                RadioListTile<String>(
                  title: Text(
                    'Light',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 15),
                  ),
                  value: 'light',
                  groupValue: tempSelection,
                  activeColor: AppTheme.primaryColor,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => tempSelection = val);
                      themeProvider.setThemeModePreference(val);
                      Navigator.pop(ctx);
                    }
                  },
                ),
                RadioListTile<String>(
                  title: Text(
                    'Dark',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 15),
                  ),
                  value: 'dark',
                  groupValue: tempSelection,
                  activeColor: AppTheme.primaryColor,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => tempSelection = val);
                      themeProvider.setThemeModePreference(val);
                      Navigator.pop(ctx);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final selectedIdx = themeProvider.selectedColorIndex;
    final isDark = themeProvider.isDark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B141A) : const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: Text(
          'App theme',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: isDark ? const Color(0xFF0B141A) : const Color(0xFFF0F2F5),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: AppTheme.textPrimary),
            color: isDark ? const Color(0xFF202C33) : Colors.white,
            onSelected: (val) {
              if (val == 'reset') {
                themeProvider.setColorIndex(0);
                themeProvider.setThemeModePreference('dark');
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Theme reset to WhatsApp Green (Dark)')),
                );
              } else if (val == 'wallpaper') {
                setState(() => _showWallpaperControls = !_showWallpaperControls);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'reset',
                child: Text(
                  'Reset to default',
                  style: TextStyle(color: AppTheme.textPrimary),
                ),
              ),
              PopupMenuItem(
                value: 'wallpaper',
                child: Text(
                  _showWallpaperControls ? 'Hide wallpaper settings' : 'Wallpaper settings',
                  style: TextStyle(color: AppTheme.textPrimary),
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── 1. Dark Mode Tile ──
                    InkWell(
                      onTap: () => _showDarkModeDialog(context, themeProvider),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        child: Row(
                          children: [
                            Icon(
                              Icons.brightness_medium_outlined,
                              color: AppTheme.textPrimary,
                              size: 24,
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Dark mode',
                                    style: TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _getModeLabel(themeProvider.themeModePreference),
                                    style: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 4),

                    // ── 2. Color Header ──
                    Padding(
                      padding: const EdgeInsets.only(left: 20, top: 12, bottom: 14),
                      child: Text(
                        'Color',
                        style: TextStyle(
                          color: isDark ? const Color(0xFF8696A0) : const Color(0xFF667781),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),

                    // ── 3. 20-Color Swatch Grid (4 columns x 5 rows) ──
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: ThemeManager.appThemeColors.length,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 22,
                          crossAxisSpacing: 22,
                          childAspectRatio: 1.0,
                        ),
                        itemBuilder: (context, index) {
                          final option = ThemeManager.appThemeColors[index];
                          final isSelected = index == selectedIdx;

                          return GestureDetector(
                            onTap: () {
                              themeProvider.setColorIndex(index);
                            },
                            child: Center(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                width: 56,
                                height: 56,
                                padding: isSelected ? const EdgeInsets.all(3.5) : EdgeInsets.zero,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: isSelected
                                      ? Border.all(
                                          color: isDark ? Colors.white : Colors.black87,
                                          width: 2.0,
                                        )
                                      : null,
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: option.color,
                                    boxShadow: [
                                      BoxShadow(
                                        color: option.color.withValues(alpha: 0.25),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: isSelected
                                      ? const Center(
                                          child: Icon(
                                            Icons.check,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Preserved Wallpaper Controls (Zero Regression) ──
                    if (_showWallpaperControls)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1F2C34) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark ? const Color(0xFF2A3942) : const Color(0xFFE0E0E0),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Wallpaper Settings',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(Icons.opacity, color: AppTheme.textSecondary, size: 20),
                                const SizedBox(width: 8),
                                Text('Opacity', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                                Expanded(
                                  child: Slider(
                                    value: themeProvider.wallpaperOpacity,
                                    activeColor: AppTheme.primaryColor,
                                    onChanged: (val) => themeProvider.setWallpaperOpacity(val),
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Icon(Icons.blur_on, color: AppTheme.textSecondary, size: 20),
                                const SizedBox(width: 8),
                                Text('Blur', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                                Expanded(
                                  child: Slider(
                                    value: themeProvider.wallpaperBlur,
                                    activeColor: AppTheme.primaryColor,
                                    max: 10,
                                    onChanged: (val) => themeProvider.setWallpaperBlur(val),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // ── 4. Bottom WhatsApp Plus Theme Banner & Pill Button ──
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Change your app theme with DOLSYX Plus.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark ? const Color(0xFF8696A0) : const Color(0xFF667781),
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: const Color(0xFF0B141A),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      onPressed: () {
                        final currentOption = ThemeManager.appThemeColors[selectedIdx];
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${currentOption.name} theme active!'),
                            duration: const Duration(seconds: 2),
                            backgroundColor: const Color(0xFF1F2C34),
                          ),
                        );
                      },
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.stars_rounded, size: 20, color: Color(0xFF0B141A)),
                          SizedBox(width: 8),
                          Text(
                            'DOLSYX Plus Active',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                              color: Color(0xFF0B141A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
