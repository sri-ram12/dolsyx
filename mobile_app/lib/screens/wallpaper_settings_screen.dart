import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/wallpaper_provider.dart';
import '../theme/app_theme.dart';
import 'wallpaper_selection_screen.dart';
import 'package:image_picker/image_picker.dart';

class WallpaperSettingsScreen extends StatefulWidget {
  final String? conversationId; // If null, applies globally

  const WallpaperSettingsScreen({super.key, this.conversationId});

  @override
  State<WallpaperSettingsScreen> createState() => _WallpaperSettingsScreenState();
}

class _WallpaperSettingsScreenState extends State<WallpaperSettingsScreen> {
  Color _fromHex(String hexString) {
    try {
      final buffer = StringBuffer();
      if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
      buffer.write(hexString.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return Colors.transparent;
    }
  }

  BoxDecoration? _buildDecoration(WallpaperConfig config) {
    if (config.type == WallpaperType.solidColor && config.value != null) {
      return BoxDecoration(
        color: _fromHex(config.value!),
      );
    } else if (config.type == WallpaperType.pattern && config.value != null) {
      return BoxDecoration(
        gradient: LinearGradient(
          colors: config.value!.split(',').map((c) => _fromHex(c)).toList(),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      );
    } else if (config.type == WallpaperType.customFile && config.value != null) {
      return BoxDecoration(
        image: DecorationImage(
          image: FileImage(File(config.value!)),
          fit: BoxFit.cover,
        ),
      );
    }
    return BoxDecoration(
      color: AppTheme.backgroundColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallpaperProvider = Provider.of<WallpaperProvider>(context);
    final currentConfig = widget.conversationId != null
        ? wallpaperProvider.getWallpaperForChat(widget.conversationId!)
        : wallpaperProvider.globalWallpaper;

    final decoration = _buildDecoration(currentConfig);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.conversationId == null ? 'Chat Wallpaper' : 'Custom Wallpaper',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        backgroundColor: AppTheme.surfaceColor,
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          Text(
            widget.conversationId == null
                ? 'Set the default background, opacity, and blur for all chats.'
                : 'Set a custom background, opacity, and blur for this chat.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),

          // ── Live Wallpaper Preview Card ──
          Container(
            height: 220,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.4), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                children: [
                  // Base background
                  Container(color: AppTheme.backgroundColor),
                  // Filtered Wallpaper
                  if (decoration != null)
                    Positioned.fill(
                      child: Opacity(
                        opacity: currentConfig.opacity.clamp(0.0, 1.0),
                        child: currentConfig.blur > 0.0
                            ? ImageFiltered(
                                imageFilter: ImageFilter.blur(
                                  sigmaX: currentConfig.blur,
                                  sigmaY: currentConfig.blur,
                                ),
                                child: Container(decoration: decoration),
                              )
                            : Container(decoration: decoration),
                      ),
                    ),
                  // Sample Chat Bubble Mockups
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Text(
                                'Hey! How does the wallpaper look? ✨',
                                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Text(
                                'Crisp, bold and perfect opacity! 🚀',
                                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Opacity (Dimming) Slider ──
          Card(
            color: AppTheme.surfaceColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.opacity_rounded, color: AppTheme.primaryColor, size: 20),
                          const SizedBox(width: 8),
                          Text('Wallpaper Opacity / Dimming', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w800, fontSize: 15)),
                        ],
                      ),
                      Text(
                        '${(currentConfig.opacity * 100).round()}%',
                        style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Slider(
                    value: currentConfig.opacity.clamp(0.05, 1.0),
                    min: 0.05,
                    max: 1.0,
                    divisions: 19,
                    activeColor: AppTheme.primaryColor,
                    inactiveColor: Colors.white12,
                    onChanged: (val) {
                      wallpaperProvider.updateOpacity(val, conversationId: widget.conversationId);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Blur Slider ──
          Card(
            color: AppTheme.surfaceColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.blur_on_rounded, color: AppTheme.primaryColor, size: 20),
                          const SizedBox(width: 8),
                          Text('Wallpaper Blur Effect', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w800, fontSize: 15)),
                        ],
                      ),
                      Text(
                        '${currentConfig.blur.toStringAsFixed(1)} px',
                        style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Slider(
                    value: currentConfig.blur.clamp(0.0, 10.0),
                    min: 0.0,
                    max: 10.0,
                    divisions: 20,
                    activeColor: AppTheme.primaryColor,
                    inactiveColor: Colors.white12,
                    onChanged: (val) {
                      wallpaperProvider.updateBlur(val, conversationId: widget.conversationId);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Wallpaper Source Options ──
          Text('Change Wallpaper', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 8),
          Card(
            color: AppTheme.surfaceColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.color_lens_rounded, color: AppTheme.primaryColor),
                  title: Text('Solid Colors', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
                  trailing: Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => WallpaperSelectionScreen(
                        type: WallpaperType.solidColor, 
                        conversationId: widget.conversationId,
                      ),
                    ));
                  },
                ),
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
                ListTile(
                  leading: Icon(Icons.pattern_rounded, color: AppTheme.primaryColor),
                  title: Text('Patterns & Gradients', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
                  trailing: Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => WallpaperSelectionScreen(
                        type: WallpaperType.pattern, 
                        conversationId: widget.conversationId,
                      ),
                    ));
                  },
                ),
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
                ListTile(
                  leading: Icon(Icons.photo_library_rounded, color: AppTheme.primaryColor),
                  title: Text('My Photos (Gallery)', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
                  trailing: Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                  onTap: () async {
                    final picker = ImagePicker();
                    final xfile = await picker.pickImage(source: ImageSource.gallery);
                    if (xfile == null || !context.mounted) return;
                    final provider = Provider.of<WallpaperProvider>(context, listen: false);
                    final config = currentConfig.copyWith(
                      type: WallpaperType.customFile,
                      value: xfile.path,
                    );
                    if (widget.conversationId != null) {
                      await provider.setChatWallpaper(widget.conversationId!, config);
                    } else {
                      await provider.setGlobalWallpaper(config);
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('✅ Custom Wallpaper Applied!')),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (widget.conversationId != null)
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              title: const Text('Remove Custom Wallpaper', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              tileColor: Colors.redAccent.withValues(alpha: 0.1),
              onTap: () {
                Provider.of<WallpaperProvider>(context, listen: false).removeChatWallpaper(widget.conversationId!);
                Navigator.pop(context);
              },
            ),
          if (widget.conversationId == null)
            ListTile(
              leading: const Icon(Icons.restore_rounded, color: Colors.redAccent),
              title: const Text('Reset to Default Wallpaper', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              tileColor: Colors.redAccent.withValues(alpha: 0.1),
              onTap: () {
                Provider.of<WallpaperProvider>(context, listen: false).setGlobalWallpaper(WallpaperConfig());
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Wallpaper reset to default!')),
                );
              },
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
