// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:esurfing_app/src/data/config_repository.dart';
import 'package:esurfing_app/src/data/credential_store.dart';
import 'package:esurfing_app/src/data/log_repository.dart';
import 'package:esurfing_app/src/ffi/esf_bindings.dart';
import 'package:esurfing_app/src/platform/desktop_shell.dart';
import 'package:esurfing_app/src/state/app_controller.dart';
import 'package:esurfing_app/src/state/host_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/legacy.dart';

class _MemoryLogs extends LogRepository {
  @override
  Future<void> init() async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real macOS Keychain, bundled ABI, menu bar and close lifecycle', (
    tester,
  ) async {
    expect(Platform.isMacOS, isTrue);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Text('Desktop integration check')),
      ),
    );
    await tester.runAsync(() async {
      // Only this unique test entry is touched; no saved account is loaded.
      final identifier =
          'desktop-check-${DateTime.now().microsecondsSinceEpoch}';
      final credentials = CredentialStore();
      try {
        await credentials.write(identifier, 'disposable-test-value');
        expect(await credentials.read(identifier), 'disposable-test-value');
      } finally {
        await credentials.delete(identifier);
      }
      expect(await credentials.read(identifier), isNull);

      final bindings = EsfBindings.instance;
      expect(bindings.version, isNotEmpty);
      expect(bindings.sessionCompatibilityError, isNull);
      final client = bindings.create(0);
      expect(client.address, isNot(0));
      bindings.destroy(client);

      final support = await getApplicationSupportDirectory();
      final directory = Directory('${support.path}/$identifier');
      final repository = await ConfigRepository.open(directory: directory);
      await repository.save(
        const AppConfig(
          clientId: 'desktop-integration-check',
          ui: UiConfig(startMinimized: true, closeToTray: true),
        ),
      );
      final host = HostClient();
      final controller = AppController(
        configRepository: repository,
        credentials: credentials,
        logs: _MemoryLogs(),
        host: host,
      );
      final shell = DesktopShell(controller);
      try {
        await controller.initialize();
        expect(controller.nativeVersion, bindings.version);
        // Do not change the CI user's login items.
        await shell.init(syncAutoStart: false);
        expect(shell.trayReady, isTrue);
        expect(await trayManager.getBounds(), isNotNull);
        expect(await windowManager.isVisible(), isFalse);
        await shell.showWindow();
        expect(await windowManager.isVisible(), isTrue);
        await windowManager.close();
        for (var attempt = 0; attempt < 50; attempt++) {
          if (!await windowManager.isVisible()) break;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(await windowManager.isVisible(), isFalse);
        // Closing the window must leave both engine and native host available.
        expect((await host.send('version'))['version'], bindings.version);
        await shell.showWindow();
        expect(await windowManager.isVisible(), isTrue);
        expect(DesktopShell.supportsEfficiencyMode, isFalse);
        expect(
          await const MethodChannel('launch_at_startup')
              .invokeMethod<bool>('launchAtStartupIsEnabled'),
          isA<bool>(),
        );
        await shell.dispose();
        // Fault injection only for this failure branch; the checks above use
        // the real tray plugin and its native status item.
        const trayChannel = MethodChannel('tray_manager');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          trayChannel,
          (_) async => throw PlatformException(code: 'tray_unavailable'),
        );
        try {
          await shell.init(syncAutoStart: false);
          expect(shell.trayReady, isFalse);
          expect(await windowManager.isVisible(), isTrue);
        } finally {
          messenger.setMockMethodCallHandler(trayChannel, null);
        }
      } finally {
        await shell.dispose();
        await controller.shutdown();
        await controller.shutdown();
        await expectLater(host.send('version'), throwsStateError);
        controller.dispose();
        if (await directory.exists()) await directory.delete(recursive: true);
      }
    });
  });
}
