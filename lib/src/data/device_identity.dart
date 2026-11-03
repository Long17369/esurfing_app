import 'dart:io';
import 'dart:math';

/// 设备身份：Client-ID 与伪 MAC。
///
/// Client-ID 每安装一份、跨账号共用，绝不能在两台设备上相同（核心会互相踢下线）。
/// 伪 MAC 只在系统隐藏真实 Wi-Fi MAC 的平台（Android 10+、iOS）使用，
/// 它是本设备稳定的本地管理地址，不锁死网卡。
abstract final class DeviceIdentity {
  static final Random _random = Random.secure();

  static String newClientId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int start, int end) => bytes
        .sublist(start, end)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }

  static String newPseudoMac() {
    final bytes = List<int>.generate(6, (_) => _random.nextInt(256));
    bytes[0] = 0x02; // 本地管理 + 单播
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');
  }

  /// Android 10+ 与 iOS 读不到真实 Wi-Fi MAC，需要伪 MAC。
  static bool get needsPseudoMac => Platform.isAndroid || Platform.isIOS;
}
