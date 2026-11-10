import 'dart:io';

import 'package:flutter/services.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../data/log_repository.dart';
import '../state/app_controller.dart';

/// Windows 桌面壳：托盘常驻、关闭到托盘、开机自启、效率模式（原生侧单实例）。
class DesktopShell with WindowListener, TrayListener {
  DesktopShell(this.controller);

  final AppController controller;

  static const MethodChannel _platformChannel = MethodChannel(
    'esurfing/windows',
  );

  static bool get supported => Platform.isWindows;

  bool? _efficiencyApplied;
  bool _efficiencyUnsupported = false;

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
        await syncEfficiencyMode();
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
    await syncEfficiencyMode();
  }

  /// 按「设置开关 + 窗口是否可见」同步 Windows 效率模式（EcoQoS）。
  /// 窗口隐藏到托盘时开启，重新显示时关闭；系统不支持时只在日志里提示一次。
  Future<void> syncEfficiencyMode() async {
    if (!supported) return;
    if (!controller.config.ui.efficiencyMode) {
      await _applyEfficiencyMode(false);
      return;
    }
    final visible = await windowManager.isVisible();
    await _applyEfficiencyMode(!visible);
  }

  Future<void> _applyEfficiencyMode(bool enabled) async {
    if (_efficiencyApplied == enabled) return;
    var ok = false;
    try {
      ok =
          await _platformChannel.invokeMethod<bool>(
            'setEfficiencyMode',
            enabled,
          ) ??
          false;
    } on MissingPluginException {
      ok = false;
    } on PlatformException {
      ok = false;
    }
    if (ok) {
      _efficiencyApplied = enabled;
      controller.logs.add(
        enabled ? '已开启效率模式（后台运行）' : '已退出效率模式',
        level: LogLevel.debug,
      );
      return;
    }
    if (_efficiencyUnsupported) return;
    _efficiencyUnsupported = true;
    controller.logs.add(
      '当前系统不支持效率模式（需要 Windows 10 1709 及以上）',
      level: LogLevel.warn,
    );
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
      windowManager.hide().then((_) => syncEfficiencyMode());
    } else {
      exitApp();
    }
  }
}
