import 'dart:io';

import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/platform/android_shell.dart';
import 'src/platform/desktop_shell.dart';
import 'src/state/app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final AppController controller;
  try {
    controller = await AppController.create();
  } catch (error) {
    runApp(_StartupErrorApp(error: error));
    return;
  }

  final desktopShell = DesktopShell(controller);
  await desktopShell.init();
  if (Platform.isAndroid) {
    await AndroidShell.requestNotificationPermission();
  }

  runApp(EsurfingApp(controller: controller, desktopShell: desktopShell));
}

class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                const Text('启动失败'),
                const SizedBox(height: 8),
                SelectableText('$error', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
