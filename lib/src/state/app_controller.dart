import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/config_repository.dart';
import '../data/credential_store.dart';
import '../data/device_identity.dart';
import '../data/log_repository.dart';
import '../ffi/esf_models.dart';
import '../ffi/esf_types.dart';
import '../platform/wifi_shell.dart';
import 'host_client.dart';
import 'wifi_rules.dart';

class AppController extends ChangeNotifier {
  final ConfigRepository configRepository;
  final CredentialStore credentials;
  final LogRepository logs;
  final HostClient _host;
  final Stream<WifiNetworkSnapshot>? _wifiEvents;

  AppController({
    required this.configRepository,
    required this.credentials,
    required this.logs,
    HostClient? host,
    this._wifiEvents,
  }) : _host = host ?? HostClient();

  static const MethodChannel _android = MethodChannel('esurfing/android');

  AppConfig _config = const AppConfig();
  SessionSnapshot _snapshot = const SessionSnapshot();
  String _nativeVersion = '';
  String _lastError = '';
  bool _ready = false;
  bool _autoConnecting = false;
  int? _sessionMode;

  WifiStatus _wifi = WifiStatus.unsupported;
  WifiNetworkSnapshot _wifiNetworks = WifiNetworkSnapshot.unsupported;
  StreamSubscription<WifiNetworkSnapshot>? _wifiNetworkSubscription;
  String _wifiSessionSsid = '';
  int _wifiSessionId = 0;
  ({String accountId, String ssid, int handle})? _wifiAutoLoginSuppression;
  bool _logoutInFlight = false;
  SessionWifiRoute? _sentWifiRoute;
  int? _lastSessionWifiHandle;
  Timer? _wifiTimer;
  bool _wifiPolling = false;
  String _pendingWifiSsid = '';
  DateTime? _pendingWifiDeadline;
  String _autoLoginSsidDone = '';
  bool _loginInFlight = false;
  bool _keepServiceStarted = false;
  bool _nativeWifiRecovery = false;
  bool _disposed = false;
  Future<void>? _shutdownFuture;
  StreamSubscription<SessionSnapshot>? _stateSubscription;
  StreamSubscription<SessionEvent>? _eventSubscription;
  String? _nativeCompatibilityError = '原生后端尚未就绪，请稍后重试';

  AppConfig get config => _config;
  SessionSnapshot get snapshot => _snapshot;
  String get nativeVersion => _nativeVersion;
  String get lastError => _lastError;
  bool get ready => _ready;
  List<AccountProfile> get accounts => _config.accounts;
  AccountProfile? get activeAccount => _config.activeAccount;

  /// 主页是否提供了本次登录的模式覆盖。
  bool get hasSessionModeOverride => _sessionMode != null;

  /// 该账号的配置/客户端模式是否被在线会话锁定。
  ///
  /// 连接中、认证中、已连接、保活中都不允许改动当前正在使用的账号，
  /// 避免配置和实际会话脱节。
  bool isAccountLocked(String id) =>
      activeAccount?.id == id && hasLockedSession;

  /// 当前是否存在「正在使用或正在进行」的会话（主页/设置用于禁用编辑入口）。
  bool get hasLockedSession =>
      _loginInFlight || _snapshot.isOnline || _snapshot.isBusy;

  /// 日志页的显示级别下限。
  LogLevel get logLevel => logs.minLevel;

  /// 最近一次读到的 Wi-Fi 状态（目前只有 Android 实现）。
  WifiStatus get wifi => _wifi;

  /// 当前平台是否实现了 Wi-Fi 联动。
  bool get wifiSupported => WifiShell.supported;

  /// 当前连接的 SSID；未连接或没权限时为空。
  String get currentSsid => _wifi.ssid;

  /// 当前账号的目标 SSID；空表示该账号不管理 Wi-Fi。
  String get targetSsid => (activeAccount?.wifiSsid ?? '').trim();

  /// 是否已经连在目标 Wi-Fi 上。
  bool get onTargetWifi => targetSsid.isNotEmpty && currentSsid == targetSsid;

