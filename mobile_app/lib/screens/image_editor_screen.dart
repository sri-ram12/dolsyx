import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class DrawnLine {
  final List<Offset?> path;
  final Color color;
  final double strokeWidth;

  DrawnLine({required this.path, required this.color, required this.strokeWidth});
}

class ImageEditorScreen extends StatefulWidget {
  final File imageFile;

  const ImageEditorScreen({super.key, required this.imageFile});

  @override
  State<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

class _ImageEditorScreenState extends State<ImageEditorScreen> {
  final List<DrawnLine> _lines = [];
  DrawnLine? _currentLine;
  Color _selectedColor = Colors.redAccent;
  double _strokeWidth = 4.0;

  final TextEditingController _captionController = TextEditingController();
  bool _isTextMode = false;
  String _overlayText = '';

  final List<Color> _colors = [
    Colors.redAccent,
    Colors.greenAccent,
    Colors.lightBlueAccent,
    Colors.amberAccent,
    Colors.purpleAccent,
    Colors.white,
    Colors.black,
  ];

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  void _undo() {
    if (_lines.isNotEmpty) {
      setState(() {
        _lines.removeLast();
      });
    }
  }

  void _clear() {
    setState(() {
      _lines.clear();
      _overlayText = '';
      _captionController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        title: const Text('Edit Photo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo, color: Colors.white),
            tooltip: 'Undo Draw',
            onPressed: _undo,
          ),
          IconButton(
            icon: const Icon(Icons.cleaning_services, color: Colors.white),
            tooltip: 'Clear All',
            onPressed: _clear,
          ),
          TextButton.icon(
            icon: const Icon(Icons.check_circle, color: Colors.greenAccent),
            label: const Text('Send', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16)),
            onPressed: () {
              Navigator.pop(context, widget.imageFile);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Image.file(widget.imageFile, fit: BoxFit.contain),
                  Positioned.fill(
                    child: GestureDetector(
                      onPanStart: (details) {
                        final RenderBox renderBox = context.findRenderObject() as RenderBox;
                        final localPos = renderBox.globalToLocal(details.globalPosition);
                        setState(() {
                          _currentLine = DrawnLine(
                            path: [localPos],
                            color: _selectedColor,
                            strokeWidth: _strokeWidth,
                          );
                          if (_currentLine != null) {
                            _lines.add(_currentLine!);
                          }
                        });
                      },
                      onPanUpdate: (details) {
                        final RenderBox renderBox = context.findRenderObject() as RenderBox;
                        final localPos = renderBox.globalToLocal(details.globalPosition);
                        setState(() {
                          _currentLine?.path.add(localPos);
                        });
                      },
                      onPanEnd: (_) {
                        setState(() {
                          _currentLine = null;
                        });
                      },
                      child: CustomPaint(
                        painter: DrawingPainter(lines: _lines),
                        size: Size.infinite,
                      ),
                    ),
                  ),
                  if (_overlayText.isNotEmpty)
                    Positioned(
                      bottom: 40,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          _overlayText,
                          style: TextStyle(color: _selectedColor, fontSize: 20, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Drawing Tools & Color Palette
          Container(
            color: const Color(0xFF1E293B),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: _colors.map((color) {
                    final isSelected = _selectedColor == color;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedColor = color),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: isSelected ? Border.all(color: Colors.white, width: 3) : null,
                          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.text_fields, color: _isTextMode ? AppTheme.primaryColor : Colors.white),
                      onPressed: () {
                        setState(() => _isTextMode = !_isTextMode);
                      },
                    ),
                    Expanded(
                      child: TextField(
                        controller: _captionController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'Add a caption or text...',
                          hintStyle: TextStyle(color: Colors.white54),
                          border: InputBorder.none,
                        ),
                        onChanged: (val) {
                          setState(() => _overlayText = val);
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

class DrawingPainter extends CustomPainter {
  final List<DrawnLine> lines;

  DrawingPainter({required this.lines});

  @override
  void paint(Canvas canvas, Size size) {
    for (final line in lines) {
      final paint = Paint()
        ..color = line.color
        ..strokeCap = StrokeCap.round
        ..strokeWidth = line.strokeWidth
        ..style = PaintingStyle.stroke;

      for (int i = 0; i < line.path.length - 1; i++) {
        if (line.path[i] != null && line.path[i + 1] != null) {
          canvas.drawLine(line.path[i]!, line.path[i + 1]!, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
