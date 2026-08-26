import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

enum CropAspectRatio {
  free,
  square, // 1:1
  ratio4_3, // 4:3
  ratio16_9, // 16:9
  ratio9_16, // 9:16
}

class ImageEditorScreen extends StatefulWidget {
  final File imageFile;

  const ImageEditorScreen({super.key, required this.imageFile});

  @override
  State<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

class _ImageEditorScreenState extends State<ImageEditorScreen> {
  ui.Image? _decodedImage;
  bool _isLoading = true;
  int _rotationQuarterTurns = 0;
  bool _flipHorizontal = false;
  CropAspectRatio _selectedRatio = CropAspectRatio.free;

  // Normalized crop rectangle: 0.0 to 1.0 relative to displayed image boundaries
  Rect _cropRect = const Rect.fromLTWH(0.0, 0.0, 1.0, 1.0);
  int? _activeHandle; // 0: TL, 1: TR, 2: BR, 3: BL, 4: Center Drag

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final bytes = await widget.imageFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() {
          _decodedImage = frame.image;
          _isLoading = false;
          _resetCrop();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load image: $e')));
        Navigator.pop(context);
      }
    }
  }

  void _resetCrop() {
    setState(() {
      _cropRect = const Rect.fromLTWH(0.0, 0.0, 1.0, 1.0);
      _selectedRatio = CropAspectRatio.free;
    });
  }

  void _applyAspectRatio(CropAspectRatio ratio) {
    setState(() {
      _selectedRatio = ratio;
      double targetW = 1.0;
      double targetH = 1.0;

      final imgW = (_rotationQuarterTurns % 2 == 1) ? _decodedImage!.height.toDouble() : _decodedImage!.width.toDouble();
      final imgH = (_rotationQuarterTurns % 2 == 1) ? _decodedImage!.width.toDouble() : _decodedImage!.height.toDouble();
      final imgAspect = imgW / imgH;

      double targetRatioValue = imgAspect;
      switch (ratio) {
        case CropAspectRatio.free:
          _cropRect = const Rect.fromLTWH(0.0, 0.0, 1.0, 1.0);
          return;
        case CropAspectRatio.square:
          targetRatioValue = 1.0;
          break;
        case CropAspectRatio.ratio4_3:
          targetRatioValue = 4.0 / 3.0;
          break;
        case CropAspectRatio.ratio16_9:
          targetRatioValue = 16.0 / 9.0;
          break;
        case CropAspectRatio.ratio9_16:
          targetRatioValue = 9.0 / 16.0;
          break;
      }

      if (targetRatioValue > imgAspect) {
        targetW = 1.0;
        targetH = (imgAspect / targetRatioValue).clamp(0.1, 1.0);
      } else {
        targetH = 1.0;
        targetW = (targetRatioValue / imgAspect).clamp(0.1, 1.0);
      }

      final left = (1.0 - targetW) / 2;
      final top = (1.0 - targetH) / 2;
      _cropRect = Rect.fromLTWH(left, top, targetW, targetH);
    });
  }

  Future<void> _exportCroppedImage() async {
    if (_decodedImage == null) return;
    setState(() => _isLoading = true);

    try {
      final img = _decodedImage!;
      final bool isSwapped = _rotationQuarterTurns % 2 == 1;
      final double srcImgW = isSwapped ? img.height.toDouble() : img.width.toDouble();
      final double srcImgH = isSwapped ? img.width.toDouble() : img.height.toDouble();

      final double cropX = _cropRect.left * srcImgW;
      final double cropY = _cropRect.top * srcImgH;
      final double cropW = _cropRect.width * srcImgW;
      final double cropH = _cropRect.height * srcImgH;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, cropW, cropH));

      canvas.save();
      // Apply rotation / flip
      canvas.translate(cropW / 2, cropH / 2);
      canvas.rotate(_rotationQuarterTurns * math.pi / 2);
      if (_flipHorizontal) canvas.scale(-1, 1);
      canvas.translate(-srcImgW / 2, -srcImgH / 2);
      canvas.translate(-cropX + (srcImgW - cropW) / 2, -cropY + (srcImgH - cropH) / 2);

      // Draw source image
      if (!isSwapped) {
        canvas.drawImage(img, Offset.zero, Paint());
      } else {
        canvas.drawImage(img, Offset.zero, Paint());
      }
      canvas.restore();

      final picture = recorder.endRecording();
      final croppedUiImage = await picture.toImage(cropW.toInt().clamp(1, 4096), cropH.toInt().clamp(1, 4096));
      final byteData = await croppedUiImage.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        final tempDir = await getTemporaryDirectory();
        final croppedFile = File('${tempDir.path}/cropped_${DateTime.now().millisecondsSinceEpoch}.png');
        await croppedFile.writeAsBytes(byteData.buffer.asUint8List());
        if (mounted) {
          Navigator.pop(context, croppedFile);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error cropping image: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _decodedImage == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00A884))),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Crop & Rotate', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.rotate_right_rounded, color: Colors.white, size: 26),
            tooltip: 'Rotate 90°',
            onPressed: () {
              setState(() {
                _rotationQuarterTurns = (_rotationQuarterTurns + 1) % 4;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.flip_rounded, color: Colors.white, size: 24),
            tooltip: 'Flip Horizontal',
            onPressed: () {
              setState(() {
                _flipHorizontal = !_flipHorizontal;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 26),
            tooltip: 'Reset',
            onPressed: _resetCrop,
          ),
          TextButton(
            onPressed: _exportCroppedImage,
            child: const Text('Done', style: TextStyle(color: Color(0xFF00A884), fontWeight: FontWeight.bold, fontSize: 17)),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Crop Viewport Canvas
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bool isSwapped = _rotationQuarterTurns % 2 == 1;
                final double imgW = isSwapped ? _decodedImage!.height.toDouble() : _decodedImage!.width.toDouble();
                final double imgH = isSwapped ? _decodedImage!.width.toDouble() : _decodedImage!.height.toDouble();

                final double maxW = constraints.maxWidth - 32;
                final double maxH = constraints.maxHeight - 32;

                final double scale = math.min(maxW / imgW, maxH / imgH);
                final double viewW = imgW * scale;
                final double viewH = imgH * scale;

                return Center(
                  child: SizedBox(
                    width: viewW,
                    height: viewH,
                    child: Stack(
                      children: [
                        // Displayed Rotated/Flipped Image
                        Positioned.fill(
                          child: RotatedBox(
                            quarterTurns: _rotationQuarterTurns,
                            child: Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()..scale(_flipHorizontal ? -1.0 : 1.0, 1.0),
                              child: RawImage(
                                image: _decodedImage,
                                fit: BoxFit.fill,
                              ),
                            ),
                          ),
                        ),

                        // Interactive Crop Grid & Dimmer Overlay
                        Positioned.fill(
                          child: GestureDetector(
                            onPanStart: (details) {
                              final pos = details.localPosition;
                              final normX = (pos.dx / viewW).clamp(0.0, 1.0);
                              final normY = (pos.dy / viewH).clamp(0.0, 1.0);

                              const handleRadius = 0.08;
                              if ((normX - _cropRect.left).abs() < handleRadius && (normY - _cropRect.top).abs() < handleRadius) {
                                _activeHandle = 0; // TL
                              } else if ((normX - _cropRect.right).abs() < handleRadius && (normY - _cropRect.top).abs() < handleRadius) {
                                _activeHandle = 1; // TR
                              } else if ((normX - _cropRect.right).abs() < handleRadius && (normY - _cropRect.bottom).abs() < handleRadius) {
                                _activeHandle = 2; // BR
                              } else if ((normX - _cropRect.left).abs() < handleRadius && (normY - _cropRect.bottom).abs() < handleRadius) {
                                _activeHandle = 3; // BL
                              } else if (_cropRect.contains(Offset(normX, normY))) {
                                _activeHandle = 4; // Center Drag
                              } else {
                                _activeHandle = null;
                              }
                            },
                            onPanUpdate: (details) {
                              if (_activeHandle == null) return;
                              final deltaX = details.delta.dx / viewW;
                              final deltaY = details.delta.dy / viewH;

                              setState(() {
                                double l = _cropRect.left;
                                double t = _cropRect.top;
                                double r = _cropRect.right;
                                double b = _cropRect.bottom;

                                if (_activeHandle == 0) {
                                  l = (l + deltaX).clamp(0.0, r - 0.1);
                                  t = (t + deltaY).clamp(0.0, b - 0.1);
                                } else if (_activeHandle == 1) {
                                  r = (r + deltaX).clamp(l + 0.1, 1.0);
                                  t = (t + deltaY).clamp(0.0, b - 0.1);
                                } else if (_activeHandle == 2) {
                                  r = (r + deltaX).clamp(l + 0.1, 1.0);
                                  b = (b + deltaY).clamp(t + 0.1, 1.0);
                                } else if (_activeHandle == 3) {
                                  l = (l + deltaX).clamp(0.0, r - 0.1);
                                  b = (b + deltaY).clamp(t + 0.1, 1.0);
                                } else if (_activeHandle == 4) {
                                  final w = r - l;
                                  final h = b - t;
                                  l = (l + deltaX).clamp(0.0, 1.0 - w);
                                  t = (t + deltaY).clamp(0.0, 1.0 - h);
                                  r = l + w;
                                  b = t + h;
                                }

                                _cropRect = Rect.fromLTRB(l, t, r, b);
                              });
                            },
                            onPanEnd: (_) => _activeHandle = null,
                            child: CustomPaint(
                              painter: CropOverlayPainter(cropRect: _cropRect),
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

          // Aspect Ratio Presets Selector
          Container(
            color: const Color(0xFF1F2C34),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildRatioPill('Free', CropAspectRatio.free),
                    _buildRatioPill('1:1', CropAspectRatio.square),
                    _buildRatioPill('4:3', CropAspectRatio.ratio4_3),
                    _buildRatioPill('16:9', CropAspectRatio.ratio16_9),
                    _buildRatioPill('9:16', CropAspectRatio.ratio9_16),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatioPill(String label, CropAspectRatio ratio) {
    final isSelected = _selectedRatio == ratio;
    return GestureDetector(
      onTap: () => _applyAspectRatio(ratio),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00A884) : Colors.white12,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? const Color(0xFF00A884) : Colors.white24),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class CropOverlayPainter extends CustomPainter {
  final Rect cropRect;

  CropOverlayPainter({required this.cropRect});

  @override
  void paint(Canvas canvas, Size size) {
    final double l = cropRect.left * size.width;
    final double t = cropRect.top * size.height;
    final double r = cropRect.right * size.width;
    final double b = cropRect.bottom * size.height;
    final pixelRect = Rect.fromLTRB(l, t, r, b);

    // Dark dimmed area outside crop rect
    final dimPaint = Paint()..color = Colors.black.withValues(alpha: 0.55);
    canvas.drawPath(
      Path()
        ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
        ..addRect(pixelRect)
        ..fillType = PathFillType.evenOdd,
      dimPaint,
    );

    // Crop border
    final borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawRect(pixelRect, borderPaint);

    // Rule-of-thirds grid
    final gridPaint = Paint()
      ..color = Colors.white30
      ..strokeWidth = 0.8;
    final w = r - l;
    final h = b - t;
    canvas.drawLine(Offset(l + w / 3, t), Offset(l + w / 3, b), gridPaint);
    canvas.drawLine(Offset(l + 2 * w / 3, t), Offset(l + 2 * w / 3, b), gridPaint);
    canvas.drawLine(Offset(l, t + h / 3), Offset(r, t + h / 3), gridPaint);
    canvas.drawLine(Offset(l, t + 2 * h / 3), Offset(r, t + 2 * h / 3), gridPaint);

    // Corner Handles (WhatsApp style bold corners)
    final cornerPaint = Paint()
      ..color = const Color(0xFF00A884)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const cornerLen = 18.0;

    // Top-Left
    canvas.drawLine(Offset(l, t + cornerLen), Offset(l, t), cornerPaint);
    canvas.drawLine(Offset(l, t), Offset(l + cornerLen, t), cornerPaint);
    // Top-Right
    canvas.drawLine(Offset(r - cornerLen, t), Offset(r, t), cornerPaint);
    canvas.drawLine(Offset(r, t), Offset(r, t + cornerLen), cornerPaint);
    // Bottom-Right
    canvas.drawLine(Offset(r, b - cornerLen), Offset(r, b), cornerPaint);
    canvas.drawLine(Offset(r, b), Offset(r - cornerLen, b), cornerPaint);
    // Bottom-Left
    canvas.drawLine(Offset(l + cornerLen, b), Offset(l, b), cornerPaint);
    canvas.drawLine(Offset(l, b), Offset(l, b - cornerLen), cornerPaint);
  }

  @override
  bool shouldRepaint(covariant CropOverlayPainter oldDelegate) => oldDelegate.cropRect != cropRect;
}
