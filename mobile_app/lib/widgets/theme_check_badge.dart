import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ThemeCheckBadge extends StatelessWidget {
  final bool isSelected;
  final double size;
  final VoidCallback? onTap;

  const ThemeCheckBadge({
    super.key,
    required this.isSelected,
    this.size = 22.0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final badge = isSelected
        ? Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: const Color(0xFF00A884),
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.backgroundColor, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00A884).withOpacity(0.4),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Icon(
              Icons.check,
              size: size * 0.65,
              color: Colors.white,
            ),
          )
        : Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white38, width: 2),
            ),
          );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(4.0),
          child: badge,
        ),
      );
    }
    return badge;
  }
}
