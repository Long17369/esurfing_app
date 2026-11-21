import 'package:esurfing_app/src/data/config_repository.dart';
import 'package:esurfing_app/src/platform/wifi_shell.dart';
import 'package:esurfing_app/src/state/wifi_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Wi-Fi 自动登录判定', () {
    WifiAutoLoginDecision decide({
      String target = 'Campus',
      String current = 'Campus',
      String handled = '',
      bool enabled = true,
      bool session = false,
      bool busy = false,
    }) => decideWifiAutoLogin(
      target: target,
      current: current,
      alreadyHandled: handled,
      autoLoginEnabled: enabled,
      hasSession: session,
      busy: busy,
    );

    test('不在目标 Wi-Fi 时什么都不做', () {
      expect(decide(current: 'Home-5G'), WifiAutoLoginDecision.notOnTarget);
      expect(decide(current: ''), WifiAutoLoginDecision.notOnTarget);
      expect(decide(target: '  '), WifiAutoLoginDecision.notOnTarget);
    });

    test('刚连上目标 Wi-Fi 且没有会话时登录', () {
      expect(decide(), WifiAutoLoginDecision.login);
    });

    test('同一次连接只触发一次', () {
      expect(decide(handled: 'Campus'), WifiAutoLoginDecision.alreadyHandled);
    });

    test('已有会话时不动，保留票据', () {
      expect(decide(session: true), WifiAutoLoginDecision.keepSession);
      expect(decide(busy: true), WifiAutoLoginDecision.keepSession);
    });

    test('账号没开自动登录就只记录', () {
      expect(decide(enabled: false), WifiAutoLoginDecision.disabled);
    });

    test('目标带空格时按去空格比较', () {
      expect(
        decide(target: ' Campus ', current: 'Campus'),
        WifiAutoLoginDecision.login,
      );
    });
  });

  group('Wi-Fi 会话出口', () {
    WifiNetwork network(
      int handle, {
      String ssid = 'Campus',
      bool ready = true,
    }) => WifiNetwork(
      handle: handle,
      ssid: ssid,
      interfaceName: 'wlan0',
      ipv4Addresses: const [
        WifiLinkAddress(address: '192.0.2.5', prefixLength: 24),
      ],
      gateway: '192.0.2.1',
      ready: ready,
    );

    WifiNetworkSnapshot snapshot(List<WifiNetwork> networks) =>
        WifiNetworkSnapshot(permissionGranted: true, networks: networks);

    test('同 SSID 重连使用新句柄并允许复用票据', () {
      final initial = selectWifiRoute(snapshot([network(1)]), 'Campus')!;
      expect(
        selectWifiRoute(snapshot([]), 'Campus', previous: initial),
        isNull,
      );
      final resumed = selectWifiRoute(snapshot([network(2)]), 'Campus')!;
      expect(initial.sameRoute(resumed), isFalse);
      expect(initial.sameLink(resumed), isTrue);
    });

    test('未知 SSID、链路未就绪或身份不明确时不选择错误出口', () {
      final initial = selectWifiRoute(snapshot([network(1)]), 'Campus')!;
      expect(
        selectWifiRoute(snapshot([network(1, ssid: '')]), 'Campus'),
        isNull,
      );
      expect(
        selectWifiRoute(snapshot([network(1, ready: false)]), 'Campus'),
        isNull,
      );
      final ambiguous = snapshot([network(2), network(1)]);
      expect(selectWifiRoute(ambiguous, 'Campus'), isNull);
      expect(
        selectWifiRoute(ambiguous, 'Campus', previous: initial)?.handle,
        1,
      );
    });
  });

  group('账号的 Wi-Fi 配置', () {
    const base = AccountProfile(id: '1', account: '19000000000');

    test('默认不管理 Wi-Fi', () {
      expect(base.wifiSsid, '');
      expect(base.wifiEnabled, isFalse);
      expect(base.wifiAutoLogin, isFalse);
      expect(base.wifiConnectOnLogin, isTrue);
    });

    test('空白 SSID 视为未启用', () {
      expect(base.copyWith(wifiSsid: '   ').wifiEnabled, isFalse);
      expect(base.copyWith(wifiSsid: 'Campus').wifiEnabled, isTrue);
    });

    test('JSON 往返保留 Wi-Fi 字段', () {
      final profile = base.copyWith(
        wifiSsid: 'Campus-Auto',
        wifiAutoLogin: true,
        wifiConnectOnLogin: false,
      );
      final restored = AccountProfile.fromJson(profile.toJson());
      expect(restored.wifiSsid, 'Campus-Auto');
      expect(restored.wifiAutoLogin, isTrue);
      expect(restored.wifiConnectOnLogin, isFalse);
    });

    test('旧配置缺少 Wi-Fi 字段时用默认值', () {
      final restored = AccountProfile.fromJson({
        'id': '2',
        'account': '19000000001',
      });
      expect(restored.wifiSsid, '');
      expect(restored.wifiAutoLogin, isFalse);
      expect(restored.wifiConnectOnLogin, isTrue);
    });
  });
}
