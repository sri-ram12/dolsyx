import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/wallpaper_provider.dart';
import '../theme/app_theme.dart';

class WallpaperSelectionScreen extends StatelessWidget {
  final WallpaperType type;
  final String? conversationId;

  const WallpaperSelectionScreen({super.key, required this.type, this.conversationId});

  @override
  Widget build(BuildContext context) {
    final List<String> solidColors = [
      '#000000', '#FFFFFF', '#004D40', '#01579B', '#4DD0E1',
      '#4A148C', '#9C27B0', '#1A237E', '#E65100', '#FF7043',
      '#E91E63', '#FFAB91', '#00BFA5', '#827717', '#4E342E',
      '#006064', '#00BCD4', '#3F51B5', '#212121', '#424242',
    ];

    // For patterns, we'll store a comma separated list of colors for gradients
    final List<String> gradientPatterns = [
      '#ff7e5f,#feb47b', // Sunset
      '#00c6ff,#0072ff', // Ocean
      '#f79d00,#64f38c', // Mint
      '#f953c6,#b91d73', // Pink
      '#11998e,#38ef7d', // Green
      '#8e2de2,#4a00e0', // Purple
      '#4ca1af,#c4e0e5', // Sky
      '#108dc7,#ef8e38', // Contrast
      '#fc4a1a,#f7b733', // Fire
      '#2b5876,#4e4376', // Deep
      '#7f00ff,#e100ff', // Neon Violet
      '#00f2fe,#4facfe', // Cyber Cyan
      '#fa709a,#fee140', // Peach Sorbet
      '#30cfd0,#330867', // Teal Midnight
      '#a8ff78,#78ffd6', // Aurora Mint
      '#ff0844,#ffb199', // Flamingo Red
      '#0f172a,#38bdf8', // Nordic Sky
      '#b92b27,#1565c0', // Electric Indigo
      '#3a1c71,#d76d77', // Velvet Dusk
      '#43e97b,#38f9d7', // Emerald Glow
      '#ff9a9e,#fecfef', // Rose Pastel
      '#6a11cb,#2575fc', // Royal Orbit
      '#0f172a,#1e293b', // Titanium Slate
      '#141e30,#243b55', // Night Shadow
      '#000000,#434343', // Obsidian Dark
      '#f857a6,#ff5858', // Crimson Pulse
      '#e0c3fc,#8ec5fc', // Lavender Mist
      '#c2e9fb,#a1c4fd', // Ice Cloud
      '#ffd269,#ff4500', // Gold Rush
      '#1d2b64,#f8cdda', // Cosmic Rose
    ];

    final items = type == WallpaperType.solidColor ? solidColors : gradientPatterns;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(type == WallpaperType.solidColor ? 'Solid Colors' : 'Patterns'),
        backgroundColor: AppTheme.surfaceColor,
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.6,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final val = items[index];
          return GestureDetector(
            onTap: () {
              _showPreview(context, val);
            },
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withOpacity(0.3)),
                gradient: type == WallpaperType.pattern ? LinearGradient(
                  colors: val.split(',').map((c) => _fromHex(c)).toList(),
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ) : null,
                color: type == WallpaperType.solidColor ? _fromHex(val) : null,
              ),
            ),
          );
        },
      ),
    );
  }

  void _showPreview(BuildContext context, String val) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('Apply Wallpaper?', style: TextStyle(color: Colors.white)),
        content: Container(
          width: 200,
          height: 300,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: type == WallpaperType.pattern ? LinearGradient(
              colors: val.split(',').map((c) => _fromHex(c)).toList(),
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ) : null,
            color: type == WallpaperType.solidColor ? _fromHex(val) : null,
          ),
          child: const Center(
            child: Text('Chat Preview', style: TextStyle(color: Colors.white70)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
            onPressed: () {
              final provider = Provider.of<WallpaperProvider>(context, listen: false);
              final config = WallpaperConfig(
                type: type,
                value: val,
              );
              if (conversationId != null) {
                provider.setChatWallpaper(conversationId!, config);
              } else {
                provider.setGlobalWallpaper(config);
              }
              Navigator.pop(context); // close dialog
              Navigator.pop(context); // close selection screen
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Wallpaper Applied!'))
              );
            },
            child: const Text('SET', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Color _fromHex(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }
}
