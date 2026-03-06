import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/ui.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: JinshiApp()));
}

class JinshiApp extends StatelessWidget {
  const JinshiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '锦时打卡',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2C8C66)),
        useMaterial3: true,
      ),
      home: const AppShell(),
    );
  }
}
