import 'dart:io';

import 'package:flutter/services.dart';

/// 一次 Wi-Fi 状态快照。
class WifiStatus {
  const WifiStatus({
    this.supported = false,
    this.enabled = false,
    this.ssid = '',
    this.permissionGranted = false,
  });

  /// 当前平台是否实现了 Wi-Fi 联动（目前只有 Android）。
  final bool supported;

  /// Wi-Fi 射频是否打开。
  final bool enabled;

  /// 当前连接的 SSID；未连接或没权限时为空。
  final String ssid;

  /// 是否已拿到读取 SSID 所需的运行时权限。
  final bool permissionGranted;

  bool get connected => ssid.isNotEmpty;

  static const WifiStatus unsupported = WifiStatus();

  @override
  String toString() =>
      'WifiStatus(supported: $supported, enabled: $enabled, ssid: $ssid, perm: $permissionGranted)';
}

/// Wi-Fi 联动的最小平台能力。
///
/// 平台事实（决定了这里的接口长什么样）：
/// - **Android 10+** 不允许 App 直接开 / 关 Wi-Fi（`setWifiEnabled` 被废弃且返回 false），
///   也不允许静默连接任意 SSID（`addNetwork` + `enableNetwork` 需要系统权限）。
///   所以这里只做「读当前 SSID」+「唤起系统 Wi-Fi 面板」，
///   真正的连接交给系统自动连接 / 用户点一下。
/// - **Windows** 本期不实现：`netsh wlan` 需要建配置文件、还要处理 GBK 输出，
///   功能先作为实验性只做 Android，Windows 侧一律返回不支持。
class WifiShell {
  static const MethodChannel _channel = MethodChannel('esurfing/android');

  /// Windows 本期不实现 Wi-Fi 联动。
  static bool get supported => Platform.isAndroid;

  static Future<WifiStatus> status() async {
    if (!supported) return WifiStatus.unsupported;
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'wifiStatus',
      );
      if (raw == null) return WifiStatus.unsupported;
      return WifiStatus(
        supported: raw['supported'] as bool? ?? true,
        enabled: raw['enabled'] as bool? ?? false,
        ssid: (raw['ssid'] as String? ?? '').trim(),
        permissionGranted: raw['permissionGranted'] as bool? ?? false,
      );
    } on MissingPluginException {
      return WifiStatus.unsupported;
    } on PlatformException {
      return WifiStatus.unsupported;
    }
  }

  /// 申请读取 SSID 所需的权限（Android 13+ 为「附近的设备」，以下为「位置信息」）。
  static Future<bool> requestPermission() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('requestWifiPermission') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 唤起系统 Wi-Fi 面板（Android 10+ 不允许 App 自己开关 Wi-Fi）。
  static Future<void> openPanel() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('openWifiPanel');
    } on MissingPluginException {
      // 非 Android 壳或测试环境。
    } on PlatformException {
      // 系统面板打不开时静默失败，UI 仍会提示用户手动连接。
    }
  }
}