  /// 是否正在「点登录 → 等系统连上目标 Wi-Fi → 再登录」。
  bool get waitingForWifi => _pendingWifiSsid.isNotEmpty;

  String get waitingForWifiSsid => _pendingWifiSsid;

  /// 保活间隔的人话描述：<=0 表示跟随核心内置默认（10 秒）。
  static String keepIntervalLabel(double seconds) {
    if (seconds <= 0) return '默认（10 秒）';
    final text = seconds == seconds.roundToDouble()
        ? seconds.toStringAsFixed(0)
        : seconds.toString();
    return '$text 秒';
  }

  /// 本次登录实际使用的客户端模式：主页覆盖优先，其次账号配置。
  int get sessionMode =>
      _sessionMode ?? EsfMode.normalize(activeAccount?.mode ?? EsfMode.auto);

  static Future<AppController> create() async {
    final controller = AppController(
      configRepository: await ConfigRepository.open(),
      credentials: CredentialStore(),
      logs: LogRepository(),
    );
    await controller.initialize();
    return controller;
  }

  Future<void> initialize() async {
    await logs.init();
    _config = configRepository.value;
    logs.minLevel = LogLevelX.parse(_config.ui.logLevel);

    var config = _config;
    if (config.clientId.isEmpty) {
      config = config.copyWith(clientId: DeviceIdentity.newClientId());
    }
    if (DeviceIdentity.needsPseudoMac && config.savedMac.isEmpty) {
      config = config.copyWith(savedMac: DeviceIdentity.newPseudoMac());
    }
    if (!identical(config, _config)) {
      await configRepository.save(config);
      _config = config;
    }

    _stateSubscription = _host.states.listen(_onState);
    _eventSubscription = _host.events.listen(_onEvent);
    try {
      await _host.start();
      final version = await _host.send('version');
      _nativeVersion = version['version']?.toString() ?? '';
      _nativeWifiRecovery = version['wifiRecovery'] == true;
      logs.add('原生后端版本：$_nativeVersion');
      _nativeCompatibilityError = version['compatibilityError'] as String?;
      if (_nativeCompatibilityError != null) {
        _lastError = _nativeCompatibilityError!;
        logs.add(_lastError, level: LogLevel.error);
      }
    } catch (error) {
      _lastError = '原生后端加载失败：$error';
      _nativeCompatibilityError = _lastError;
      logs.add(_lastError, level: LogLevel.error);
    }

    if (_disposed) return;
    _ready = true;
    _restartWifiWatch();
    notifyListeners();
    unawaited(autoConnectIfNeeded());
  }

  bool _canLogin() {
    final error = _nativeCompatibilityError;
    if (error == null) return true;
    _fail(error);
    return false;
  }

  Future<void> autoConnectIfNeeded() async {
    if (!_canLogin()) return;
    if (_autoConnecting || _snapshot.isBusy || _snapshot.isOnline) return;
    final account = activeAccount;
    if (account == null || !account.autoConnect) return;
    if (WifiShell.supported && account.wifiEnabled && account.wifiAutoLogin) {
      // 开了 Wi-Fi 联动就交给联动判定：只有连在目标 Wi-Fi 上才自动登录，
      // 否则（比如还在用蜂窝 / 别的 Wi-Fi）登进去也只会拿到 102。
      _maybeAutoLoginOnWifi();
      return;
    }
    _autoConnecting = true;
    try {
      await login();
    } finally {
      _autoConnecting = false;
    }
  }

