import 'package:flutter/material.dart';

class ColorAvatar extends StatelessWidget {
  final String name;
  final double radius;
  final double fontSize;

  const ColorAvatar({
    super.key,
    required this.name,
    this.radius = 24.0,
    this.fontSize = 20.0,
  });

  Color _getAvatarColor(String text) {
    final int hash = text.hashCode;
    final List<Color> colors = [
      Colors.redAccent,
      Colors.blueAccent,
      Colors.green,
      Colors.orange,
      Colors.purpleAccent,
      Colors.teal,
      Colors.pinkAccent,
      Colors.indigoAccent,
      Colors.deepOrange,
      Colors.cyan,
    ];
    return colors[(hash.abs()) % colors.length].withOpacity(0.85);
  }

  String _getInitials(String text) {
    if (text.isEmpty) return "?";
    final parts = text.trim().split(RegExp(r'\s+'));
    if (parts.length > 1) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return text.substring(0, text.length > 1 ? 2 : 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final color = _getAvatarColor(name);
    final initials = _getInitials(name);

    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
