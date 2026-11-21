import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Android 壳的能力：通知权限、电池优化白名单、前台服务。
/// 首版不接 Shizuku，只保留设置项占位。
class AndroidShell {
  static const MethodChannel _channel = MethodChannel('esurfing/android');
  static final Stream<void> backgroundUiRemoved = _backgroundUiRemovedStream();

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

  /// 由原生 Activity 生命周期计时；非正数表示不销毁。
  static Future<void> setBackgroundDestroyMinutes(int minutes) async {
    if (!supported) return;
    await _invoke('setBackgroundDestroyMinutes', {'minutes': minutes});
  }

  static Stream<void> _backgroundUiRemovedStream() {
    final events = StreamController<void>.broadcast();
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'backgroundUiRemoved') {
        throw MissingPluginException();
      }
      events.add(null);
    });
    return events.stream;
  }

  static Future<void> _invoke(
    String method, [
    Map<String, Object>? arguments,
  ]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // 桌面或测试环境没有这个 channel。
    } on PlatformException {
      // 权限被拒绝时保持静默，UI 仍可提示。
    }
  }
}
