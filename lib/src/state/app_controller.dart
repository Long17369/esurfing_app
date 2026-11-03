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
import 'host_client.dart';

class AppController extends ChangeNotifier {
  final ConfigRepository configRepository;
  final CredentialStore credentials;
  final LogRepository logs;
  final HostClient _host = HostClient();

  AppController({
    required this.configRepository,
    required this.credentials,
    required this.logs,
  });

  static const MethodChannel _android = MethodChannel('esurfing/android');

  AppConfig _config = const AppConfig();
  SessionSnapshot _snapshot = const SessionSnapshot();
  String _nativeVersion = '';
  String _lastError = '';
  bool _ready = false;
  bool _autoConnecting = false;
  int? _sessionMode;

  AppConfig get config => _config;
  SessionSnapshot get snapshot => _snapshot;
  String get nativeVersion => _nativeVersion;
  String get lastError => _lastError;
  bool get ready => _ready;
  List<AccountProfile> get accounts => _config.accounts;
  AccountProfile? get activeAccount => _config.activeAccount;

  /// 主页是否提供了本次登录的模式覆盖。
  bool get hasSessionModeOverride => _sessionMode != null;

  /// 本次登录实际使用的客户端模式：主页覆盖优先，其次账号配置。
  int get sessionMode =>
      _sessionMode ??
      EsfMode.normalize(activeAccount?.mode ?? EsfMode.auto);

  static Future<AppController> create() async {
    final controller = AppController(
      configRepository: await ConfigRepository.open(),
      credentials: CredentialStore(),
      logs: LogRepository(),
    );
    await controller._init();
    return controller;
  }

  Future<void> _init() async {
    await logs.init();
    _config = configRepository.value;

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

    _host.states.listen(_onState);
    _host.events.listen(_onEvent);
    try {
      await _host.start();
      final version = await _host.send('version');
      _nativeVersion = version['version']?.toString() ?? '';
      logs.add('原生后端版本：$_nativeVersion');
      if (!_versionCompatible(_nativeVersion)) {
        _lastError = '原生后端版本不符（$_nativeVersion），请重新构建。';
        logs.add(_lastError, level: LogLevel.error);
      }
    } catch (error) {
      _lastError = '原生后端加载失败：$error';
      logs.add(_lastError, level: LogLevel.error);
    }

    _ready = true;
    notifyListeners();
    unawaited(autoConnectIfNeeded());
  }

  bool _versionCompatible(String version) {
    if (version.isEmpty) return false;
    // 只校验原生库的 ABI 主版本；补丁/次版本与 App 自身版本号无关，
    // 两边各自独立递增（见 README「版本与兼容」）。
    return version.split('.').first == '1';
  }

  Future<void> autoConnectIfNeeded() async {
    if (_autoConnecting || _snapshot.isBusy || _snapshot.isOnline) return;
    final account = activeAccount;
    if (account == null || !account.autoConnect) return;
    _autoConnecting = true;
    try {
      await login();
    } finally {
      _autoConnecting = false;
    }
  }

  Future<void> login() async {
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

    final password = await credentials.read(account.account) ?? '';
    if (password.isEmpty) {
      _fail('账号 ${account.account} 没有保存密码，请重新输入');
      return;
    }

    _lastError = '';
    notifyListeners();
    logs.add(
      '开始登录：${account.account}（${EsfMode.label(sessionMode)}'
      '${hasSessionModeOverride ? '，主页覆盖' : ''}）',
    );

    try {
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
        ).toMap(),
      );
      final ok = result['ok'] == true;
      if (!ok) {
        final message = result['errorMessage']?.toString() ?? '登录失败';
        final code = result['errorCode']?.toString() ?? '';
        _lastError = _decorateError(code, message);
        logs.add(_lastError, level: LogLevel.error);
        notifyListeners();
        return;
      }

