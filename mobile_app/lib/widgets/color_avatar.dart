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

  List<Color> _getAvatarGradientColors(String text) {
    final int hash = text.hashCode;
    final List<List<Color>> gradients = [
      [const Color(0xFFff9a9e), const Color(0xFFfecfef)], // Peach to pink
      [const Color(0xFFa18cd1), const Color(0xFFfbc2eb)], // Purple to pink
      [const Color(0xFF84fab0), const Color(0xFF8fd3f4)], // Green to blue
      [const Color(0xFFfccb90), const Color(0xFFd57eeb)], // Orange to purple
      [const Color(0xFFe0c3fc), const Color(0xFF8ec5fc)], // Lavender to sky blue
      [const Color(0xFFf093fb), const Color(0xFFf5576c)], // Magenta to red
      [const Color(0xFF4facfe), const Color(0xFF00f2fe)], // Bright cyan to blue
      [const Color(0xFF43e97b), const Color(0xFF38f9d7)], // Mint green
      [const Color(0xFFfa709a), const Color(0xFFfee140)], // Pink to yellow
      [const Color(0xFF30cfd0), const Color(0xFF330867)], // Teal to dark purple
    ];
    return gradients[(hash.abs()) % gradients.length];
  }

  @override
  Widget build(BuildContext context) {
    final gradientColors = _getAvatarGradientColors(name);

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.person,
          color: Colors.white.withOpacity(0.5),
          size: radius * 1.2,
        ),
      ),
    );
  }
}