  /// 主页「登录」按钮：先确保连在目标 Wi-Fi 上，再登录。
  ///
  /// Android 10+ 不允许 App 静默连接 / 开关 Wi-Fi，所以这里的做法是
  /// 唤起系统 Wi-Fi 面板让用户点一下，然后轮询 SSID，一旦连上目标 Wi-Fi
  /// 就自动继续登录 —— 对用户来说仍然是「点一次登录」。
  Future<void> loginWithWifi() async {
    if (!_canLogin()) return;
    final account = activeAccount;
    if (account == null) {
      _fail('请先添加账号');
      return;
    }
    _wifiAutoLoginSuppression = null;
    if (_snapshot.isBusy || _snapshot.isOnline) {
      await login();
      return;
    }
    final target = account.wifiSsid.trim();
    if (target.isEmpty || !account.wifiConnectOnLogin || !WifiShell.supported) {
      await login();
      return;
    }

    await _pollWifi();
    if (_routeForSsid(target) != null) {
      await login();
      return;
    }

    final needsPermission = !_wifi.permissionGranted;
    if (needsPermission) {
      await WifiShell.requestPermission();
      await _pollWifi();
      if (_routeForSsid(target) != null) {
        await login();
        return;
      }
    }
    _pendingWifiSsid = target;
    _pendingWifiDeadline = DateTime.now().add(const Duration(seconds: 120));
    logs.add('等待连接 Wi-Fi $target：已在系统面板里选好后会自动继续登录');
    notifyListeners();
    if (!needsPermission && currentSsid != target) await WifiShell.openPanel();
  }

  /// 放弃「等待 Wi-Fi → 自动登录」。
  void cancelWaitingForWifi() {
    if (_pendingWifiSsid.isEmpty) return;
    logs.add('已取消等待 Wi-Fi $_pendingWifiSsid');
    _pendingWifiSsid = '';
    _pendingWifiDeadline = null;
    notifyListeners();
  }

  /// 一次性读取当前 SSID（账号编辑页的「用当前 Wi-Fi」用）。
  Future<String> probeWifiSsid() async {
    if (!WifiShell.supported) return '';
    _wifi = await WifiShell.status();
    notifyListeners();
    return _wifi.ssid;
  }

  /// 申请读取 SSID 的运行时权限，返回是否已获得。
  Future<bool> requestWifiPermission() async {
    if (!WifiShell.supported) return false;
    final granted = await WifiShell.requestPermission();
    _wifi = await WifiShell.status();
    notifyListeners();
    return granted || _wifi.permissionGranted;
  }

