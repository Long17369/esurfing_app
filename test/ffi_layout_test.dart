import 'dart:ffi';

import 'package:esurfing_app/src/ffi/esf_models.dart';
import 'package:esurfing_app/src/ffi/esf_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FFI ABI', () {
    test('EsfOptions 与 C 结构体布局一致', () {
      // int preTerm; int keep; double x3; int keepRetryTries; int keepReauthAfter;
      // 4 + 4 + 24 + 4 + 4 = 40，64 位下 double 8 字节对齐。
      expect(sizeOf<EsfOptions>(), 40);
      // double 字段要求 8 字节对齐，由 sizeOf 间接验证。
    });

    test('EsfCallbacks 为四个指针', () {
      expect(sizeOf<EsfCallbacks>(), 4 * sizeOf<Pointer<Void>>());
    });
  });

  group('会话模型', () {
    test('SessionParams 往返序列化', () {
      const params = SessionParams(
        account: '13800000000',
        password: 'secret',
        clientId: 'client-1',
        server: '1.2.3.4',
        port: 8080,
        keepInterval: 30,
        preTerm: false,
      );
      final restored = SessionParams.fromMap(params.toMap());
      expect(restored.account, params.account);
      expect(restored.port, params.port);
      expect(restored.keepInterval, params.keepInterval);
      expect(restored.preTerm, isFalse);
    });

    test('SessionSnapshot 往返序列化', () {
      const snapshot = SessionSnapshot(
        phase: SessionPhase.keeping,
        message: '保活中',
        ipv4: '10.0.0.2',
        mac: '02:11:22:33:44:55',
        keepRunning: true,
      );
      final restored = SessionSnapshot.fromMap(snapshot.toMap());
      expect(restored.phase, SessionPhase.keeping);
      expect(restored.isOnline, isTrue);
      expect(restored.mac, snapshot.mac);
    });

    test('客户端模式只暴露 Windows / Android，「自动」归一为平台默认', () {
      expect(EsfMode.normalize(EsfMode.windows), EsfMode.windows);
      expect(EsfMode.normalize(EsfMode.android), EsfMode.android);
      expect(EsfMode.normalize(EsfMode.auto), EsfMode.platformDefault);
      expect(EsfMode.normalize(99), EsfMode.platformDefault);
    });
  });
}
