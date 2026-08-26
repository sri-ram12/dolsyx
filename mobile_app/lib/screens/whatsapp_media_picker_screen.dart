import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../widgets/app_lock_wrapper.dart';
import 'image_editor_screen.dart';

class MediaItem {
  final File file;
  final String type; // 'IMAGE' or 'VIDEO'
  final String? duration;
  final String? path;

  MediaItem({
    required this.file,
    required this.type,
    this.duration,
    this.path,
  });
}

class WhatsAppMediaPickerScreen extends StatefulWidget {
  final Function(List<MediaItem> selectedMedia, String caption, bool isViewOnce, bool isHD) onSend;

  const WhatsAppMediaPickerScreen({
    super.key,
    required this.onSend,
  });

  @override
  State<WhatsAppMediaPickerScreen> createState() => _WhatsAppMediaPickerScreenState();
}

class _WhatsAppMediaPickerScreenState extends State<WhatsAppMediaPickerScreen> with SingleTickerProviderStateMixin {
  final List<MediaItem> _allMedia = [];
  final List<MediaItem> _displayedMedia = [];
  final List<MediaItem> _selectedItems = [];
  final TextEditingController _captionController = TextEditingController();
  final FocusNode _captionFocus = FocusNode();
  final ScrollController _galleryScrollController = ScrollController();
  String _currentAlbum = 'All Media';
  bool _isHD = false;
  bool _isViewOnce = false;
  bool _isFlashOn = false;
  bool _isLoading = true;
  bool _isFullGalleryOpen = false;
  int _currentModeIndex = 1; // 0: Video, 1: Photo, 2: Video note
  final List<String> _modes = ['Video', 'Photo', 'Video note'];
  final ImagePicker _picker = ImagePicker();

  int _allMediaCount = 0;
  int _recentsCount = 0;
  int _photosCount = 0;
  int _videosCount = 0;
  int _cameraCount = 0;
  int _screenshotsCount = 0;
  int _whatsappCount = 0;
  int _downloadsCount = 0;

  @override
  void initState() {
    super.initState();
    _loadDeviceMedia();
  }

