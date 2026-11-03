import 'dart:io';

import 'package:flutter/material.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../state/app_controller.dart';

/// Windows 桌面壳：托盘常驻、关闭到托盘、开机自启、单实例（原生侧）。
class DesktopShell with WindowListener, TrayListener {
  DesktopShell(this.controller);

  final AppController controller;

  static bool get supported => Platform.isWindows;

  Future<void> init() async {
    if (!supported) return;
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(980, 700),
        minimumSize: Size(720, 560),
        center: true,
        title: '校园网助手',
      ),
      () async {
        if (controller.config.ui.startMinimized) {
          await windowManager.hide();
        } else {
          await windowManager.show();
          await windowManager.focus();
        }
      },
    );
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);

    await trayManager.setIcon('assets/tray.ico');
    await trayManager.setToolTip('校园网助手');
    trayManager.addListener(this);
    await _refreshMenu();
    controller.addListener(_refreshMenu);
    await _syncAutoStart();
  }

  Future<void> _refreshMenu() async {
    if (!supported) return;
    final online = controller.snapshot.isOnline;
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: '显示主界面'),
          MenuItem.separator(),
          MenuItem(
            key: 'connect',
            label: online ? '断开连接' : '立即登录',
            disabled: controller.snapshot.isBusy,
          ),
          MenuItem(
            key: 'keep',
            label: controller.snapshot.keepRunning ? '停止保活' : '开始保活',
            disabled: !online,
          ),
          MenuItem.separator(),
          MenuItem(key: 'exit', label: '退出'),
        ],
      ),
    );
  }

  Future<void> _syncAutoStart() => setAutoStart(controller.config.ui.autoStart);

  Future<void> setAutoStart(bool enabled) async {
    if (!supported) return;
    final launcher = LaunchAtStartup.instance;
    launcher.setup(
      appName: 'EsurfingApp',
      appPath: Platform.resolvedExecutable,
    );
    if (enabled) {
      await launcher.enable();
    } else {
      await launcher.disable();
    }
  }

  Future<void> showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> exitApp() async {
    if (controller.config.ui.logoutOnExit && controller.snapshot.isOnline) {
      await controller.logout();
    }
    await trayManager.destroy();
    windowManager.removeListener(this);
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
    exit(0);
  }

  @override
  void onTrayIconMouseDown() {
    showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        showWindow();
        break;
      case 'connect':
        if (controller.snapshot.isOnline) {
          controller.logout();
        } else {
          controller.login();
        }
        break;
      case 'keep':
        if (controller.snapshot.keepRunning) {
          controller.stopKeep();
        } else {
          controller.startKeep();
        }
        break;
      case 'exit':
        exitApp();
        break;
    }
  }

  @override
  void onWindowClose() {
    if (controller.config.ui.closeToTray) {
      windowManager.hide();
    } else {
      exitApp();
    }
  }
}