  void _restartWifiWatch() {
    _wifiTimer?.cancel();
    _wifiTimer = null;
    final needed =
        (_wifiEvents != null || WifiShell.supported) &&
        _config.accounts.any((a) => a.wifiEnabled);
    if (!needed) {
      unawaited(_wifiNetworkSubscription?.cancel());
      _wifiNetworkSubscription = null;
      _wifiNetworks = WifiNetworkSnapshot.unsupported;
      _wifi = WifiStatus.unsupported;
      _pendingWifiSsid = '';
      _pendingWifiDeadline = null;
      return;
    }
    _wifiNetworkSubscription ??= (_wifiEvents ?? WifiShell.networkEvents)
        .listen(
          _onWifiNetworks,
          onError: (Object error) {
            logs.add('Wi-Fi 状态监听失败：$error', level: LogLevel.warn);
            _onWifiNetworks(WifiNetworkSnapshot.unsupported);
          },
        );
    unawaited(_pollWifi());
    _wifiTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_pollWifi()),
    );
  }

  Future<void> _pollWifi() async {
    if (_wifiPolling || !WifiShell.supported) return;
    _wifiPolling = true;
    try {
      final previous = _wifi;
      final next = await WifiShell.status();
      if (_disposed) return;
      _wifi = next;
      _onWifiUpdated(previous, next);
    } finally {
      _wifiPolling = false;
    }
  }

  void _onWifiUpdated(WifiStatus previous, WifiStatus next) {
    final changed =
        previous.ssid != next.ssid ||
        previous.enabled != next.enabled ||
        previous.permissionGranted != next.permissionGranted;

    if (previous.ssid != next.ssid && _wifiSessionSsid.isEmpty) {
      if (next.ssid.isEmpty) {
        logs.add('Wi-Fi 已断开');
      } else {
        logs.add('Wi-Fi 已连接：${next.ssid}');
      }
    }

    _maybeContinueWifiLogin();
    if (changed) notifyListeners();
  }

  SessionWifiRoute? _routeForSsid(String ssid, {SessionWifiRoute? previous}) =>
      selectWifiRoute(_wifiNetworks, ssid, previous: previous);

  void _onWifiNetworks(WifiNetworkSnapshot state) {
    if (_disposed || _wifiNetworkSubscription == null) return;
    _wifiNetworks = state;
    _updateSessionWifi();
    _maybeContinueWifiLogin();
    notifyListeners();
  }

  void _updateSessionWifi() {
    final ssid = _wifiSessionSsid;
    if (ssid.isEmpty) return;
    final previous = _sentWifiRoute;
    final route = _routeForSsid(ssid, previous: previous);
    if (route == null ? previous == null : previous?.sameRoute(route) == true) {
      return;
    }
    if (route == null) {
      logs.add('目标 Wi-Fi 暂不可用：保留会话票据，等待链路恢复');
    }
    _sentWifiRoute = route;
    if (route != null) _lastSessionWifiHandle = route.handle;
    unawaited(_sendWifiRoute(_wifiSessionId, route));
  }

  Future<void> _sendWifiRoute(int sessionId, SessionWifiRoute? route) async {
    try {
      await _host.send('updateWifi', {
        'sessionId': sessionId,
        'route': route?.toMap(),
      });
    } catch (error) {
      if (_wifiSessionId == sessionId) _fail('更新目标 Wi-Fi 失败：$error');
    }
  }

  void _maybeContinueWifiLogin() {
    if (_logoutInFlight) return;
    if (_pendingWifiSsid.isNotEmpty) {
      if (_routeForSsid(_pendingWifiSsid) != null) {
        final target = _pendingWifiSsid;
        _pendingWifiSsid = '';
        _pendingWifiDeadline = null;
        // 先占位，避免同一个 tick 里 _maybeAutoLoginOnWifi 再派发一次登录。
        _autoLoginSsidDone = target;
        logs.add('已连上 Wi-Fi $target，继续登录');
        unawaited(login());
      } else if (_pendingWifiDeadline != null &&
          DateTime.now().isAfter(_pendingWifiDeadline!)) {
        final target = _pendingWifiSsid;
        _pendingWifiSsid = '';
        _pendingWifiDeadline = null;
        _fail(
          _wifi.permissionGranted
              ? '等待 Wi-Fi $target 超时，请确认系统定位已开启，再手动连接并登录'
              : '无法识别目标 Wi-Fi：请授予精确位置权限后重试',
        );
      }
      return;
    }

    _maybeAutoLoginOnWifi();
  }

  void _maybeAutoLoginOnWifi() {
    final target = targetSsid;
    if (_disposed || _logoutInFlight || target.isEmpty) return;
    final route = _routeForSsid(target);
    final suppression = _wifiAutoLoginSuppression;
    if (suppression != null &&
        suppression.accountId == activeAccount?.id &&
        suppression.ssid == target) {
      // Redacted or temporarily unready links are not a new connection.
      if (route == null ||
          _wifiNetworks.networks.any(
            (link) => link.handle == suppression.handle,
          )) {
        return;
      }
      _wifiAutoLoginSuppression = null;
      _autoLoginSsidDone = '';
    }
    final matched = route != null;
    if (!matched && _autoLoginSsidDone == target) {
      // 离开目标 Wi-Fi 后清标记，下次再连回来可以重新触发一次。
      _autoLoginSsidDone = '';
    }
    final decision = decideWifiAutoLogin(
      target: target,
      current: matched ? target : '',
      alreadyHandled: _autoLoginSsidDone,
      autoLoginEnabled: activeAccount?.wifiAutoLogin ?? false,
      hasSession: _snapshot.isOnline,
      busy: _loginInFlight || _snapshot.isBusy,
    );
    switch (decision) {
      case WifiAutoLoginDecision.notOnTarget:
      case WifiAutoLoginDecision.alreadyHandled:
        return;
      case WifiAutoLoginDecision.disabled:
        _autoLoginSsidDone = target;
        logs.add('已连上 $target（该账号未开启 Wi-Fi 自动登录）');
        return;
      case WifiAutoLoginDecision.keepSession:
        _autoLoginSsidDone = target;
        return;
      case WifiAutoLoginDecision.login:
        _autoLoginSsidDone = target;
        logs.add('检测到目标 Wi-Fi $target，自动登录');
        unawaited(login());
        return;
    }
  }

  Future<void> login() async {
    if (_disposed) return;
    if (!_canLogin()) return;
    // 登录是同步阻塞的原生调用，重复派发会连做两次 term+auth，票据也会被用掉。
    if (_loginInFlight || _logoutInFlight) return;
    _loginInFlight = true;
    try {
      await _login();
    } catch (error) {
      if (_snapshot.isBusy) {
        _snapshot = const SessionSnapshot(phase: SessionPhase.error);
      }
      _fail('登录失败：$error');
    } finally {
      _loginInFlight = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _login() async {
    final account = activeAccount;
    if (account == null) {
      _fail('请先添加账号');
      return;
    }
    if (_snapshot.isBusy) return;
    if (_snapshot.isOnline) {
      _fail('已有账号在线，请先断开再登录其它账号');
      return;
    }

    _snapshot = const SessionSnapshot(
      phase: SessionPhase.connecting,
      message: '正在读取凭据',
    );
    notifyListeners();
    final password = await credentials.read(account.account) ?? '';
    if (_disposed) return;
    if (password.isEmpty) {
      _snapshot = const SessionSnapshot(phase: SessionPhase.error);
      _fail('账号 ${account.account} 没有保存密码，请重新输入');
      return;
    }

    _lastError = '';
    notifyListeners();
    logs.add(
      '开始登录：${account.account}（${EsfMode.label(sessionMode)}'
      '${hasSessionModeOverride ? '，主页覆盖' : ''}；'
      '保活间隔 ${keepIntervalLabel(account.keepInterval)}）',
    );

    try {
      final target = account.wifiSsid.trim();
      var route = _routeForSsid(target);
      if (WifiShell.supported &&
          target.isNotEmpty &&
          account.wifiConnectOnLogin &&
          route == null) {
        _snapshot = const SessionSnapshot(phase: SessionPhase.error);
        _fail('目标 Wi-Fi 尚不可用，无法开始认证。');
        return;
      }
      if (route != null) {
        if (!_nativeWifiRecovery) {
          _snapshot = const SessionSnapshot(phase: SessionPhase.error);
          _fail('当前原生库不支持 Wi-Fi 会话恢复，请更新应用。');
          return;
        }
        if (account.keepEnabled) {
          await _setAndroidService(true, wifiLocation: true);
          route = _routeForSsid(target, previous: route);
          if (route == null || _disposed) {
            await _setAndroidService(false);
            _snapshot = const SessionSnapshot(phase: SessionPhase.error);
            _fail('目标 Wi-Fi 已断开，未开始认证。');
            return;
          }
        }
        _wifiSessionId++;
        _wifiSessionSsid = target;
        _sentWifiRoute = route;
        _lastSessionWifiHandle = route.handle;
      }
      final result = await _host.send(
        'connect',
        SessionParams(
          account: account.account,
          password: password,
          clientId: _config.clientId,
          server: account.server,
          port: account.port,
          mscgip: account.mscgip,
          mode: sessionMode,
          mac: _config.savedMac,
          keepInterval: account.keepInterval,
          preTerm: account.preTerm,
          wifiRoute: route,
          wifiSessionId: _wifiSessionId,
        ).toMap(),
      );
      final ok = result['ok'] == true;
      if (!ok) {
        _clearWifiSession();
        await _setAndroidService(false);
        final message = result['errorMessage']?.toString() ?? '登录失败';
        final code = result['errorCode']?.toString() ?? '';
        final status = result['status'];
        final issue = route != null && status == EsfStatus.prepare
            ? '$message。目标 Wi-Fi 的门户或认证服务未能访问，请查看连接日志。'
            : message;
        _lastError = _decorateError(code, issue);
        logs.add(_lastError, level: LogLevel.error);
        notifyListeners();
        return;
      }

      if (route != null) {
        unawaited(_revalidateAuthenticatedWifi(_wifiSessionId, route.handle));
      }
      final mac = result['mac']?.toString() ?? '';
      if (mac.isNotEmpty && mac != _config.savedMac && !Platform.isWindows) {
        final nextConfig = _config.copyWith(savedMac: mac);
        try {
          await configRepository.save(nextConfig);
          _config = nextConfig;
        } catch (error) {
          logs.add('登录成功，但保存 MAC 失败：$error', level: LogLevel.warn);
        }
      }
      logs.add('登录成功');
      if (account.keepEnabled) await startKeep();
    } catch (error) {
      _clearWifiSession();
      await _setAndroidService(false);
      if (_snapshot.isBusy) {
        _snapshot = const SessionSnapshot(phase: SessionPhase.error);
      }
      _fail('登录失败：$error');
    }
  }

  Future<void> _revalidateAuthenticatedWifi(int sessionId, int handle) async {
    bool isCurrent() =>
        !_disposed &&
        !_logoutInFlight &&
        _wifiSessionId == sessionId &&
        _sentWifiRoute?.handle == handle;

    if (!isCurrent()) return;
    final args = {'handle': handle};
    try {
      final reachable = await _android.invokeMethod<bool>(
        'probeWifiInternet',
        args,
      );
      if (!isCurrent() || reachable == null) return;
      if (!reachable) {
        logs.add('校园网认证成功，但目标 Wi-Fi 的公网探测未通过', level: LogLevel.warn);
        return;
      }
      final requested = await _android.invokeMethod<bool>(
        'requestWifiRevalidation',
        args,
      );
      if (isCurrent() && requested == true) {
        logs.add('已请求 Android 重新验证目标 Wi-Fi');
      }
    } on PlatformException catch (error) {
      if (isCurrent()) {
        logs.add('目标 Wi-Fi 重新验证请求失败：${error.code}', level: LogLevel.warn);
      }
    } on MissingPluginException {
      if (isCurrent()) {
        logs.add('当前平台未提供 Wi-Fi 重新验证接口', level: LogLevel.warn);
      }
    }
  }

  String _decorateError(String code, String message) {
    final hint = switch (code) {
      '102' =>
        '（已有在线会话：可先断开再登录。若反复出现，请确认原生库为 esurfing_c 1.2.1+，'
            '旧版本会把保存的 MAC 与另一块网卡的 IPv4 配对，服务端必然拒）',
      '105' => '（账号受限：到期/欠费/超流量，请勿反复重试）',
      '14' => '（无有效会话：请重新登录）',
      '1' => '（报文解析失败：可尝试切换 Windows/Android 模式）',
      _ => '',
    };
    return hint.isEmpty ? message : '$message$hint';
  }

  Future<void> logout() => _logout();

  Future<void> _logout({bool reconsiderWifi = true}) async {
    if (_loginInFlight || _logoutInFlight || _snapshot.isBusy) return;
    _logoutInFlight = true;
    final account = activeAccount;
    final ssid = targetSsid;
    final handle =
        _routeForSsid(ssid, previous: _sentWifiRoute)?.handle ??
        (_wifiSessionSsid == ssid ? _lastSessionWifiHandle : null);
    if (account != null && handle != null && ssid.isNotEmpty) {
      _wifiAutoLoginSuppression = (
        accountId: account.id,
        ssid: ssid,
        handle: handle,
      );
    }
    _pendingWifiSsid = '';
    _pendingWifiDeadline = null;
    _clearWifiSession();
    _lastError = '';
    notifyListeners();
    try {
      final result = await _host.send('disconnect');
      if (result['ok'] != true) {
        _fail(
          '本地会话已关闭，但服务器注销失败：'
          '${result['errorMessage'] ?? result['errorCode'] ?? '未知错误'}',
        );
        return;
      }

      logs.add('已断开连接');
    } catch (error) {
      _fail('断开失败：$error');
    } finally {
      try {
        await _setAndroidService(false);
      } finally {
        _logoutInFlight = false;
        if (reconsiderWifi) _maybeAutoLoginOnWifi();
      }
    }
  }

  void _clearWifiSession() {
    _wifiSessionId++;
    _wifiSessionSsid = '';
    _sentWifiRoute = null;
    _lastSessionWifiHandle = null;
  }

  Future<void> startKeep() async {
    try {
      await _host.send('startKeep');
      if (!_keepServiceStarted) {
        await _setAndroidService(
          true,
          wifiLocation: _wifiSessionSsid.isNotEmpty,
        );
      }
      logs.add('保活已启动');
    } catch (error) {
      _fail('保活启动失败：$error');
    }
  }

  Future<void> stopKeep() async {
    try {
      await _host.send('stopKeep');
      await _setAndroidService(false);
      logs.add('保活已停止');
    } catch (error) {
      _fail('保活停止失败：$error');
    }
  }

  /// 前台服务只负责持有进程，真正保活在 SessionHost。
  Future<void> _setAndroidService(
    bool running, {
    bool wifiLocation = false,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      if (running) {
        final scoped = await _android.invokeMethod<bool>(
          'startSessionService',
          {'wifiLocation': wifiLocation},
        );
        _keepServiceStarted = true;
        if (wifiLocation && scoped != true) {
          logs.add('未能在前台取得 Wi-Fi 识别权限；后台重连可能需要先打开应用。', level: LogLevel.warn);
        }
      } else {
        _keepServiceStarted = false;
        await _android.invokeMethod<void>('stopSessionService');
      }
    } on PlatformException catch (error) {
      logs.add('前台服务调用失败：${error.message}', level: LogLevel.warn);
    } on MissingPluginException {
      // 非 Android 壳或测试环境。
    }
  }

  /// 保存/更新账号资料。返回 false 表示被在线会话或校验挡住，没有写入。
  Future<bool> saveAccount({
    String? id,
    required String account,
    required String password,
    String displayName = '',
    String server = '',
    int port = 0,
    String mscgip = '',
    int mode = EsfMode.auto,
    bool autoConnect = false,
    bool keepEnabled = true,
    double keepInterval = 0,
    bool preTerm = true,
    String wifiSsid = '',
    bool wifiAutoLogin = false,
    bool wifiConnectOnLogin = true,
  }) async {
    if (id != null && isAccountLocked(id)) {
      _fail('该账号正在使用中，请先断开连接再修改配置');
      return false;
    }
    final existing = id == null
        ? null
        : _config.accounts.where((a) => a.id == id).firstOrNull;
    final profile = AccountProfile(
      id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      account: account,
      displayName: displayName,
      server: server,
      port: port,
      mscgip: mscgip,
      mode: EsfMode.normalize(mode),
      autoConnect: autoConnect,
      keepEnabled: keepEnabled,
      keepInterval: keepInterval,
      preTerm: preTerm,
      wifiSsid: wifiSsid.trim(),
      wifiAutoLogin: wifiAutoLogin,
      wifiConnectOnLogin: wifiConnectOnLogin,
    );
    if (password.isNotEmpty) {
      await credentials.write(account, password);
    }

    final list = [..._config.accounts];
    final index = list.indexWhere((a) => a.id == profile.id);
    if (index >= 0) {
      list[index] = profile;
    } else {
      list.add(profile);
    }
    final nextConfig = _config.copyWith(
      accounts: list,
      activeAccountId: activeAccount?.id ?? profile.id,
    );
    await configRepository.save(nextConfig);
    _config = nextConfig;
    logs.add('已保存账号：${profile.account}');
    _restartWifiWatch();
    notifyListeners();
    return true;
  }

  Future<void> deleteAccount(String id) async {
    if (isAccountLocked(id)) {
      _fail('该账号正在使用中，请先断开连接再删除');
      return;
    }
    final target = _config.accounts.where((a) => a.id == id).firstOrNull;
    if (target == null) return;
    final list = _config.accounts.where((a) => a.id != id).toList();
    final nextConfig = _config.copyWith(
      accounts: list,
      activeAccountId: list.isEmpty
          ? ''
          : (_config.activeAccountId == id ? list.first.id : null),
    );
    await configRepository.save(nextConfig);
    _config = nextConfig;
    if (!list.any((profile) => profile.account == target.account)) {
      await credentials.delete(target.account);
    }
    _restartWifiWatch();
    notifyListeners();
  }

  /// 切换活动账号。已连接时会先断开（UI 会先弹确认）。
  Future<void> setActiveAccount(String id) async {
    if (_snapshot.isBusy || _loginInFlight) {
      _fail('操作进行中，请稍后再切换账号');
      return;
    }
    if (_config.activeAccountId == id) return;
    if (_snapshot.isOnline) {
      await _logout(reconsiderWifi: false);
      if (_snapshot.isOnline || _snapshot.isBusy) return;
    }
    final nextConfig = _config.copyWith(activeAccountId: id);
    await configRepository.save(nextConfig);
    _config = nextConfig;
    // 换了账号就换了目标 Wi-Fi，允许在新目标上重新触发一次自动登录。
    _autoLoginSsidDone = '';
    _wifiAutoLoginSuppression = null;
    _restartWifiWatch();
    notifyListeners();
  }

  /// 主页选择只作为「本次登录」的模式覆盖，不写回账号配置。
  /// 优先级：主页覆盖 > 账号配置 > 平台默认。
  Future<void> setSessionMode(int mode) async {
    if (_snapshot.isBusy || _snapshot.isOnline) {
      _fail(
        _snapshot.isOnline ? '已连接，请先断开再修改客户端模式' : '连接进行中，请等本次操作结束后再切换客户端模式',
      );
      return;
    }
    final target = EsfMode.normalize(mode);
    final accountMode = EsfMode.normalize(activeAccount?.mode ?? EsfMode.auto);
    if (target == accountMode) {
      clearSessionMode();
      return;
    }
    if (_sessionMode == target) return;
    _sessionMode = target;
    logs.add('本次登录使用 ${EsfMode.label(target)}（不修改账号配置）');
    notifyListeners();
  }

  /// 取消主页覆盖，回落到账号自身的客户端模式。
  void clearSessionMode() {
    if (_sessionMode == null) return;
    if (_snapshot.isBusy || _snapshot.isOnline) {
      _fail('已连接，请先断开再修改客户端模式');
      return;
    }
    _sessionMode = null;
    logs.add('已回落到账号的客户端模式：${EsfMode.label(sessionMode)}');
    notifyListeners();
  }

  Future<void> updateUi(UiConfig ui) async {
    final nextConfig = _config.copyWith(ui: ui);
    await configRepository.save(nextConfig);
    _config = nextConfig;
    logs.minLevel = LogLevelX.parse(ui.logLevel, fallback: logs.minLevel);
    notifyListeners();
  }

  /// 切换日志页的显示级别并持久化到 `ui.logLevel`。
  Future<void> setLogLevel(LogLevel level) async {
    await updateUi(_config.ui.copyWith(logLevel: level.name));
  }

  void _onState(SessionSnapshot state) {
    if (_disposed) return;
    _snapshot = state;
    if (state.errorText.isNotEmpty) _lastError = state.errorText;
    notifyListeners();
  }

  void _onEvent(SessionEvent event) {
    if (_disposed) return;
    if (event.text.isEmpty) return;
    final level = switch (event.kind) {
      EsfEventKind.error => LogLevel.error,
      EsfEventKind.status || EsfEventKind.step => LogLevel.info,
      _ => LogLevel.debug,
    };
    logs.add('[${EsfEventKind.name(event.kind)}] ${event.text}', level: level);
  }

  void _fail(String message) {
    if (_disposed) return;
    _lastError = message;
    logs.add(message, level: LogLevel.error);
    notifyListeners();
  }

  void clearError() {
    _lastError = '';
    notifyListeners();
  }

  Future<void> shutdown() => _shutdownFuture ??= _shutdown();

  Future<void> _shutdown() async {
    _disposed = true;
    _wifiTimer?.cancel();
    await _wifiNetworkSubscription?.cancel();
    await _stateSubscription?.cancel();
    await _eventSubscription?.cancel();
    await _host.dispose();
  }

  @override
  void dispose() {
    unawaited(shutdown());
    super.dispose();
  }
}
