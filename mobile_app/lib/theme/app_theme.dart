import 'package:flutter/material.dart';

class AppTheme {
  static bool isDark = true;

  static Color primaryColor = const Color(0xFF32CD32); // Lime Green
  static Color backgroundColor = const Color(0xFF0F172A);
  static Color surfaceColor = const Color(0xFF1E293B);
  static Color textPrimary = Colors.white;
  static Color textSecondary = const Color(0xFFCBD5E1); // Crisp, high-contrast secondary text
  static Color bubbleSender = const Color(0xFF32CD32);
  static Color bubbleReceiver = const Color(0xFF1E293B);

  static ThemeData get themeData {
    return ThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: backgroundColor,
      primaryColor: primaryColor,
      cardColor: surfaceColor,
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceColor,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 19,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
        subtitleTextStyle: TextStyle(
          color: textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        iconColor: textPrimary,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surfaceColor,
        textStyle: TextStyle(
          color: textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primaryColor,
        unselectedLabelColor: textSecondary,
        labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.3),
        unselectedLabelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        indicatorColor: primaryColor,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surfaceColor,
        selectedItemColor: primaryColor,
        unselectedItemColor: textSecondary,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceColor,
        titleTextStyle: TextStyle(color: textPrimary, fontSize: 18, fontWeight: FontWeight.w800),
        contentTextStyle: TextStyle(color: textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(color: textPrimary, fontSize: 28, fontWeight: FontWeight.w800),
        headlineMedium: TextStyle(color: textPrimary, fontSize: 24, fontWeight: FontWeight.w800),
        headlineSmall: TextStyle(color: textPrimary, fontSize: 20, fontWeight: FontWeight.w800),
        titleLarge: TextStyle(color: textPrimary, fontSize: 18, fontWeight: FontWeight.w800),
        titleMedium: TextStyle(color: textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
        titleSmall: TextStyle(color: textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
        bodyLarge: TextStyle(color: textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
        bodyMedium: TextStyle(color: textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
        bodySmall: TextStyle(color: textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
        labelLarge: TextStyle(color: textPrimary, fontSize: 15, fontWeight: FontWeight.w800),
        labelMedium: TextStyle(color: textSecondary, fontSize: 13, fontWeight: FontWeight.w700),
        labelSmall: TextStyle(color: textSecondary, fontSize: 11, fontWeight: FontWeight.w700),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: textPrimary,
        selectionColor: primaryColor.withValues(alpha: 0.3),
        selectionHandleColor: primaryColor,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceColor,
        hintStyle: TextStyle(color: textSecondary.withValues(alpha: 0.8), fontWeight: FontWeight.w600),
        labelStyle: TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: primaryColor, width: 1.5),
        ),
      ),
    );
  }
}
