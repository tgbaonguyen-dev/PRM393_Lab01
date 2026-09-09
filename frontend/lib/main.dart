import 'package:flutter/material.dart';

void main() => runApp(const MainApp());

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    title: 'PRM393 Attendance',
    debugShowCheckedModeBanner: false,
    home: Scaffold(),
  );
}
