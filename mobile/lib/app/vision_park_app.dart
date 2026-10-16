import 'package:flutter/material.dart';

import 'app_config.dart';
import 'app_shell.dart';
import 'app_theme.dart';

class VisionParkApp extends StatelessWidget {
  const VisionParkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.name,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const AppShell(),
    );
  }
}
