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

/// IPv4 address and subnet prefix for the Wi-Fi interface (not the default route).
class WifiLinkAddress {
  const WifiLinkAddress({required this.address, required this.prefixLength});

  final String address;
  final int prefixLength;
}

class WifiNetwork {
  const WifiNetwork({
    required this.handle,
    required this.ssid,
    required this.interfaceName,
    required this.ipv4Addresses,
    required this.ready,
    this.gateway,
  });

  /// Android's opaque `Network.getNetworkHandle()` value, valid for this link
  /// lifetime. Never persist it or assume the same SSID keeps the same handle.
  final int handle;

  /// Exact SSID when Android exposes it; otherwise empty (not proof of loss).
  final String ssid;
  final String interfaceName;
  final List<WifiLinkAddress> ipv4Addresses;

  /// Numeric IPv4 gateway from this link's default route, if available.
  /// Its absence does not affect [ready].
  final String? gateway;

  /// App-unblocked interface with a usable IPv4 address. Neither internet
  /// validation nor a default route is required. SSID may still be unknown.
  final bool ready;
}

/// Full set of app-visible Android Wi-Fi links at one point in time.
class WifiNetworkSnapshot {
  const WifiNetworkSnapshot({
    this.supported = false,
    this.permissionGranted = false,
    this.networks = const [],
  });

  final bool supported;

  /// Fine location is granted; Android can still redact SSID (e.g. when
  /// device location is disabled).
  final bool permissionGranted;

  /// Candidates, not ranked by default status or readiness.
  final List<WifiNetwork> networks;

  static const unsupported = WifiNetworkSnapshot();

  factory WifiNetworkSnapshot.fromPlatform(Map<Object?, Object?> raw) {
    final networks = raw['networks'] as List<Object?>? ?? const [];
    return WifiNetworkSnapshot(
      supported: raw['supported'] == true,
      permissionGranted: raw['permissionGranted'] == true,
      networks: List.unmodifiable(
        networks.cast<Map<Object?, Object?>>().map((network) {
          return WifiNetwork(
            handle: network['handle'] as int,
            ssid: network['ssid'] as String,
            interfaceName: network['interfaceName'] as String,
            ipv4Addresses: List.unmodifiable(
              (network['ipv4Addresses'] as List<Object?>)
                  .cast<Map<Object?, Object?>>()
                  .map(
                    (link) => WifiLinkAddress(
                      address: link['address'] as String,
                      prefixLength: link['prefixLength'] as int,
                    ),
                  ),
            ),
            ready: network['ready'] == true,
            gateway: network['gateway'] as String?,
          );
        }),
      ),
    );
  }
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
  static const EventChannel _networkChannel = EventChannel(
    'esurfing/android/wifi_networks',
  );
  static final Stream<WifiNetworkSnapshot> _networkEvents = _networkChannel
      .receiveBroadcastStream()
      .map(
        (raw) => WifiNetworkSnapshot.fromPlatform(raw as Map<Object?, Object?>),
      );

  /// Windows 本期不实现 Wi-Fi 联动。
  static bool get supported => Platform.isAndroid;

  /// Returns the most recent callback state; discovery is asynchronous.
  static Future<WifiNetworkSnapshot> networkSnapshot() async {
    if (!supported) return WifiNetworkSnapshot.unsupported;
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>(
        'wifiNetworkSnapshot',
      );
      return raw == null
          ? WifiNetworkSnapshot.unsupported
          : WifiNetworkSnapshot.fromPlatform(raw);
    } on MissingPluginException {
      return WifiNetworkSnapshot.unsupported;
    } on PlatformException {
      return WifiNetworkSnapshot.unsupported;
    }
  }

  /// Broadcast stream of full snapshots. Android sends current state when
  /// observation starts, when it changes (including removals), and when the
  /// SSID permission dialog completes. Subscribers joining an active stream
  /// can fetch [networkSnapshot] for its current state.
  static Stream<WifiNetworkSnapshot> get networkEvents =>
      supported ? _networkEvents : const Stream.empty();

  static Future<WifiStatus> status() async {
    if (!supported) return WifiStatus.unsupported;
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('wifiStatus');
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

  /// 申请读取 SSID 所需的精确位置权限；仅「附近的设备」权限不足以读取 SSID。
  /// 返回当前授权状态，不等待对话框；处理结果后 Android 会刷新 [networkEvents]。
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
