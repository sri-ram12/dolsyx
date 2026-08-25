import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import '../theme/app_theme.dart';
import '../widgets/app_lock_wrapper.dart';

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
  final Function(List<MediaItem> selectedMedia, String caption, bool isViewOnce) onSend;

  const WhatsAppMediaPickerScreen({
    super.key,
    required this.onSend,
  });

  @override
  State<WhatsAppMediaPickerScreen> createState() => _WhatsAppMediaPickerScreenState();
}

class _WhatsAppMediaPickerScreenState extends State<WhatsAppMediaPickerScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _captionController = TextEditingController();
  final List<MediaItem> _selectedItems = [];
  bool _isViewOnce = false;
  bool _isHD = false;
  bool _isFlashOn = false;
  int _currentModeIndex = 1; // 0: Video, 1: Photo, 2: Video note
  final List<String> _modes = ['Video', 'Photo', 'Video note'];
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Automatically trigger system picker or launch direct capture
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e')),
        );
      }
    } finally {
      Future.delayed(const Duration(seconds: 1), () {
        GlobalAppLockWrapper.isMediaPickerActive = false;
      });
    }
  }

  Future<void> _pickFromGallery() async {
    GlobalAppLockWrapper.isMediaPickerActive = true;
    try {
      final List<XFile> pickedList = await _picker.pickMultipleMedia();
      if (pickedList.isNotEmpty && mounted) {
        final items = pickedList.map((f) {
          final ext = f.path.split('.').last.toLowerCase();
          final isVid = ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp', 'm4v'].contains(ext);
          return MediaItem(
            file: File(f.path),
            type: isVid ? 'VIDEO' : 'IMAGE',
          );
        }).toList();

        _openMediaPreview(items);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gallery picker error: $e')),
        );
      }
    } finally {
      Future.delayed(const Duration(seconds: 1), () {
        GlobalAppLockWrapper.isMediaPickerActive = false;
      });
    }
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
            widget.onSend(mediaList, caption, isViewOnce);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Center Viewfinder / Dark Camera Area
            Positioned.fill(
              child: Container(
                color: const Color(0xFF0F141A),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.06),
                          border: Border.all(color: Colors.white.withOpacity(0.15), width: 2),
                        ),
                        child: Icon(
                          _currentModeIndex == 0
                              ? Icons.videocam_rounded
                              : (_currentModeIndex == 1 ? Icons.camera_alt_rounded : Icons.fiber_manual_record_rounded),
                          color: Colors.white70,
                          size: 56,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _currentModeIndex == 0
                            ? 'Tap shutter to record video'
                            : (_currentModeIndex == 1 ? 'Tap shutter for photo, hold for video' : 'Hold to record video note'),
                        style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _pickFromGallery,
                        icon: const Icon(Icons.photo_library_rounded, color: Colors.white),
                        label: const Text('Open Gallery / Recents', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00A884),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Top Control Bar (Close X, HD, Flash)
            Positioned(
              top: 10,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _isHD = !_isHD;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(_isHD ? 'HD Quality enabled' : 'Standard Quality enabled'),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            border: Border.all(color: _isHD ? const Color(0xFF00A884) : Colors.white70, width: 1.5),
                            borderRadius: BorderRadius.circular(6),
                            color: _isHD ? const Color(0xFF00A884).withOpacity(0.25) : Colors.transparent,
                          ),
                          child: Text(
                            'HD',
                            style: TextStyle(
                              color: _isHD ? const Color(0xFF00A884) : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        icon: Icon(
                          _isFlashOn ? Icons.flash_on : Icons.flash_off,
                          color: _isFlashOn ? const Color(0xFFFFD700) : Colors.white,
                          size: 26,
                        ),
                        onPressed: () {
                          setState(() {
                            _isFlashOn = !_isFlashOn;
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Bottom Shutter & Controls
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black.withOpacity(0.85), Colors.black],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Main Action Row (Gallery Icon, Shutter Button, Switch Camera)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Gallery Button (Thumbnail / Recents)
                        GestureDetector(
                          onTap: _pickFromGallery,
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white38, width: 1.5),
                            ),
                            child: const Icon(Icons.photo_library_outlined, color: Colors.white, size: 26),
                          ),
                        ),

                        // Shutter Button
                        GestureDetector(
                          onTap: () {
                            if (_currentModeIndex == 0) {
                              _captureFromCamera(isVideo: true);
                            } else {
                              _captureFromCamera(isVideo: false);
                            }
                          },
                          onLongPress: () {
                            _captureFromCamera(isVideo: true);
                          },
                          child: Container(
                            width: 80,
                            height: 80,
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
                          onTap: () {
                            _captureFromCamera(isVideo: _currentModeIndex == 0);
                          },
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white38, width: 1.5),
                            ),
                            child: const Icon(Icons.flip_camera_android_rounded, color: Colors.white, size: 26),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Mode Slider (Video | Photo | Video note)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_modes.length, (index) {
                        final isSelected = _currentModeIndex == index;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _currentModeIndex = index;
                            });
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 14),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.white.withOpacity(0.15) : Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              _modes[index],
                              style: TextStyle(
                                color: isSelected ? const Color(0xFF00A884) : Colors.white60,
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
        ),
      ),
    );
  }
}

