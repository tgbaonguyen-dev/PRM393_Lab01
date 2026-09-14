import 'package:flutter/material.dart';

import 'features/import/import_screen.dart';

void main() {
  runApp(const Prm393DesktopApp());
}

class Prm393DesktopApp extends StatelessWidget {
  const Prm393DesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF2557A7);
    return MaterialApp(
      title: 'PRM393 - Import & Schedule',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F7FB),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
      home: const ImportScreen(),
    );
  }
}
