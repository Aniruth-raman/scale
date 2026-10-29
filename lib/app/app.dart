import 'package:flutter/material.dart';

import 'shell.dart';

class ScaleApp extends StatelessWidget {
  const ScaleApp({super.key});

  @override
  Widget build(BuildContext context) {
    final light = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0E7C66)),
      visualDensity: VisualDensity.standard,
    );
    return MaterialApp(
      title: 'Scale',
      debugShowCheckedModeBanner: false,
      theme: light,
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0E7C66),
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const HomeShell(),
    );
  }
}
