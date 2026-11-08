import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'esf_bindings.dart';
import 'esf_models.dart';
import 'esf_types.dart';
import 'native_text.dart';

/// 后台会话宿主。UI isolate 只发命令，所有阻塞的 `esf_*` 调用都在这里串行执行。
void sessionHostMain(List<Object?> args) {
  final uiPort = args.first as SendPort;
  _SessionHost(uiPort).start();
}

class _SessionHost {
  _SessionHost(this._ui);

  final SendPort _ui;
  final ReceivePort _rx = ReceivePort();

  EsfBindings? _bindings;
  Pointer<EsfClient>? _client;
  NativeCallable<EsfEventCbNative>? _eventCallable;
  NativeCallable<EsfOwnedEventCbNative>? _ownedEventCallable;
  bool _online = false;
  String _lastMac = '';
  /// 本次会话的保活节奏（秒）。只从 connect 参数来，不看全局配置。
  double _keepInterval = 0;

  void start() {
    _ui.send(_rx.sendPort);
    _rx.listen(_onMessage);
  }

  EsfBindings get _b => _bindings ??= EsfBindings.instance;

  void _onMessage(Object? message) {
    if (message is! Map) return;
    final id = message['id'] as int?;
    if (id == null) return;
    final type = message['type'] as String? ?? '';
    final payload = (message['payload'] as Map?) ?? const {};
    try {
      final data = _handle(type, payload);
      _ui.send({'type': 'reply', 'id': id, 'ok': true, 'data': data});
      if (type == 'dispose') {
        _rx.close();
      }
    } catch (error) {
      _ui.send({
        'type': 'reply',
        'id': id,
        'ok': false,
        'error': error.toString(),
      });
    }
  }

  Map<String, Object?> _handle(String type, Map payload) {
    switch (type) {
      case 'version':
        return {'version': _b.version};
      case 'connect':
        return _connect(SessionParams.fromMap(payload));
      case 'disconnect':
        return _disconnect();
      case 'startKeep':
        return _startKeep();
      case 'stopKeep':
        return _stopKeep();
      case 'keepRunning':
        final client = _client;
        return {'running': client == null ? false : _b.keepRunning(client)};
      case 'dispose':
        _disconnect();
        _eventCallable?.close();
        _eventCallable = null;
        _ownedEventCallable?.close();
        _ownedEventCallable = null;
        return const {};
      default:
        throw StateError('未知命令：$type');
    }
  }

  Map<String, Object?> _connect(SessionParams params) {
    if (params.account.isEmpty || params.password.isEmpty) {
      throw StateError('账号或密码为空');
    }

    _teardownClient();
    _sendState(SessionPhase.connecting, '正在创建会话');
    final client = _b.create(params.mode);
    if (client == nullptr) {
      throw StateError('esf_create 失败（内存不足）');
    }
    _client = client;
    _installCallbacks(client);
    _keepInterval = params.keepInterval;

    final options = _makeOptions(preTerm: params.preTerm, keep: -1);
    final codeOut = calloc<Pointer<Utf8>>();
    final messageOut = calloc<Pointer<Utf8>>();
    try {
      _check(_b.setAccount(client, params.account, params.password), '设置账号');
      if (params.clientId.isEmpty) {
        throw StateError('Client-ID 为空，拒绝连接（会导致设备互相踢下线）');
      }
      _check(_b.setClientId(client, params.clientId), '设置 Client-ID');
      if (params.server.isNotEmpty) {
        _check(_b.setServer(client, params.server, params.port), '设置服务器');
        _b.setAllowDiscovery(client, false);
      }
      if (params.mscgip.isNotEmpty) {
        _check(_b.setMscgip(client, params.mscgip), '设置 mscgip');
      }
      if (params.mac.isNotEmpty) {
        _check(_b.setMac(client, params.mac), '设置 MAC');
      }
      if (params.mode != EsfMode.auto) {
        _check(_b.setMode(client, params.mode), '设置模式');
      }

      _sendState(SessionPhase.authenticating, '正在登录');
      final rc = _b.login(client, options, codeOut, messageOut);
      final code = _b.takeString(codeOut);
      final message = _b.takeString(messageOut);
      if (rc != EsfStatus.ok) {
        final detail = message.isNotEmpty ? message : _b.errorText(code);
        _online = false;
        _sendState(
          SessionPhase.error,
          detail.isEmpty ? '登录失败' : detail,
          errorCode: code,
          errorText: detail,
        );
        return {
          'ok': false,
          'status': rc,
          'errorCode': code,
          'errorMessage': detail,
        };
      }

      _online = true;
      var ipv4 = '';
      final ipOut = calloc<Pointer<Utf8>>();
      final macOut = calloc<Pointer<Utf8>>();
      try {
        if (_b.query(client, ipOut, macOut) == EsfStatus.ok) {
          ipv4 = _b.takeString(ipOut);
          _lastMac = _b.takeString(macOut);
        }
      } finally {
        calloc.free(ipOut);
        calloc.free(macOut);
      }

      _sendState(SessionPhase.online, '登录成功', ipv4: ipv4, mac: _lastMac);
      return {
        'ok': true,
        'status': rc,
        'errorCode': code,
        'errorMessage': message,
        'mac': _lastMac,
      };
    } catch (_) {
      _teardownClient();
      rethrow;
    } finally {
      calloc.free(options);
      calloc.free(codeOut);
      calloc.free(messageOut);
    }
  }

