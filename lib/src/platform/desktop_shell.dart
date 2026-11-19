// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/legacy.dart';

import '../data/log_repository.dart';
import '../state/app_controller.dart';

/// Windows/macOS 桌面壳；效率模式仅限 Windows。
class DesktopShell with WindowListener, TrayListener {
  DesktopShell(this.controller);

  final AppController controller;

  static const MethodChannel _platformChannel = MethodChannel(
    'esurfing/windows',
  );

  static const MethodChannel _macChannel = MethodChannel('esurfing/macos');

  static bool get supported => Platform.isWindows || Platform.isMacOS;
  static bool get supportsEfficiencyMode => Platform.isWindows;

  bool _trayReady = false;
  bool _trayInstalled = false;
  bool _exiting = false;

  bool get trayReady => _trayReady;

  /// macOS 登录项针对整个 .app，而不是 Contents/MacOS 内的可执行文件。
  static String launchPath(String executable, {required bool macOS}) {
    if (!macOS) return executable;
    final file = File(executable);
    final bundle = file.parent.parent.parent;
    if (!file.parent.path.endsWith('/MacOS') ||
        !file.parent.parent.path.endsWith('/Contents') ||
        !bundle.path.endsWith('.app')) {
      throw StateError('macOS 自启动需要从已安装的 .app 运行');
    }
    return bundle.path;
  }

  bool? _efficiencyApplied;
  bool _efficiencyUnsupported = false;

  Future<void> init({bool syncAutoStart = true}) async {
    if (!supported) return;
    await windowManager.ensureInitialized();
    if (Platform.isMacOS) {
      _macChannel.setMethodCallHandler((call) async {
        if (call.method == 'requestQuit') {
          await exitApp();
        } else if (call.method == 'showWindow') {
          await showWindow();
        } else {
          throw MissingPluginException();
        }
      });
      await _macChannel.invokeMethod<void>('ready');
    }
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    try {
      await trayManager.setIcon(
        Platform.isMacOS ? 'assets/tray_macos.png' : 'assets/tray.ico',
      );
      _trayInstalled = true;
      await trayManager.setToolTip('校园网助手');
      trayManager.addListener(this);
      await _refreshMenu();
      _trayReady = true;
      controller.addListener(_onControllerChanged);
    } catch (error) {
      controller.logs.add('托盘初始化失败，窗口将保持可见：$error', level: LogLevel.warn);
      if (_trayInstalled) {
        await trayManager.destroy();
        _trayInstalled = false;
      }
    }
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(980, 700),
        minimumSize: Size(720, 560),
        center: true,
        title: '校园网助手',
      ),
      () async {
        if (controller.config.ui.startMinimized && _trayReady) {
          await windowManager.hide();
        } else {
          await windowManager.show();
          await windowManager.focus();
        }
        await syncEfficiencyMode();
      },
    );
    if (syncAutoStart) {
      try {
        await _syncAutoStart();
      } catch (error) {
        controller.logs.add('无法同步开机启动，请检查系统登录项设置：$error', level: LogLevel.warn);
      }
    }
  }

  void _onControllerChanged() {
    _refreshMenu().catchError((Object error) async {
      _trayReady = false;
      controller.logs.add('托盘菜单不可用，恢复主窗口：$error', level: LogLevel.warn);
      await showWindow();
    });
  }

  Future<void> _refreshMenu() async {
    if (!supported || _exiting) return;
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
      appPath: launchPath(Platform.resolvedExecutable, macOS: Platform.isMacOS),
    );
    if (Platform.isMacOS) {
      // The package skips "disable" for a pending approval. Always ask the
      // native backend, so a user can also remove a pending login item.
      await const MethodChannel('launch_at_startup').invokeMethod<void>(
        'launchAtStartupSetEnabled',
        {'setEnabledValue': enabled},
      );
      return;
    }
    if (enabled) {
      if (!await launcher.enable()) throw StateError('无法启用开机启动');
    } else {
      if (!await launcher.disable()) throw StateError('无法关闭开机启动');
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
    if (!supportsEfficiencyMode) return;
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
    if (_exiting) return;
    _exiting = true;
    controller.removeListener(_onControllerChanged);
    try {
      await controller.stopKeep();
      if (controller.config.ui.logoutOnExit && controller.snapshot.isOnline) {
        await controller.logout();
      }
      await controller.shutdown();
      controller.dispose();
      await dispose();
      await windowManager.setPreventClose(false);
      if (Platform.isMacOS) {
        await _macChannel.invokeMethod<void>('completeQuit');
      } else {
        await windowManager.destroy();
        exit(0);
      }
    } catch (error) {
      _exiting = false;
      controller.logs.add('退出清理失败：$error', level: LogLevel.error);
      await showWindow();
      rethrow;
    }
  }

  Future<void> dispose() async {
    controller.removeListener(_onControllerChanged);
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    if (_trayInstalled) await trayManager.destroy();
    _trayInstalled = false;
    _trayReady = false;
    if (Platform.isMacOS) {
      _macChannel.setMethodCallHandler(null);
      await _macChannel.invokeMethod<void>('notReady');
    }
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
    if (controller.config.ui.closeToTray && _trayReady) {
      windowManager.hide().then((_) => syncEfficiencyMode());
    } else {
      exitApp();
    }
  }
}
