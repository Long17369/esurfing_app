import 'dart:io';

import 'package:esurfing_app/src/platform/wifi_shell.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes two distinct Wi-Fi handles, even with an unknown SSID', () {
    const codec = StandardMessageCodec();
    final payload = codec.encodeMessage({
      'supported': true,
      'permissionGranted': true,
      'networks': [
        {
          'handle': 0x10000cafed00d,
          'ssid': '',
          'interfaceName': 'wlan0',
          'ipv4Addresses': [
            {'address': '10.0.0.5', 'prefixLength': 24},
          ],
          'ready': true,
          'gateway': '10.0.0.1',
        },
        {
          'handle': 0x20000cafed00d,
          'ssid': ' 校园 Wi-Fi ',
          'interfaceName': '',
          'ipv4Addresses': [],
          'ready': false,
        },
      ],
    });
    final snapshot = WifiNetworkSnapshot.fromPlatform(
      codec.decodeMessage(payload) as Map<Object?, Object?>,
    );
    expect(snapshot.supported, isTrue);
    expect(snapshot.permissionGranted, isTrue);
    final [first, second] = snapshot.networks;
    expect(first.handle, 0x10000cafed00d);
    expect(first.ssid, isEmpty);
    expect(first.interfaceName, 'wlan0');
    expect(first.ipv4Addresses.single.address, '10.0.0.5');
    expect(first.ipv4Addresses.single.prefixLength, 24);
    expect(first.ready, isTrue);
    expect(first.gateway, '10.0.0.1');
    expect(second.handle, 0x20000cafed00d);
    expect(second.ssid, ' 校园 Wi-Fi ');
    expect(second.ready, isFalse);
    expect(second.gateway, isNull);
  });

  test('non-Android has no snapshot or event source', () async {
    final snapshot = await WifiShell.networkSnapshot();
    expect(snapshot.supported, isFalse);
    expect(snapshot.networks, isEmpty);
    await expectLater(WifiShell.networkEvents, emitsDone);
  }, skip: Platform.isAndroid);
}
