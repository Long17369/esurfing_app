import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:esurfing_app/src/ffi/esf_bindings.dart';
import 'package:esurfing_app/src/ffi/esf_models.dart';
import 'package:esurfing_app/src/ffi/esf_session_host.dart';
import 'package:esurfing_app/src/ffi/esf_types.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeBindings extends EsfBindings {
  FakeBindings({this.owned = true, this.nativeVersion = '1.2.1'})
    : super.fromLibrary(DynamicLibrary.process());

  final bool owned;
  final String nativeVersion;
  int created = 0;
  int destroyed = 0;
  int loggedIn = 0;
  int freed = 0;
  int loginStatus = EsfStatus.ok;
  bool failSetup = false;
  bool failLogout = false;
  bool borrowedInstalled = false;
  EsfOwnedEventCbDart? event;

  @override
  String get version => nativeVersion;

  @override
  EsfSetOwnedEventCbDart? get setOwnedEventCb => owned
      ? (client, callback, user) {
          event = callback.asFunction<EsfOwnedEventCbDart>();
        }
      : null;

  @override
  Pointer<EsfClient> create(int mode) {
    created++;
    return Pointer.fromAddress(1);
  }

  @override
  void destroy(Pointer<EsfClient> client) {
    // 模拟 destroy 同步停止生产者前产生的最后一条 owned 事件。
    event?.call(nullptr, EsfEventKind.status, 'stopped'.toNativeUtf8());
    destroyed++;
  }

  @override
  void setCallbacks(
    Pointer<EsfClient> client,
    Pointer<EsfCallbacks> callbacks,
  ) {
    borrowedInstalled = callbacks.ref.onEvent != nullptr;
  }

  @override
  void optionsInit(Pointer<EsfOptions> options) {}

  @override
  int setAccount(Pointer<EsfClient> client, String account, String password) =>
      EsfStatus.ok;

  @override
  int setClientId(Pointer<EsfClient> client, String? value) =>
      failSetup ? -1 : EsfStatus.ok;

  @override
  int login(
    Pointer<EsfClient> client,
    Pointer<EsfOptions> options,
    Pointer<Pointer<Utf8>> code,
    Pointer<Pointer<Utf8>> message,
  ) {
    loggedIn++;
    event?.call(nullptr, EsfEventKind.status, 'login'.toNativeUtf8());
    return loginStatus;
  }

  @override
  int logout(
    Pointer<EsfClient> client,
    Pointer<EsfOptions> options,
    Pointer<Pointer<Utf8>> code,
    Pointer<Pointer<Utf8>> message,
  ) {
    if (failLogout) throw StateError('模拟注销失败');
    return EsfStatus.ok;
  }

  @override
  int query(
    Pointer<EsfClient> client,
    Pointer<Pointer<Utf8>> ip,
    Pointer<Pointer<Utf8>> mac,
  ) => EsfStatus.ok;

  @override
  int keepStop(Pointer<EsfClient> client) => EsfStatus.ok;

  @override
  String errorText(String? code) => '认证失败';

  @override
  void free(Pointer<Utf8> text) {
    if (text == nullptr) return;
    freed++;
    malloc.free(text);
  }
}

class HostHarness {
  HostHarness(this.bindings);

  final FakeBindings bindings;
  final ReceivePort receive = ReceivePort();
  late final StreamIterator<dynamic> messages = StreamIterator(receive);
  late SendPort port;
  final List<Map> received = [];
  int nextId = 0;

  Future<void> start() async {
    SessionHost(receive.sendPort, bindings: bindings).start();
    await messages.moveNext();
    port = messages.current as SendPort;
  }

  Future<Map> command(String type, [Map<String, Object?>? payload]) async {
    final id = ++nextId;
    port.send({'id': id, 'type': type, 'payload': payload ?? {}});
    while (await messages.moveNext()) {
      final message = messages.current as Map;
      received.add(message);
      if (message['type'] == 'reply' && message['id'] == id) return message;
    }
    throw StateError('Missing reply');
  }

  Future<Map> close() async {
    final reply = await command('dispose');
    await messages.cancel();
    receive.close();
    return reply;
  }
}

const params = SessionParams(
  account: 'offline-test',
  password: 'not-a-real-password',
  clientId: 'test-client',
);

void main() {
  test('旧库或不同 ABI 在创建客户端和认证前拒绝，并报告升级错误', () async {
    for (final bindings in [
      FakeBindings(owned: false),
      FakeBindings(nativeVersion: '2.0.0'),
    ]) {
      final host = HostHarness(bindings);
      await host.start();
      final version = await host.command('version');
      expect((version['data'] as Map)['compatibilityError'], contains('升级'));
      final reply = await host.command('connect', params.toMap());
      expect(reply['ok'], false);
      expect(reply['error'], contains('升级'));
      expect(bindings.created, 0);
      expect(bindings.loggedIn, 0);
      expect(bindings.borrowedInstalled, false);
      final state = host.received.lastWhere((m) => m['type'] == 'state');
      expect((state['state'] as Map)['phase'], 'error');
      await host.close();
    }
  });

  test('支持 owned 的库正常登录，dispose 排空并释放包含停止期间的事件', () async {
    final bindings = FakeBindings();
    final host = HostHarness(bindings);
    await host.start();
    final reply = await host.command('connect', params.toMap());
    expect((reply['data'] as Map)['ok'], true);
    expect(bindings.borrowedInstalled, false);
    await host.close();
    expect(bindings.loggedIn, 1);
    expect(bindings.destroyed, 1);
    expect(bindings.freed, 2);
  });

  test('设置异常和认证失败都销毁客户端，不停留在 connecting', () async {
    for (final bindings in [
      FakeBindings()..failSetup = true,
      FakeBindings()..loginStatus = -1,
    ]) {
      final host = HostHarness(bindings);
      await host.start();
      await host.command('connect', params.toMap());
      expect(bindings.destroyed, 1);
      final state = host.received.lastWhere((m) => m['type'] == 'state');
      expect((state['state'] as Map)['phase'], 'error');
      await host.close();
      expect(bindings.destroyed, 1);
    }
  });

  test('注销异常仍停止生产者并排空 dispose 事件', () async {
    final bindings = FakeBindings()..failLogout = true;
    final host = HostHarness(bindings);
    await host.start();
    await host.command('connect', params.toMap());
    final reply = await host.close();
    expect(reply['ok'], false);
    expect(bindings.destroyed, 1);
    expect(bindings.freed, 2);
  });
}
