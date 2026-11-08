import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../ffi/esf_types.dart';

class AccountProfile {
  const AccountProfile({
    required this.id,
    required this.account,
    this.displayName = '',
    this.server = '',
    this.port = 0,
    this.mscgip = '',
    this.mode = EsfMode.auto,
    this.autoConnect = false,
    this.keepEnabled = true,
    this.keepInterval = 0,
    this.preTerm = true,
    this.wifiSsid = '',
    this.wifiAutoLogin = false,
    this.wifiConnectOnLogin = true,
  });

  final String id;
  final String account;
  final String displayName;
  final String server;
  final int port;
  final String mscgip;
  final int mode;
  final bool autoConnect;
  final bool keepEnabled;
  final double keepInterval;
  final bool preTerm;

  /// 目标 Wi-Fi 的 SSID（实验性功能）；空字符串表示不管理 Wi-Fi。
  final String wifiSsid;

  /// 发现已连上 [wifiSsid] 且当前没有会话时，自动登录。
  final bool wifiAutoLogin;

  /// 点「登录」时若还没连上 [wifiSsid]，先唤起系统 Wi-Fi 面板并等待连上再登录。
  final bool wifiConnectOnLogin;

  /// 该账号是否启用了 Wi-Fi 联动。
  bool get wifiEnabled => wifiSsid.trim().isNotEmpty;

  String get title => displayName.isEmpty ? account : displayName;

  AccountProfile copyWith({
    String? displayName,
    String? server,
    int? port,
    String? mscgip,
    int? mode,
    bool? autoConnect,
    bool? keepEnabled,
    double? keepInterval,
    bool? preTerm,
    String? wifiSsid,
    bool? wifiAutoLogin,
    bool? wifiConnectOnLogin,
  }) => AccountProfile(
    id: id,
    account: account,
    displayName: displayName ?? this.displayName,
    server: server ?? this.server,
    port: port ?? this.port,
    mscgip: mscgip ?? this.mscgip,
    mode: mode ?? this.mode,
    autoConnect: autoConnect ?? this.autoConnect,
    keepEnabled: keepEnabled ?? this.keepEnabled,
    keepInterval: keepInterval ?? this.keepInterval,
    preTerm: preTerm ?? this.preTerm,
    wifiSsid: wifiSsid ?? this.wifiSsid,
    wifiAutoLogin: wifiAutoLogin ?? this.wifiAutoLogin,
    wifiConnectOnLogin: wifiConnectOnLogin ?? this.wifiConnectOnLogin,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'account': account,
    'displayName': displayName,
    'server': server,
    'port': port,
    'mscgip': mscgip,
    'mode': mode,
    'autoConnect': autoConnect,
    'keepEnabled': keepEnabled,
    'keepInterval': keepInterval,
    'preTerm': preTerm,
    'wifiSsid': wifiSsid,
    'wifiAutoLogin': wifiAutoLogin,
    'wifiConnectOnLogin': wifiConnectOnLogin,
  };

  factory AccountProfile.fromJson(Map<String, Object?> json) => AccountProfile(
    id: json['id'] as String? ?? '',
    account: json['account'] as String? ?? '',
    displayName: json['displayName'] as String? ?? '',
    server: json['server'] as String? ?? '',
    port: (json['port'] as num?)?.toInt() ?? 0,
    mscgip: json['mscgip'] as String? ?? '',
    mode: EsfMode.normalize((json['mode'] as num?)?.toInt() ?? EsfMode.auto),
    autoConnect: json['autoConnect'] as bool? ?? false,
    keepEnabled: json['keepEnabled'] as bool? ?? true,
    keepInterval: (json['keepInterval'] as num?)?.toDouble() ?? 0,
    preTerm: json['preTerm'] as bool? ?? true,
    wifiSsid: json['wifiSsid'] as String? ?? '',
    wifiAutoLogin: json['wifiAutoLogin'] as bool? ?? false,
    wifiConnectOnLogin: json['wifiConnectOnLogin'] as bool? ?? true,
  );
}

class UiConfig {
  const UiConfig({
    this.startMinimized = false,
    this.closeToTray = true,
    this.autoStart = false,
    this.logoutOnExit = false,
    this.notifications = true,
    this.logLevel = 'info',
  });

  final bool startMinimized;
  final bool closeToTray;
  final bool autoStart;
  final bool logoutOnExit;
  final bool notifications;

