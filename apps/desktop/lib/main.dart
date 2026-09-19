import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'shell/app_shell.dart';

void main() {
  runApp(const Prm393DesktopApp());
}

class Prm393DesktopApp extends StatelessWidget {
  const Prm393DesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    const charcoal = Color(0xFF37352F);
    const canvasBg = Color(0xFFFAF9F6);
    const borderColor = Color(0xFFE3E2DE);

    final baseTextTheme = ThemeData.light().textTheme;
    final interTextTheme = GoogleFonts.interTextTheme(baseTextTheme).apply(
      bodyColor: charcoal,
      displayColor: charcoal,
    );

    return MaterialApp(
      title: 'iPresent',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: canvasBg,
        textTheme: interTextTheme,
        colorScheme: const ColorScheme.light(
          primary: charcoal,
          surface: Colors.white,
          onPrimary: Colors.white,
          onSurface: charcoal,
        ),
        dividerColor: borderColor,
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: const BorderSide(color: borderColor, width: 1),
          ),
          margin: EdgeInsets.zero,
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: charcoal,
            side: const BorderSide(color: borderColor, width: 1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            textStyle: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: charcoal,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            textStyle: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
      home: const AppShell(),
    );
  }
}
