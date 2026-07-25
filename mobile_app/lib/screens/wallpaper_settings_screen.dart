import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/wallpaper_provider.dart';
import '../theme/app_theme.dart';
import 'wallpaper_selection_screen.dart';
import 'package:image_picker/image_picker.dart';

class WallpaperSettingsScreen extends StatelessWidget {
  final String? conversationId; // If null, applies globally

  const WallpaperSettingsScreen({super.key, this.conversationId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(conversationId == null ? 'Chat Wallpaper' : 'Custom Wallpaper'),
        backgroundColor: AppTheme.surfaceColor,
      ),
      backgroundColor: AppTheme.backgroundColor,
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              conversationId == null 
                  ? 'Set the default background for all chats.' 
                  : 'Set a custom background for this specific chat.',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          ListTile(
            leading: Icon(Icons.color_lens, color: AppTheme.primaryColor),
            title: const Text('Solid Colors', style: TextStyle(color: Colors.white)),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => WallpaperSelectionScreen(
                  type: WallpaperType.solidColor, 
                  conversationId: conversationId,
                )
              ));
            },
          ),
          ListTile(
            leading: Icon(Icons.pattern, color: AppTheme.primaryColor),
            title: const Text('Patterns', style: TextStyle(color: Colors.white)),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => WallpaperSelectionScreen(
                  type: WallpaperType.pattern, 
                  conversationId: conversationId,
                )
              ));
            },
          ),
          ListTile(
            leading: Icon(Icons.photo_library, color: AppTheme.primaryColor),
            title: const Text('My Photos', style: TextStyle(color: Colors.white)),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () async {
              final picker = ImagePicker();
              final xfile = await picker.pickImage(source: ImageSource.gallery);
              if (xfile == null || !context.mounted) return;
              final provider = Provider.of<WallpaperProvider>(context, listen: false);
              final config = WallpaperConfig(
                type: WallpaperType.customFile,
                value: xfile.path,
              );
              if (conversationId != null) {
                provider.setChatWallpaper(conversationId!, config);
              } else {
                provider.setGlobalWallpaper(config);
              }
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Wallpaper Applied!'))
              );
            },
          ),
          if (conversationId != null)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Remove Custom Wallpaper', style: TextStyle(color: Colors.red)),
              onTap: () {
                Provider.of<WallpaperProvider>(context, listen: false).removeChatWallpaper(conversationId!);
                Navigator.pop(context);
              },
            ),
          if (conversationId == null)
            ListTile(
              leading: const Icon(Icons.restore, color: Colors.red),
              title: const Text('Reset Wallpaper', style: TextStyle(color: Colors.red)),
              onTap: () {
                Provider.of<WallpaperProvider>(context, listen: false).setGlobalWallpaper(WallpaperConfig());
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Wallpaper reset to default!'))
                );
              },
            ),
        ],
      ),
    );
  }
}