  @override
  void dispose() {
    _captionController.dispose();
    _captionFocus.dispose();
    _galleryScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadDeviceMedia() async {
    try {
      final List<Directory> scanDirs = [];
      if (Platform.isAndroid) {
        scanDirs.addAll([
          Directory('/storage/emulated/0/DCIM/Camera'),
          Directory('/storage/emulated/0/Pictures'),
          Directory('/storage/emulated/0/Download'),
          Directory('/storage/emulated/0/DCIM/Screenshots'),
          Directory('/storage/emulated/0/Pictures/Screenshots'),
          Directory('/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images'),
          Directory('/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video'),
          Directory('/storage/emulated/0/DCIM'),
        ]);
      }

      final Set<String> seenPaths = {};
      final List<MediaItem> mediaItems = [];

      for (final dir in scanDirs) {
        if (dir.existsSync()) {
          try {
            final entities = dir.listSync(recursive: false, followLinks: false);
            for (final entity in entities) {
              if (entity is File) {
                final path = entity.path;
                if (seenPaths.contains(path)) continue;

                final ext = path.split('.').last.toLowerCase();
                if (['jpg', 'jpeg', 'png', 'webp'].contains(ext)) {
                  try {
                    if (entity.existsSync() && entity.lengthSync() > 0) {
                      seenPaths.add(path);
                      mediaItems.add(MediaItem(file: entity, type: 'IMAGE'));
                    }
                  } catch (_) {}
                } else if (['mp4', 'mov', 'm4v', '3gp', 'webm', 'mkv'].contains(ext)) {
                  try {
                    if (entity.existsSync() && entity.lengthSync() > 0) {
                      seenPaths.add(path);
                      mediaItems.add(MediaItem(file: entity, type: 'VIDEO'));
                    }
                  } catch (_) {}
                }
              }
            }
          } catch (_) {}
        }
      }

      // Sort by modified date descending (newest first)
      mediaItems.sort((a, b) {
        try {
          return b.file.lastModifiedSync().compareTo(a.file.lastModifiedSync());
        } catch (_) {
          return 0;
        }
      });

      if (mounted) {
        setState(() {
          _allMedia.clear();
          _allMedia.addAll(mediaItems);
          
          _allMediaCount = mediaItems.length;
          _recentsCount = mediaItems.take(100).length;
          _photosCount = mediaItems.where((m) => m.type == 'IMAGE').length;
          _videosCount = mediaItems.where((m) => m.type == 'VIDEO').length;
          _cameraCount = mediaItems.where((m) => m.file.path.toLowerCase().contains('camera')).length;
          _screenshotsCount = mediaItems.where((m) => m.file.path.toLowerCase().contains('screenshot')).length;
          _whatsappCount = mediaItems.where((m) => m.file.path.toLowerCase().contains('whatsapp')).length;
          _downloadsCount = mediaItems.where((m) => m.file.path.toLowerCase().contains('download')).length;

          _displayedMedia.clear();
          _displayedMedia.addAll(mediaItems);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filterByAlbum(String albumName) {
    setState(() {
      _currentAlbum = albumName;
      if (albumName == 'All Media') {
        _displayedMedia.clear();
        _displayedMedia.addAll(_allMedia);
      } else if (albumName == 'Recents') {
        _displayedMedia.clear();
        _displayedMedia.addAll(_allMedia.take(100));
      } else if (albumName == 'Photos') {
        _displayedMedia.clear();
        _displayedMedia.addAll(_allMedia.where((m) => m.type == 'IMAGE'));
      } else if (albumName == 'Videos') {
        _displayedMedia.clear();
        _displayedMedia.addAll(_allMedia.where((m) => m.type == 'VIDEO'));
      } else if (albumName == 'Camera') {
        _displayedMedia.clear();
        _displayedMedia.addAll(_allMedia.where((m) => m.file.path.toLowerCase().contains('camera')));
      } else if (albumName == 'Screenshots') {
        _displayedMedia.clear();
        _displayedMedia.addAll(_allMedia.where((m) => m.file.path.toLowerCase().contains('screenshot')));
      } else if (albumName == 'WhatsApp') {
        _displayedMedia.clear();
        _displayedMedia.addAll(_allMedia.where((m) => m.file.path.toLowerCase().contains('whatsapp')));
      } else if (albumName == 'Downloads') {
        _displayedMedia.clear();
        _displayedMedia.addAll(_allMedia.where((m) => m.file.path.toLowerCase().contains('download')));
      }
    });
  }

  void _showAlbumSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1F2C34),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final List<Map<String, dynamic>> albumList = [
          {'name': 'All Media', 'icon': Icons.perm_media_rounded, 'count': _allMediaCount},
          {'name': 'Recents', 'icon': Icons.access_time_rounded, 'count': _recentsCount},
          {'name': 'Photos', 'icon': Icons.photo_rounded, 'count': _photosCount},
          {'name': 'Videos', 'icon': Icons.videocam_rounded, 'count': _videosCount},
          if (_cameraCount > 0) {'name': 'Camera', 'icon': Icons.camera_alt_rounded, 'count': _cameraCount},
          if (_screenshotsCount > 0) {'name': 'Screenshots', 'icon': Icons.screenshot_rounded, 'count': _screenshotsCount},
          if (_whatsappCount > 0) {'name': 'WhatsApp', 'icon': Icons.chat_bubble_outline_rounded, 'count': _whatsappCount},
          if (_downloadsCount > 0) {'name': 'Downloads', 'icon': Icons.download_rounded, 'count': _downloadsCount},
        ];

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 12),
              const Text('Select Album', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const Divider(color: Colors.white10),
              ...albumList.map((alb) {
                final name = alb['name'] as String;
                final icon = alb['icon'] as IconData;
                final count = alb['count'] as int;
                final isSelected = _currentAlbum == name;
                return ListTile(
                  leading: Icon(
                    icon,
                    color: isSelected ? const Color(0xFF00A884) : Colors.white70,
                  ),
                  title: Text(
                    '$name ($count)',
                    style: TextStyle(
                      color: isSelected ? const Color(0xFF00A884) : Colors.white,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                  trailing: isSelected ? const Icon(Icons.check, color: Color(0xFF00A884)) : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    _filterByAlbum(name);
                  },
                );
              }),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: Color(0xFF00A884)),
                title: const Text('Open System Gallery...', style: TextStyle(color: Color(0xFF00A884), fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFromSystemGallery();
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _handlePanSelect(Offset localPosition) {
    if (_displayedMedia.isEmpty) return;
    final screenWidth = MediaQuery.of(context).size.width;
    final itemWidth = (screenWidth - 5) / 3;
    final scrollOffset = _galleryScrollController.hasClients ? _galleryScrollController.offset : 0.0;
    final col = (localPosition.dx / itemWidth).floor().clamp(0, 2);
    final row = ((localPosition.dy + scrollOffset) / itemWidth).floor();
    final index = row * 3 + col;
    if (index >= 0 && index < _displayedMedia.length) {
      final item = _displayedMedia[index];
      if (!_selectedItems.any((m) => m.file.path == item.file.path)) {
        HapticFeedback.selectionClick();
        setState(() {
          _selectedItems.add(item);
        });
      }
    }
  }

  Future<void> _captureFromCamera({bool isVideo = false}) async {
    GlobalAppLockWrapper.isMediaPickerActive = true;
    try {
      if (isVideo) {
        final XFile? recorded = await _picker.pickVideo(
          source: ImageSource.camera,
          maxDuration: const Duration(minutes: 5),
        );
        if (recorded != null && mounted) {
          final item = MediaItem(file: File(recorded.path), type: 'VIDEO');
          _openMediaPreview([item]);
        }
      } else {
        final XFile? photo = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: _isHD ? 100 : 85,
        );
        if (photo != null && mounted) {
          final item = MediaItem(file: File(photo.path), type: 'IMAGE');
          _openMediaPreview([item]);
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Camera error: $e')));
    } finally {
      Future.delayed(const Duration(seconds: 1), () {
        GlobalAppLockWrapper.isMediaPickerActive = false;
      });
    }
  }

  Future<void> _pickFromSystemGallery() async {
    GlobalAppLockWrapper.isMediaPickerActive = true;
    try {
      List<XFile> pickedList = [];
      try {
        pickedList = await _picker.pickMultipleMedia();
      } catch (_) {
        try {
          pickedList = await _picker.pickMultiImage();
        } catch (_) {
          final XFile? single = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
          if (single != null) pickedList = [single];
        }
      }

      if (pickedList.isNotEmpty && mounted) {
        final items = pickedList.map((f) {
          final ext = f.path.split('.').last.toLowerCase();
          final isVid = ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp', 'flv', 'm4v'].contains(ext);
          return MediaItem(file: File(f.path), type: isVid ? 'VIDEO' : 'IMAGE');
        }).toList();

        _openMediaPreview(items);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gallery error: $e')));
    } finally {
      Future.delayed(const Duration(seconds: 1), () {
        GlobalAppLockWrapper.isMediaPickerActive = false;
      });
    }
  }

  void _toggleItemSelection(MediaItem item) {
    setState(() {
      final index = _selectedItems.indexWhere((m) => m.file.path == item.file.path);
      if (index != -1) {
        _selectedItems.removeAt(index);
      } else {
        _selectedItems.add(item);
      }
    });
  }

  void _openMediaPreview(List<MediaItem> items) {
    if (items.isEmpty) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => WhatsAppMediaPreviewScreen(
          initialItems: items,
          isHD: _isHD,
          onSend: (mediaList, caption, isViewOnce, isHD) {
            widget.onSend(mediaList, caption, isViewOnce, isHD);
          },
        ),
      ),
    );
  }

  void _sendDirectly() {
    if (_selectedItems.isEmpty) return;
    final caption = _captionController.text.trim();
    Navigator.pop(context);
    widget.onSend(_selectedItems, caption, _isViewOnce, _isHD);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _isFullGalleryOpen || _selectedItems.isNotEmpty
            ? _buildFullGalleryView()
            : _buildCameraView(),
      ),
    );
  }

  // 🟢 1. WhatsApp Full Camera View with Horizontal Recent Strip (Matches Screenshot 2)
  Widget _buildCameraView() {
    return Stack(
      children: [
        // Camera Viewport / Dark Live Center Area
        Positioned.fill(
          child: GestureDetector(
            onTap: () => _captureFromCamera(isVideo: _currentModeIndex == 0),
            child: Container(
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _currentModeIndex == 0 ? Icons.videocam : Icons.camera_alt,
                      color: Colors.white24,
                      size: 70,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _currentModeIndex == 0 ? 'Tap to record video' : 'Tap to take photo',
                      style: const TextStyle(color: Colors.white38, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Top Control Bar: [✕ Close] and [⚡ Flash]
        Positioned(
          top: 12,
          left: 16,
          right: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 24),
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() => _isFlashOn = !_isFlashOn);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_isFlashOn ? 'Flash turned ON' : 'Flash turned OFF'),
                      duration: const Duration(milliseconds: 700),
                    ),
                  );
                },
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isFlashOn ? Icons.flash_on : Icons.flash_off,
                    color: _isFlashOn ? const Color(0xFFFFD700) : Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Bottom Controls Container (Recent Strip + Drag Handle + Shutter + Modes)
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            color: Colors.black.withValues(alpha: 0.85),
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 🟢 Drag Handle (Swipe Up to Expand to Full Gallery Grid)
                GestureDetector(
                  onVerticalDragUpdate: (details) {
                    if (details.primaryDelta != null && details.primaryDelta! < -5) {
                      setState(() => _isFullGalleryOpen = true);
                    }
                  },
                  onTap: () => setState(() => _isFullGalleryOpen = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    color: Colors.transparent,
                    child: Center(
                      child: Container(
                        width: 42,
                        height: 4.5,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),

                // 🟢 Horizontal Strip of Recent Gallery Thumbnails
                if (_allMedia.isNotEmpty)
                  GestureDetector(
                    onVerticalDragUpdate: (details) {
                      if (details.primaryDelta != null && details.primaryDelta! < -5) {
                        setState(() => _isFullGalleryOpen = true);
                      }
                    },
                    child: Container(
                      height: 72,
                      margin: const EdgeInsets.only(bottom: 14),
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        itemCount: _allMedia.take(30).length,
                        itemBuilder: (context, index) {
                          final item = _allMedia[index];
                          return GestureDetector(
                            onTap: () {
                              _openMediaPreview([item]);
                            },
                            onLongPress: () {
                              _toggleItemSelection(item);
                              setState(() => _isFullGalleryOpen = true);
                            },
                            child: Container(
                              width: 70,
                              height: 70,
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.white24, width: 0.5),
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    child: item.type == 'IMAGE'
                                        ? Image.file(
                                            item.file,
                                            fit: BoxFit.cover,
                                            cacheWidth: 160,
                                            cacheHeight: 160,
                                            errorBuilder: (_, __, ___) => Container(
                                              color: const Color(0xFF1F2C34),
                                              child: const Icon(Icons.broken_image, color: Colors.white24, size: 20),
                                            ),
                                          )
                                        : Container(
                                            color: const Color(0xFF1B2831),
                                            child: const Center(
                                              child: Icon(Icons.videocam_rounded, color: Colors.white, size: 22),
                                            ),
                                          ),
                                  ),
                                  if (item.type == 'VIDEO')
                                    const Positioned(
                                      bottom: 3,
                                      left: 3,
                                      child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 14),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                // 🟢 Main Action Row: [Gallery Button] [Filter] [Shutter Button] [Flip Camera]
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Gallery Icon Button (Opens full-screen gallery)
                      GestureDetector(
                        onTap: () => setState(() => _isFullGalleryOpen = true),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.photo_library_outlined, color: Colors.white, size: 24),
                        ),
                      ),

                      // Filter / Magic Wand
                      GestureDetector(
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Camera filter toggled'), duration: Duration(milliseconds: 600)),
                          );
                        },
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.auto_fix_high_rounded, color: Colors.white, size: 22),
                        ),
                      ),

                      // Circular Big Shutter Button
                      GestureDetector(
                        onTap: () => _captureFromCamera(isVideo: _currentModeIndex == 0),
                        onLongPress: () => _captureFromCamera(isVideo: true),
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                          ),
                          padding: const EdgeInsets.all(4),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _currentModeIndex == 0 ? Colors.redAccent : Colors.white,
                            ),
                          ),
                        ),
                      ),

                      // Camera Flip Button
                      GestureDetector(
                        onTap: () => _captureFromCamera(isVideo: _currentModeIndex == 0),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.flip_camera_android_rounded, color: Colors.white, size: 24),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // 🟢 Modes Selector: Video | Photo | Video note
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_modes.length, (index) {
                    final isSelected = _currentModeIndex == index;
                    return GestureDetector(
                      onTap: () => setState(() => _currentModeIndex = index),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.white.withValues(alpha: 0.2) : Colors.transparent,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          _modes[index],
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white60,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // 🟢 2. WhatsApp Full-Screen 3-Column Recents Gallery Grid (Matches Screenshot 1)
  Widget _buildFullGalleryView() {
    return Column(
      children: [
        // Top Bar: [✕ Close/Back] | [Recents ▾] | [HD]
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.black,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () {
                  if (_selectedItems.isNotEmpty) {
                    setState(() => _selectedItems.clear());
                  } else {
                    setState(() => _isFullGalleryOpen = false);
                  }
                },
              ),

              // Album Dropdown (Recents ▾)
              GestureDetector(
                onTap: _showAlbumSelector,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _currentAlbum,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_drop_down, color: Colors.white, size: 24),
                  ],
                ),
              ),

              // HD Quality Toggle
              GestureDetector(
                onTap: () {
                  setState(() => _isHD = !_isHD);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_isHD ? 'HD Quality enabled' : 'Standard Quality enabled'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    border: Border.all(color: _isHD ? const Color(0xFF00A884) : Colors.white70, width: 1.5),
                    borderRadius: BorderRadius.circular(5),
                    color: _isHD ? const Color(0xFF00A884).withValues(alpha: 0.25) : Colors.transparent,
                  ),
                  child: Text(
                    'HD',
                    style: TextStyle(
                      color: _isHD ? const Color(0xFF00A884) : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 3-Column Scrollable Media Grid with Numbered Badges 1, 2, 3...
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF00A884)))
              : _displayedMedia.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('No media found in this album.', style: TextStyle(color: Colors.white70, fontSize: 14)),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _pickFromSystemGallery,
                            icon: const Icon(Icons.photo_library_rounded, color: Colors.white),
                            label: const Text('Open System Gallery', style: TextStyle(color: Colors.white)),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00A884)),
                          ),
                        ],
                      ),
                    )
                  : GestureDetector(
                      onPanStart: (details) {
                        _handlePanSelect(details.localPosition);
                      },
                      onPanUpdate: (details) {
                        _handlePanSelect(details.localPosition);
                      },
                      child: GridView.builder(
                        controller: _galleryScrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 2.5,
                          mainAxisSpacing: 2.5,
                          childAspectRatio: 1.0,
                        ),
                        itemCount: _displayedMedia.length,
                        itemBuilder: (context, index) {
                          final item = _displayedMedia[index];
                          final selIdx = _selectedItems.indexWhere((m) => m.file.path == item.file.path);
                          final isSelected = selIdx != -1;
                          final orderNumber = selIdx + 1;

                          return GestureDetector(
                            onTap: () {
                              if (_selectedItems.isNotEmpty) {
                                _toggleItemSelection(item);
                              } else {
                                _openMediaPreview([item]);
                              }
                            },
                            onLongPress: () {
                              HapticFeedback.mediumImpact();
                              _toggleItemSelection(item);
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                border: isSelected
                                    ? Border.all(color: const Color(0xFF00A884), width: 2.5)
                                    : null,
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  item.type == 'IMAGE'
                                      ? Image.file(
                                          item.file,
                                          fit: BoxFit.cover,
                                          cacheWidth: 220,
                                          cacheHeight: 220,
                                          errorBuilder: (_, __, ___) => Container(
                                            color: const Color(0xFF1F2C34),
                                            child: const Icon(Icons.broken_image, color: Colors.white24),
                                          ),
                                        )
                                      : Container(
                                          color: const Color(0xFF1B2831),
                                          child: const Center(
                                            child: Icon(Icons.videocam_rounded, color: Colors.white, size: 28),
                                          ),
                                        ),

                                  // Video Indicator & Duration
                                  if (item.type == 'VIDEO')
                                    Positioned(
                                      bottom: 6,
                                      left: 6,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.videocam_rounded, color: Colors.white, size: 16),
                                          const SizedBox(width: 4),
                                          Text(
                                            item.duration ?? '0:42',
                                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),

                                  // 🟢 Selection Number Circle (1, 2, 3...) at Top Right
                                  if (isSelected)
                                    Positioned(
                                      top: 6,
                                      right: 6,
                                      child: Container(
                                        width: 26,
                                        height: 26,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: const Color(0xFF00A884),
                                          border: Border.all(color: Colors.white, width: 1.5),
                                          boxShadow: const [
                                            BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2)),
                                          ],
                                        ),
                                        child: Center(
                                          child: Text(
                                            '$orderNumber',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),

        // 🟢 Bottom Caption & Send Bar (when items are selected via long-press)
        if (_selectedItems.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            color: Colors.black,
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  // Selected Preview Thumbnail with Counter Badge
                  GestureDetector(
                    onTap: () => _openMediaPreview(_selectedItems),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white38),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(7),
                            child: Image.file(
                              _selectedItems.last.file,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Positioned(
                          top: -6,
                          right: -6,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF00A884),
                            ),
                            child: Center(
                              child: Text(
                                '${_selectedItems.length}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 10),

                  // Caption Input Pill
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F2C34),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          const Icon(Icons.emoji_emotions_outlined, color: Color(0xFF8696A0), size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _captionController,
                              focusNode: _captionFocus,
                              style: const TextStyle(color: Colors.white, fontSize: 15),
                              decoration: const InputDecoration(
                                hintText: 'Add a caption...',
                                hintStyle: TextStyle(color: Color(0xFF8696A0), fontSize: 15),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              _isViewOnce ? Icons.looks_one : Icons.looks_one_outlined,
                              color: _isViewOnce ? const Color(0xFF00A884) : const Color(0xFF8696A0),
                              size: 22,
                            ),
                            onPressed: () {
                              setState(() => _isViewOnce = !_isViewOnce);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Green Circular Send Button ➤
                  GestureDetector(
                    onTap: _sendDirectly,
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF00A884),
                      ),
                      child: const Center(
                        child: Icon(Icons.send_rounded, color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// 🟢 WhatsApp-Style Media Preview & Caption / Send Screen with Full Interactive Tools
class DrawnLine {
  final List<Offset?> path;
  final Color color;
  final double strokeWidth;

  DrawnLine({required this.path, required this.color, required this.strokeWidth});
}

class TextOverlayItem {
  String text;
  Color color;
  Offset position;
  double fontSize;
  TextOverlayItem({required this.text, required this.color, required this.position, this.fontSize = 24.0});
}

class EmojiStickerItem {
  String emoji;
  Offset position;
  double size;
  EmojiStickerItem({required this.emoji, required this.position, this.size = 38.0});
}

class WhatsAppMediaPreviewScreen extends StatefulWidget {
  final List<MediaItem> initialItems;
  final bool isHD;
  final Function(List<MediaItem> items, String caption, bool isViewOnce, bool isHD) onSend;

  const WhatsAppMediaPreviewScreen({
    super.key,
    required this.initialItems,
    this.isHD = false,
    required this.onSend,
  });

  @override
  State<WhatsAppMediaPreviewScreen> createState() => _WhatsAppMediaPreviewScreenState();
}

class _WhatsAppMediaPreviewScreenState extends State<WhatsAppMediaPreviewScreen> {
  late List<MediaItem> _items;
  int _currentIndex = 0;
  final TextEditingController _captionController = TextEditingController();
  bool _isViewOnce = false;
  late bool _isHD;
  VideoPlayerController? _videoController;

  // Image Editor Tools State
  int _rotationQuarterTurns = 0;
  bool _isDrawingMode = false;
  Color _selectedDrawColor = const Color(0xFF00A884);
  double _drawStrokeWidth = 4.0;
  final List<DrawnLine> _lines = [];
  DrawnLine? _currentLine;

  final List<TextOverlayItem> _textOverlays = [];
  final List<EmojiStickerItem> _emojiStickers = [];

  final List<Color> _paletteColors = [
    const Color(0xFF00A884),
    Colors.redAccent,
    Colors.amberAccent,
    Colors.lightBlueAccent,
    Colors.purpleAccent,
    Colors.white,
    Colors.black,
  ];

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.initialItems);
    _isHD = widget.isHD;
    _initializeCurrentMedia();
  }

  void _initializeCurrentMedia() {
    _videoController?.dispose();
    _videoController = null;
    _rotationQuarterTurns = 0;
    _lines.clear();
    _textOverlays.clear();
    _emojiStickers.clear();
    _isDrawingMode = false;

    if (_items.isNotEmpty && _items[_currentIndex].type == 'VIDEO') {
      _videoController = VideoPlayerController.file(_items[_currentIndex].file)
        ..initialize().then((_) {
          if (mounted) setState(() {});
        });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _captionController.dispose();
    super.dispose();
  }

  void _rotateImage() {
    setState(() {
      _rotationQuarterTurns = (_rotationQuarterTurns + 1) % 4;
    });
    HapticFeedback.selectionClick();
  }

  void _openCropTool() async {
    final current = _items[_currentIndex];
    if (current.type != 'IMAGE') return;
    final File? edited = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImageEditorScreen(imageFile: current.file),
      ),
    );
    if (edited != null && mounted) {
      setState(() {
        _items[_currentIndex] = MediaItem(file: edited, type: 'IMAGE');
      });
      _initializeCurrentMedia();
    }
  }

  void _showAddTextDialog() {
    final textEditController = TextEditingController();
    Color textColor = Colors.white;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1F2C34),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Add Text', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: textEditController,
                    autofocus: true,
                    style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      hintText: 'Type text here...',
                      hintStyle: TextStyle(color: Colors.white38),
                      border: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00A884))),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: _paletteColors.map((color) {
                      final isSelected = textColor == color;
                      return GestureDetector(
                        onTap: () => setDlgState(() => textColor = color),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(color: isSelected ? Colors.white : Colors.transparent, width: 2.5),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00A884)),
                  onPressed: () {
                    final text = textEditController.text.trim();
                    if (text.isNotEmpty) {
                      setState(() {
                        _textOverlays.add(TextOverlayItem(
                          text: text,
                          color: textColor,
                          position: const Offset(80, 200),
                        ));
                      });
                    }
                    Navigator.pop(ctx);
                  },
                  child: const Text('Add', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEmojiStickerSheet() {
    final emojis = ['❤️', '😂', '🔥', '👍', '🎉', '😍', '👏', '🥳', '😎', '🙏', '💯', '✨', '🤩', '🚀', '💬', '🌟', '💔', '🥺', '🎂', '🌹'];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1F2C34),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 12),
                const Text('Choose Sticker', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: emojis.map((emoji) {
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _emojiStickers.add(EmojiStickerItem(
                            emoji: emoji,
                            position: const Offset(120, 250),
                          ));
                        });
                        Navigator.pop(ctx);
                      },
                      child: Text(emoji, style: const TextStyle(fontSize: 32)),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  void _undoLastEdit() {
    setState(() {
      if (_lines.isNotEmpty) {
        _lines.removeLast();
      } else if (_textOverlays.isNotEmpty) {
        _textOverlays.removeLast();
      } else if (_emojiStickers.isNotEmpty) {
        _emojiStickers.removeLast();
      }
    });
    HapticFeedback.selectionClick();
  }

  void _showHDQualityModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1F2C34),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
                    const SizedBox(height: 16),
                    const Text('Media quality', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    const Text('HD media is clearer. Standard quality sends faster.', style: TextStyle(color: Color(0xFF8696A0), fontSize: 13)),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: () {
                        setState(() => _isHD = false);
                        Navigator.pop(ctx);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Icon(!_isHD ? Icons.radio_button_checked : Icons.radio_button_off, color: !_isHD ? const Color(0xFF00A884) : const Color(0xFF8696A0)),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Standard quality', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
                                  Text('Faster to send, standard resolution', style: TextStyle(color: Color(0xFF8696A0), fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(color: Colors.white10, height: 1),
                    InkWell(
                      onTap: () {
                        setState(() => _isHD = true);
                        Navigator.pop(ctx);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Icon(_isHD ? Icons.radio_button_checked : Icons.radio_button_off, color: _isHD ? const Color(0xFF00A884) : const Color(0xFF8696A0)),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Text('HD quality', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF00A884).withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: const Color(0xFF00A884), width: 1),
                                        ),
                                        child: const Text('HD', style: TextStyle(color: Color(0xFF00A884), fontSize: 10, fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                  const Text('Full original resolution and crystal-clear quality', style: TextStyle(color: Color(0xFF8696A0), fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _onSendTapped() {
    final caption = _captionController.text.trim();
    Navigator.pop(context);
    widget.onSend(_items, caption, _isViewOnce, _isHD);
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Text('No media selected', style: TextStyle(color: Colors.white))),
      );
    }

    final currentItem = _items[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Center Media Display with Rotation, Drawings, and Overlays
            Positioned.fill(
              child: GestureDetector(
                onPanStart: _isDrawingMode
                    ? (details) {
                        setState(() {
                          _currentLine = DrawnLine(
                            path: [details.localPosition],
                            color: _selectedDrawColor,
                            strokeWidth: _drawStrokeWidth,
                          );
                        });
                      }
                    : null,
                onPanUpdate: _isDrawingMode
                    ? (details) {
                        setState(() {
                          if (_currentLine != null) {
                            _currentLine!.path.add(details.localPosition);
                          }
                        });
                      }
                    : null,
                onPanEnd: _isDrawingMode
                    ? (details) {
                        setState(() {
                          if (_currentLine != null) {
                            _lines.add(_currentLine!);
                            _currentLine = null;
                          }
                        });
                      }
                    : null,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Rotatable Media View
                    RotatedBox(
                      quarterTurns: _rotationQuarterTurns,
                      child: currentItem.type == 'IMAGE'
                          ? Center(
                              child: Image.file(
                                currentItem.file,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.broken_image_rounded, color: Colors.white24, size: 64),
                                      SizedBox(height: 8),
                                      Text('Media could not be loaded', style: TextStyle(color: Colors.white54)),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : Center(
                              child: _videoController != null && _videoController!.value.isInitialized
                                  ? AspectRatio(
                                      aspectRatio: _videoController!.value.aspectRatio,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          VideoPlayer(_videoController!),
                                          GestureDetector(
                                            onTap: () {
                                              setState(() {
                                                _videoController!.value.isPlaying ? _videoController!.pause() : _videoController!.play();
                                              });
                                            },
                                            child: Container(
                                              decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                                              padding: const EdgeInsets.all(16),
                                              child: Icon(
                                                _videoController!.value.isPlaying ? Icons.pause : Icons.play_arrow_rounded,
                                                color: Colors.white,
                                                size: 48,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : const CircularProgressIndicator(color: Color(0xFF00A884)),
                            ),
                    ),

                    // Drawing Canvas Layer
                    CustomPaint(
                      painter: DrawingPainter(_lines, _currentLine),
                      size: Size.infinite,
                    ),

                    // Draggable Text Overlays
                    ..._textOverlays.map((item) {
                      return Positioned(
                        left: item.position.dx,
                        top: item.position.dy,
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            setState(() {
                              item.position += details.delta;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.text,
                              style: TextStyle(
                                color: item.color,
                                fontSize: item.fontSize,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),

                    // Draggable Emoji Stickers
                    ..._emojiStickers.map((item) {
                      return Positioned(
                        left: item.position.dx,
                        top: item.position.dy,
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            setState(() {
                              item.position += details.delta;
                            });
                          },
                          child: Text(item.emoji, style: TextStyle(fontSize: item.size)),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),

            // Top Bar: Back, HD, Crop/Rotate, Emoji, Text, Drawing, Undo
            Positioned(
              top: 10,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  // HD Quality Toggle Button
                  GestureDetector(
                    onTap: _showHDQualityModal,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: _isHD ? const Color(0xFF00A884) : Colors.white70, width: 1.5),
                        borderRadius: BorderRadius.circular(6),
                        color: _isHD ? const Color(0xFF00A884).withOpacity(0.3) : Colors.transparent,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'HD',
                            style: TextStyle(
                              color: _isHD ? const Color(0xFF00A884) : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          if (_isHD) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.check, size: 13, color: Color(0xFF00A884)),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Crop Tool
                  IconButton(
                    icon: const Icon(Icons.crop_rounded, color: Colors.white, size: 24),
                    tooltip: 'Crop',
                    onPressed: _openCropTool,
                  ),
                  // Rotate Tool
                  IconButton(
                    icon: const Icon(Icons.rotate_90_degrees_cw_rounded, color: Colors.white, size: 24),
                    tooltip: 'Rotate',
                    onPressed: _rotateImage,
                  ),
                  // Stickers / Emojis Tool
                  IconButton(
                    icon: const Icon(Icons.emoji_emotions_outlined, color: Colors.white, size: 24),
                    tooltip: 'Stickers',
                    onPressed: _showEmojiStickerSheet,
                  ),
                  // Text Overlay Tool
                  IconButton(
                    icon: const Icon(Icons.title_rounded, color: Colors.white, size: 24),
                    tooltip: 'Text',
                    onPressed: _showAddTextDialog,
                  ),
                  // Pen / Highlighting Draw Tool
                  IconButton(
                    icon: Icon(
                      Icons.edit_outlined,
                      color: _isDrawingMode ? const Color(0xFF00A884) : Colors.white,
                      size: 24,
                    ),
                    tooltip: 'Draw',
                    onPressed: () {
                      setState(() {
                        _isDrawingMode = !_isDrawingMode;
                      });
                    },
                  ),
                  // Undo Edit Tool
                  if (_lines.isNotEmpty || _textOverlays.isNotEmpty || _emojiStickers.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.undo_rounded, color: Colors.white, size: 24),
                      tooltip: 'Undo',
                      onPressed: _undoLastEdit,
                    ),
                ],
              ),
            ),

            // Color Palette Selector when in Drawing Mode
            if (_isDrawingMode)
              Positioned(
                top: 60,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F2C34).withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _paletteColors.map((color) {
                      final isSelected = _selectedDrawColor == color;
                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedDrawColor = color);
                        },
                        child: Container(
                          width: 24,
                          height: 24,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(color: isSelected ? Colors.white : Colors.transparent, width: 2.5),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

            // 🟢 Bottom Floating Cylinder Caption Bar & Send Action
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Multiple Thumbnails Carousel
                      if (_items.length > 1)
                        Container(
                          height: 50,
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _items.length,
                            itemBuilder: (ctx, idx) {
                              final item = _items[idx];
                              final isSel = idx == _currentIndex;
                              return GestureDetector(
                                onTap: () {
                                  setState(() => _currentIndex = idx);
                                  _initializeCurrentMedia();
                                },
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSel ? const Color(0xFF00A884) : Colors.white30,
                                      width: isSel ? 2.5 : 1,
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: item.type == 'IMAGE'
                                        ? Image.file(item.file, fit: BoxFit.cover)
                                        : Container(
                                            color: Colors.grey[900],
                                            child: const Icon(Icons.videocam, color: Colors.white70, size: 18),
                                          ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                      // Floating Cylinder Shape Caption Pill & Circular Send Button
                      Row(
                        children: [
                          // Floating Cylinder Capsule
                          Expanded(
                            child: Container(
                              height: 48,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1F2C34).withOpacity(0.95),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(color: Colors.white12),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Row(
                                children: [
                                  // Gallery / Add more media icon
                                  GestureDetector(
                                    onTap: () async {
                                      final picker = ImagePicker();
                                      final picked = await picker.pickMultipleMedia();
                                      if (picked.isNotEmpty && mounted) {
                                        setState(() {
                                          for (final p in picked) {
                                            final isVid = ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'].contains(p.path.split('.').last.toLowerCase());
                                            _items.add(MediaItem(file: File(p.path), type: isVid ? 'VIDEO' : 'IMAGE'));
                                          }
                                        });
                                      }
                                    },
                                    child: const Icon(Icons.add_photo_alternate_outlined, color: Color(0xFF8696A0), size: 22),
                                  ),
                                  const SizedBox(width: 8),
                                  // Caption Text Field
                                  Expanded(
                                    child: TextField(
                                      controller: _captionController,
                                      style: const TextStyle(color: Colors.white, fontSize: 15),
                                      decoration: const InputDecoration(
                                        hintText: 'Add a caption...',
                                        hintStyle: TextStyle(color: Color(0xFF8696A0), fontSize: 15),
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                                      ),
                                    ),
                                  ),
                                  // View Once '1' Button
                                  GestureDetector(
                                    onTap: () {
                                      setState(() => _isViewOnce = !_isViewOnce);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(_isViewOnce ? 'View once enabled' : 'View once turned off'),
                                          duration: const Duration(seconds: 1),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      width: 26,
                                      height: 26,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: _isViewOnce ? const Color(0xFF00A884) : const Color(0xFF8696A0),
                                          width: 2,
                                        ),
                                        color: _isViewOnce ? const Color(0xFF00A884).withOpacity(0.25) : Colors.transparent,
                                      ),
                                      child: Center(
                                        child: Text(
                                          '1',
                                          style: TextStyle(
                                            color: _isViewOnce ? const Color(0xFF00A884) : const Color(0xFF8696A0),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(width: 8),

                          // WhatsApp Green Circular Send Button
                          GestureDetector(
                            onTap: _onSendTapped,
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: const BoxDecoration(
                                color: Color(0xFF00A884),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Color(0x6600A884),
                                    blurRadius: 6,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                                  if (_items.length > 1)
                                    Positioned(
                                      top: 3,
                                      right: 3,
                                      child: Container(
                                        padding: const EdgeInsets.all(3.5),
                                        decoration: const BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Text(
                                          '${_items.length}',
                                          style: const TextStyle(
                                            color: Color(0xFF00A884),
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DrawingPainter extends CustomPainter {
  final List<DrawnLine> lines;
  final DrawnLine? currentLine;

  DrawingPainter(this.lines, this.currentLine);

  @override
  void paint(Canvas canvas, Size size) {
    for (final line in lines) {
      final paint = Paint()
        ..color = line.color
        ..strokeCap = StrokeCap.round
        ..strokeWidth = line.strokeWidth
        ..isAntiAlias = true;
      for (int i = 0; i < line.path.length - 1; i++) {
        if (line.path[i] != null && line.path[i + 1] != null) {
          canvas.drawLine(line.path[i]!, line.path[i + 1]!, paint);
        }
      }
    }

    if (currentLine != null) {
      final paint = Paint()
        ..color = currentLine!.color
        ..strokeCap = StrokeCap.round
        ..strokeWidth = currentLine!.strokeWidth
        ..isAntiAlias = true;
      for (int i = 0; i < currentLine!.path.length - 1; i++) {
        if (currentLine!.path[i] != null && currentLine!.path[i + 1] != null) {
          canvas.drawLine(currentLine!.path[i]!, currentLine!.path[i + 1]!, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