  Map<String, Object?> _disconnect() {
    final client = _client;
    if (client == null) {
      _sendState(SessionPhase.idle, '未连接');
      return const {'ok': true};
    }
    _sendState(SessionPhase.disconnecting, '正在断开');
    _stopKeepInternal(client);
    final options = _makeOptions(preTerm: false, keep: -1);
    final codeOut = calloc<Pointer<Utf8>>();
    final messageOut = calloc<Pointer<Utf8>>();
    try {
      final rc = _b.logout(client, options, codeOut, messageOut);
      final code = _b.takeString(codeOut);
      final message = _b.takeString(messageOut);
      _online = false;
      _teardownClient();
      _sendState(SessionPhase.idle, '已断开');
      return {
        'ok': rc == EsfStatus.ok,
        'status': rc,
        'errorCode': code,
        'errorMessage': message,
      };
    } finally {
      calloc.free(options);
      calloc.free(codeOut);
      calloc.free(messageOut);
    }
  }

  Map<String, Object?> _startKeep() {
    final client = _client;
    if (client == null || !_online) {
      throw StateError('尚未登录，无法保活');
    }
    final options = _makeOptions(preTerm: false, keep: 0);
    try {
      final rc = _b.keepStart(client, options);
      if (rc != EsfStatus.ok) {
        throw StateError('esf_keep_start 失败：${EsfStatus.describe(rc)}');
      }
      _sendState(SessionPhase.keeping, '保活中');
      return {'ok': true, 'running': true};
    } finally {
      calloc.free(options);
    }
  }

  Map<String, Object?> _stopKeep() {
    final client = _client;
    if (client == null) return const {'ok': true, 'running': false};
    _stopKeepInternal(client);
    _sendState(SessionPhase.online, '已停止保活');
    return const {'ok': true, 'running': false};
  }

  void _stopKeepInternal(Pointer<EsfClient> client) {
    try {
      _b.keepStop(client);
    } catch (_) {
      // 停止失败也要继续销毁，避免把原生线程留在后台。
    }
  }

  Pointer<EsfOptions> _makeOptions({required bool preTerm, required int keep}) {
    final options = calloc<EsfOptions>();
    _b.optionsInit(options);
    options.ref.preTerm = preTerm ? 1 : 0;
    options.ref.keep = keep;
    // 0 表示让核心用自己的内置默认值（10s），所以只在用户给了正数时覆盖。
    if (_keepInterval > 0) {
      options.ref.keepInterval = _keepInterval;
    }
    return options;
  }

  void _installCallbacks(Pointer<EsfClient> client) {
    // v1.2.0 起优先用「所有权转移」版：text 由原生库 malloc，宿主读完
    // esf_free。这样 NativeCallable.listener 的异步投递才不会读到悬空指针。
    final setOwned = _b.setOwnedEventCb;
    if (setOwned != null) {
      _ownedEventCallable ??= NativeCallable<EsfOwnedEventCbNative>.listener(
        _onOwnedNativeEvent,
      );
    } else {
      // 旧库回退：text 仅在回调期间有效，只能尽量容错地读。
      _eventCallable ??= NativeCallable<EsfEventCbNative>.listener(
        _onNativeEvent,
      );
    }

    final callbacks = calloc<EsfCallbacks>();
    try {
      callbacks.ref.user = nullptr;
      callbacks.ref.onEvent = setOwned != null
          ? nullptr
          : _eventCallable!.nativeFunction;
      callbacks.ref.onAsk = nullptr;
      callbacks.ref.onCancel = nullptr;
      _b.setCallbacks(client, callbacks);
    } finally {
      calloc.free(callbacks);
    }

    if (setOwned != null) {
      setOwned(client, _ownedEventCallable!.nativeFunction, nullptr);
    }
  }

  void _onOwnedNativeEvent(Pointer<Void> user, int kind, Pointer<Utf8> text) {
    try {
      _ui.send({
        'type': 'event',
        'kind': kind,
        'text': decodeNativeUtf8(text),
      });
    } finally {
      // 所有权在宿主这边，漏了就是每条事件泄漏一次。
      _b.free(text);
    }
  }

  void _onNativeEvent(Pointer<Void> user, int kind, Pointer<Utf8> text) {
    // 旧契约（< 1.2.0）：text 只在回调期间有效，而 NativeCallable.listener
    // 是异步投递，读取时必须容错（详见 decodeNativeUtf8 的注释）。
    _ui.send({
      'type': 'event',
      'kind': kind,
      'text': decodeNativeUtf8(text),
    });
  }

  void _check(int rc, String action) {
    if (rc != EsfStatus.ok) {
      throw StateError('$action失败：${EsfStatus.describe(rc)}');
    }
  }

  void _teardownClient() {
    final client = _client;
    if (client == null) return;
    _stopKeepInternal(client);
    _b.destroy(client);
    _client = null;
    _online = false;
  }

  void _sendState(
    SessionPhase phase,
    String message, {
    String errorCode = '',
    String errorText = '',
    String ipv4 = '',
    String mac = '',
  }) {
    _ui.send({
      'type': 'state',
      'state': SessionSnapshot(
        phase: phase,
        message: message,
        errorCode: errorCode,
        errorText: errorText,
        ipv4: ipv4,
        mac: mac.isEmpty ? _lastMac : mac,
        keepRunning: phase == SessionPhase.keeping,
      ).toMap(),
    });
  }
}