      final mac = result['mac']?.toString() ?? '';
      if (mac.isNotEmpty && mac != _config.savedMac && !Platform.isWindows) {
        _config = _config.copyWith(savedMac: mac);
        await configRepository.save(_config);
      }
      logs.add('登录成功');
      if (account.keepEnabled) await startKeep();
    } catch (error) {
      _fail('登录失败：$error');
    }
  }

  String _decorateError(String code, String message) {
    final hint = switch (code) {
      '102' => '（已有在线会话：可先注销再登录）',
      '105' => '（账号受限：到期/欠费/超流量，请勿反复重试）',
      '14' => '（无有效会话：请重新登录）',
      '1' => '（报文解析失败：可尝试切换 Windows/Android 模式）',
      _ => '',
    };
    return hint.isEmpty ? message : '$message$hint';
  }

  Future<void> logout() async {
    if (_snapshot.isBusy) return;
    _lastError = '';
    notifyListeners();
    try {
      await _host.send('disconnect');
      logs.add('已断开连接');
    } catch (error) {
      _fail('断开失败：$error');
    } finally {
      await _setAndroidService(false);
    }
  }

  Future<void> startKeep() async {
    try {
      await _host.send('startKeep');
      await _setAndroidService(true);
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
  Future<void> _setAndroidService(bool running) async {
    if (!Platform.isAndroid) return;
    try {
      await _android.invokeMethod<void>(
        running ? 'startSessionService' : 'stopSessionService',
      );
    } on PlatformException catch (error) {
      logs.add('前台服务调用失败：${error.message}', level: LogLevel.warn);
    } on MissingPluginException {
      // 非 Android 壳或测试环境。
    }
  }

  Future<void> saveAccount({
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
  }) async {
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
    _config = _config.copyWith(
      accounts: list,
      activeAccountId: _config.activeAccountId.isEmpty
          ? profile.id
          : _config.activeAccountId,
    );
    await configRepository.save(_config);
    logs.add('已保存账号：${profile.account}');
    notifyListeners();
  }

  Future<void> deleteAccount(String id) async {
    final target = _config.accounts.where((a) => a.id == id).firstOrNull;
    if (target == null) return;
    if (_config.activeAccountId == id && _snapshot.isOnline) {
      await logout();
    }
    final list = _config.accounts.where((a) => a.id != id).toList();
    _config = _config.copyWith(
      accounts: list,
      activeAccountId: list.isEmpty
          ? ''
          : (_config.activeAccountId == id ? list.first.id : null),
    );
    await configRepository.save(_config);
    await credentials.delete(target.account);
    notifyListeners();
  }

  Future<void> setActiveAccount(String id) async {
    if (_snapshot.isOnline) await logout();
    _config = _config.copyWith(activeAccountId: id);
    await configRepository.save(_config);
    notifyListeners();
  }

  /// 主页选择只作为「本次登录」的模式覆盖，不写回账号配置。
  /// 优先级：主页覆盖 > 账号配置 > 平台默认。
  Future<void> setSessionMode(int mode) async {
    if (_snapshot.isBusy) {
      _fail('连接进行中，请等本次操作结束后再切换客户端模式');
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
    _sessionMode = null;
    logs.add('已回落到账号的客户端模式：${EsfMode.label(sessionMode)}');
    notifyListeners();
  }

  Future<void> updateUi(UiConfig ui) async {
    _config = _config.copyWith(ui: ui);
    await configRepository.save(_config);
    notifyListeners();
  }

  void _onState(SessionSnapshot state) {
    _snapshot = state;
    if (state.errorText.isNotEmpty) _lastError = state.errorText;
    notifyListeners();
  }

  void _onEvent(SessionEvent event) {
    if (event.text.isEmpty) return;
    final level = switch (event.kind) {
      EsfEventKind.error => LogLevel.error,
      EsfEventKind.status || EsfEventKind.step => LogLevel.info,
      _ => LogLevel.debug,
    };
    logs.add('[${EsfEventKind.name(event.kind)}] ${event.text}', level: level);
  }

  void _fail(String message) {
    _lastError = message;
    logs.add(message, level: LogLevel.error);
    notifyListeners();
  }

  void clearError() {
    _lastError = '';
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_host.dispose());
    super.dispose();
  }
}
