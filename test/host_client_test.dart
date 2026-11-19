import 'dart:isolate';

import 'package:esurfing_app/src/state/host_client.dart';
import 'package:flutter_test/flutter_test.dart';

void exitBeforeReady(List<Object?> args) {}

void exitAfterCommand(List<Object?> args) {
  final ui = args.first as SendPort;
  final receive = ReceivePort();
  ui.send(receive.sendPort);
  receive.listen((_) => receive.close());
}

void drainBeforeDispose(List<Object?> args) {
  final ui = args.first as SendPort;
  final receive = ReceivePort();
  ui.send(receive.sendPort);
  receive.listen((raw) async {
    final command = raw as Map;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    ui.send({'type': 'reply', 'id': command['id'], 'ok': true, 'data': {}});
    if (command['type'] == 'dispose') receive.close();
  });
}

void main() {
  test('握手前宿主退出立即失败，不等待就绪超时', () async {
    final host = HostClient(entryPoint: exitBeforeReady);
    await expectLater(
      host.start().timeout(const Duration(seconds: 2)),
      throwsStateError,
    );
    await host.dispose();
  });

  test('宿主退出后在途及后续命令立即失败', () async {
    final host = HostClient(entryPoint: exitAfterCommand);
    final failedState = host.states.first;
    await host.start();
    await expectLater(host.send('connect'), throwsStateError);
    await expectLater(host.send('connect'), throwsStateError);
    expect((await failedState).errorText, contains('退出'));
    await host.dispose();
  });

  test('dispose 等待宿主确认清理且禁止新命令，重复调用安全', () async {
    final host = HostClient(entryPoint: drainBeforeDispose);
    await host.start();
    final closing = host.dispose();
    await expectLater(host.send('connect'), throwsStateError);
    await Future.wait([closing, host.dispose()]);
  });
}
