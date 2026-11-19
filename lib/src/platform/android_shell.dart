import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Schedules UI removal once per background interval, independently of sessions.
class AndroidBackgroundUiLifecycle {
  AndroidBackgroundUiLifecycle({required this.delay, required this.destroyUi});

  final Duration? Function() delay;
  final VoidCallback destroyUi;
  Timer? _timer;
  bool _background = false;

  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
      case AppLifecycleState.detached:
        _background = false;
        _timer?.cancel();
        _timer = null;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        if (_background) return;
        _background = true;
        final timeout = delay();
        if (timeout == null || timeout <= Duration.zero) return;
        _timer = Timer(timeout, () {
          _timer = null;
          if (_background) destroyUi();
        });
      case AppLifecycleState.inactive:
        break;
    }
  }

  void dispose() {
    _background = false;
    _timer?.cancel();
    _timer = null;
  }
}

/// Android 壳的能力：通知权限、电池优化白名单、前台服务。
/// 首版不接 Shizuku，只保留设置项占位。
class AndroidShell {
  static const MethodChannel _channel = MethodChannel('esurfing/android');

  static bool get supported => Platform.isAndroid;

  static Future<void> requestNotificationPermission() async {
    if (!supported) return;
    await _invoke('requestNotificationPermission');
  }

  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!supported) return true;
    return await _channel.invokeMethod<bool>(
          'isIgnoringBatteryOptimizations',
        ) ??
        false;
  }

  static Future<void> requestIgnoreBatteryOptimizations() async {
    if (!supported) return;
    await _invoke('requestIgnoreBatteryOptimizations');
  }

  /// 销毁界面并从最近任务里移除，前台服务与 Dart 会话保持不变。
  static Future<void> destroyUi() async {
    if (!supported) return;
    await _invoke('destroyUi');
  }

  static Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // 桌面或测试环境没有这个 channel。
    } on PlatformException {
      // 权限被拒绝时保持静默，UI 仍可提示。
    }
  }
}