  /// 日志页的显示级别下限（debug / info / warn / error），默认 info。
  final String logLevel;

  UiConfig copyWith({
    bool? startMinimized,
    bool? closeToTray,
    bool? autoStart,
    bool? logoutOnExit,
    bool? notifications,
    String? logLevel,
  }) => UiConfig(
    startMinimized: startMinimized ?? this.startMinimized,
    closeToTray: closeToTray ?? this.closeToTray,
    autoStart: autoStart ?? this.autoStart,
    logoutOnExit: logoutOnExit ?? this.logoutOnExit,
    notifications: notifications ?? this.notifications,
    logLevel: logLevel ?? this.logLevel,
  );

  Map<String, Object?> toJson() => {
    'startMinimized': startMinimized,
    'closeToTray': closeToTray,
    'autoStart': autoStart,
    'logoutOnExit': logoutOnExit,
    'notifications': notifications,
    'logLevel': logLevel,
  };

  factory UiConfig.fromJson(Map<String, Object?> json) => UiConfig(
    startMinimized: json['startMinimized'] as bool? ?? false,
    closeToTray: json['closeToTray'] as bool? ?? true,
    autoStart: json['autoStart'] as bool? ?? false,
    logoutOnExit: json['logoutOnExit'] as bool? ?? false,
    notifications: json['notifications'] as bool? ?? true,
    logLevel: json['logLevel'] as String? ?? 'info',
  );
}

class AppConfig {
  const AppConfig({
    this.version = 1,
    this.accounts = const [],
    this.activeAccountId = '',
    this.clientId = '',
    this.savedMac = '',
    this.ui = const UiConfig(),
  });

  final int version;
  final List<AccountProfile> accounts;
  final String activeAccountId;
  final String clientId;
  final String savedMac;
  final UiConfig ui;

  AccountProfile? get activeAccount {
    for (final account in accounts) {
      if (account.id == activeAccountId) return account;
    }
    return accounts.isEmpty ? null : accounts.first;
  }

  AppConfig copyWith({
    List<AccountProfile>? accounts,
    String? activeAccountId,
    String? clientId,
    String? savedMac,
    UiConfig? ui,
  }) => AppConfig(
    version: version,
    accounts: accounts ?? this.accounts,
    activeAccountId: activeAccountId ?? this.activeAccountId,
    clientId: clientId ?? this.clientId,
    savedMac: savedMac ?? this.savedMac,
    ui: ui ?? this.ui,
  );

  Map<String, Object?> toJson() => {
    'version': version,
    'accounts': accounts.map((a) => a.toJson()).toList(),
    'activeAccountId': activeAccountId,
    'clientId': clientId,
    'savedMac': savedMac,
    'ui': ui.toJson(),
  };

  factory AppConfig.fromJson(Map<String, Object?> json) => AppConfig(
    version: (json['version'] as num?)?.toInt() ?? 1,
    accounts: (json['accounts'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (e) => AccountProfile.fromJson(
            e.map((k, v) => MapEntry(k.toString(), v)),
          ),
        )
        .toList(),
    activeAccountId: json['activeAccountId'] as String? ?? '',
    clientId: json['clientId'] as String? ?? '',
    savedMac: json['savedMac'] as String? ?? '',
    ui: UiConfig.fromJson(
      (json['ui'] as Map? ?? const {}).map((k, v) => MapEntry(k.toString(), v)),
    ),
  );
}

/// 版本化 JSON 配置，只保存账号资料与非敏感元数据。
class ConfigRepository {
  ConfigRepository._(this._file);

  static const int currentVersion = 1;

  final File _file;
  AppConfig _cache = const AppConfig();

  AppConfig get value => _cache;

  static Future<ConfigRepository> open() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final repo = ConfigRepository._(File('${dir.path}/config.json'));
    await repo.reload();
    return repo;
  }

  Future<void> reload() async {
    if (!await _file.exists()) {
      _cache = const AppConfig();
      return;
    }
    try {
      final raw = jsonDecode(await _file.readAsString());
      if (raw is Map<String, dynamic>) {
        _cache = AppConfig.fromJson(raw);
      }
    } on FormatException {
      // 配置损坏时保留一份备份，回到默认配置，避免应用无法启动。
      await _file.copy('${_file.path}.broken');
      _cache = const AppConfig();
    }
  }

  Future<void> save(AppConfig config) async {
    _cache = config;
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
      flush: true,
    );
    await tmp.rename(_file.path);
  }
}
