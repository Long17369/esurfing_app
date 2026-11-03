import 'dart:async';
import 'dart:isolate';

import '../ffi/esf_models.dart';
import '../ffi/esf_session_host.dart';

class SessionEvent {
  const SessionEvent(this.kind, this.text);

  final int kind;
  final String text;
}

/// UI isolate 侧的宿主代理：命令 + 状态流 + 原生事件流。
class HostClient {
  final ReceivePort _rx = ReceivePort();
  final Map<int, Completer<Map<String, Object?>>> _pending = {};
  final StreamController<SessionSnapshot> _states =
      StreamController<SessionSnapshot>.broadcast();
  final StreamController<SessionEvent> _events =
      StreamController<SessionEvent>.broadcast();
  final Completer<SendPort> _ready = Completer<SendPort>();

  final ReceivePort _isolateErrors = ReceivePort();
  final ReceivePort _isolateExits = ReceivePort();
  Isolate? _isolate;
  int _nextId = 1;
  bool _disposed = false;

  Stream<SessionSnapshot> get states => _states.stream;
  Stream<SessionEvent> get events => _events.stream;

  Future<void> start() async {
    _rx.listen(_onMessage);
    _isolate = await Isolate.spawn(
      sessionHostMain,
      [_rx.sendPort],
      debugName: 'esf-session-host',
      onError: _isolateErrors.sendPort,
      onExit: _isolateExits.sendPort,
    );
    _isolateErrors.listen((message) {
      if (message is List && message.isNotEmpty) {
        _failAll(StateError('会话宿主异常：${message.first}'));
      }
    });
    _isolateExits.listen((_) => _onIsolateExit());
    await _ready.future.timeout(const Duration(seconds: 10));
  }

  Future<Map<String, Object?>> send(
    String type, [
    Map<String, Object?> payload = const {},
  ]) async {
    if (_disposed) throw StateError('会话宿主已关闭');
    final port = await _ready.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw StateError('会话宿主未就绪'),
    );
    final id = _nextId++;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    port.send({'id': id, 'type': type, 'payload': payload});
    return completer.future.timeout(
      const Duration(minutes: 3),
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('原生调用超时（$type）', const Duration(minutes: 3));
      },
    );
  }

  void _onMessage(Object? message) {
    if (message is SendPort) {
      if (!_ready.isCompleted) _ready.complete(message);
      return;
    }
    if (message is! Map) return;
    switch (message['type']) {
      case 'reply':
        final id = message['id'] as int?;
        final completer = id == null ? null : _pending.remove(id);
        if (completer == null || completer.isCompleted) return;
        final data = (message['data'] as Map?) ?? const {};
        if (message['ok'] == true) {
          completer.complete(
            data.map((k, v) => MapEntry(k.toString(), v as Object?)),
          );
        } else {
          completer.completeError(
            StateError(message['error']?.toString() ?? '原生调用失败'),
          );
        }
        break;
      case 'state':
        final state = message['state'];
        if (state is Map) {
          _states.add(
            SessionSnapshot.fromMap(
              state.map((k, v) => MapEntry(k.toString(), v)),
            ),
          );
        }
        break;
      case 'event':
        _events.add(
          SessionEvent(
            (message['kind'] as num?)?.toInt() ?? 0,
            message['text']?.toString() ?? '',
          ),
        );
        break;
    }
  }

  void _onIsolateExit() {
    if (_disposed) return;
    _failAll(StateError('会话宿主已退出'));
  }

  void _failAll(Object error) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    try {
      await send('dispose').timeout(const Duration(seconds: 5));
    } catch (_) {
      // 宿主可能已经退出；直接终止即可。
    }
    _disposed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _rx.close();
    _isolateErrors.close();
    _isolateExits.close();
    await _states.close();
    await _events.close();
  }
}
