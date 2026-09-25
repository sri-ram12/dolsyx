import 'package:flutter/material.dart';

class AppTheme {
  static bool isDark = false;

  static Color primaryColor = const Color(0xFF607D8B); // Slate Gray
  static Color backgroundColor = const Color(0xFFECEFF1);
  static Color surfaceColor = const Color(0xFFFFFFFF);
  static Color textPrimary = const Color(0xFF263238);
  static Color textSecondary = const Color(0xFF455A64);
  static Color bubbleSender = const Color(0xFFCFD8DC);
  static Color bubbleReceiver = const Color(0xFFFFFFFF);

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
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        subtitleTextStyle: TextStyle(
          color: textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w400,
          height: 1.25,
        ),
        iconColor: textPrimary,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surfaceColor,
        textStyle: TextStyle(
          color: textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primaryColor,
        unselectedLabelColor: textSecondary,
        labelStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, letterSpacing: 0.2),
        unselectedLabelStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
        indicatorColor: primaryColor,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surfaceColor,
        selectedItemColor: primaryColor,
        unselectedItemColor: textSecondary,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 12),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceColor,
        titleTextStyle: TextStyle(color: textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
        contentTextStyle: TextStyle(color: textPrimary, fontSize: 14, fontWeight: FontWeight.w400, height: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      textTheme: TextTheme(
        // Headings / Screen titles
        headlineLarge: TextStyle(color: textPrimary, fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.3),
        headlineMedium: TextStyle(color: textPrimary, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.2),
        headlineSmall: TextStyle(color: textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
        // Section & Card Titles
        titleLarge: TextStyle(color: textPrimary, fontSize: 17, fontWeight: FontWeight.w700),
        titleMedium: TextStyle(color: textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
        titleSmall: TextStyle(color: textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600),
        // Body / Message texts
        bodyLarge: TextStyle(color: textPrimary, fontSize: 15, fontWeight: FontWeight.w400, height: 1.35),
        bodyMedium: TextStyle(color: textSecondary, fontSize: 13.5, fontWeight: FontWeight.w400, height: 1.3),
        bodySmall: TextStyle(color: textSecondary.withOpacity(0.85), fontSize: 12, fontWeight: FontWeight.w400),
        // Labels & Actions
        labelLarge: TextStyle(color: textPrimary, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.3),
        labelMedium: TextStyle(color: textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
        labelSmall: TextStyle(color: textSecondary.withOpacity(0.8), fontSize: 11, fontWeight: FontWeight.w500),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: BorderSide(color: textSecondary.withOpacity(0.3)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
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
        hintStyle: TextStyle(color: textSecondary.withOpacity(0.7), fontWeight: FontWeight.w400, fontSize: 14),
        labelStyle: TextStyle(color: textPrimary, fontWeight: FontWeight.w500, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColor, width: 1.5),
        ),
      ),
    );
  }
}