// 🟢 WhatsApp-Style Media Preview & Caption / Send Screen
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

  void _showHDQualityModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1F2C34),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Media quality',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'HD media is clearer. Standard quality uses less storage space and sends faster.',
                      style: TextStyle(color: Color(0xFF8696A0), fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    // Standard Quality Row
                    InkWell(
                      onTap: () {
                        setState(() => _isHD = false);
                        Navigator.pop(ctx);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Icon(
                              !_isHD ? Icons.radio_button_checked : Icons.radio_button_off,
                              color: !_isHD ? const Color(0xFF00A884) : const Color(0xFF8696A0),
                            ),
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
                    // HD Quality Row
                    InkWell(
                      onTap: () {
                        setState(() => _isHD = true);
                        Navigator.pop(ctx);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Icon(
                              _isHD ? Icons.radio_button_checked : Icons.radio_button_off,
                              color: _isHD ? const Color(0xFF00A884) : const Color(0xFF8696A0),
                            ),
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
            // Center Media Display (Interactive Viewer / Video Player)
            Positioned.fill(
              child: currentItem.type == 'IMAGE'
                  ? InteractiveViewer(
                      minScale: 0.8,
                      maxScale: 3.5,
                      child: Center(
                        child: Image.file(
                          currentItem.file,
                          fit: BoxFit.contain,
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
                                      decoration: BoxDecoration(
                                        color: Colors.black45,
                                        shape: BoxShape.circle,
                                      ),
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

            // Top Bar (Back, HD toggle, Crop/Draw tools)
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
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.crop_rotate_rounded, color: Colors.white, size: 24),
                    onPressed: () {},
                  ),
                  IconButton(
                    icon: const Icon(Icons.emoji_emotions_outlined, color: Colors.white, size: 24),
                    onPressed: () {},
                  ),
                  IconButton(
                    icon: const Icon(Icons.title_rounded, color: Colors.white, size: 24),
                    onPressed: () {},
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, color: Colors.white, size: 24),
                    onPressed: () {},
                  ),
                ],
              ),
            ),

            // Bottom Caption Bar, View-Once toggle, Send button & Multi-thumbnail carousel
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.only(top: 8, bottom: 12, left: 12, right: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black.withOpacity(0.8), Colors.black],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Thumbnails list if multiple items
                    if (_items.length > 1)
                      Container(
                        height: 52,
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _items.length,
                          itemBuilder: (ctx, idx) {
                            final item = _items[idx];
                            final isSel = idx == _currentIndex;
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _currentIndex = idx;
                                });
                                _initializeCurrentMedia();
                              },
                              child: Container(
                                width: 50,
                                height: 50,
                                margin: const EdgeInsets.only(right: 8),
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
                                          child: const Icon(Icons.videocam, color: Colors.white70, size: 20),
                                        ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                    // WhatsApp Bottom Input & Action Bar
                    Row(
                      children: [
                        // Caption Text Field Container
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1F2C34),
                              borderRadius: BorderRadius.circular(26),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.add_photo_alternate_outlined, color: Color(0xFF8696A0), size: 22),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _captionController,
                                    style: const TextStyle(color: Colors.white, fontSize: 15),
                                    maxLines: 4,
                                    minLines: 1,
                                    decoration: const InputDecoration(
                                      hintText: 'Add a caption...',
                                      hintStyle: TextStyle(color: Color(0xFF8696A0), fontSize: 15),
                                      border: InputBorder.none,
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                // View-Once '1' Button
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _isViewOnce = !_isViewOnce;
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(_isViewOnce ? 'Photo set to view once' : 'View once turned off'),
                                        duration: const Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    width: 28,
                                    height: 28,
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
                                          fontSize: 13,
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

                        // WhatsApp Green Send Button with Item Count
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
                                  blurRadius: 8,
                                  offset: Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                const Icon(Icons.send_rounded, color: Colors.white, size: 22),
                                if (_items.length > 1)
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        '${_items.length}',
                                        style: const TextStyle(
                                          color: Color(0xFF00A884),
                                          fontSize: 10,
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
          ],
        ),
      ),
    );
  }
}
