enum SessionPhase {
  idle,
  connecting,
  authenticating,
  online,
  keeping,
  wifiWaiting,
  disconnecting,
  error;

  static SessionPhase fromName(String? name) => SessionPhase.values.firstWhere(
    (p) => p.name == name,
    orElse: () => SessionPhase.idle,
  );

  String get label => switch (this) {
    SessionPhase.idle => '未连接',
    SessionPhase.connecting => '准备中',
    SessionPhase.authenticating => '认证中',
    SessionPhase.online => '已连接',
    SessionPhase.keeping => '保活中',
    SessionPhase.wifiWaiting => '等待 Wi-Fi 恢复',
    SessionPhase.disconnecting => '正在断开',
    SessionPhase.error => '出错',
  };
}

class SessionSnapshot {
  const SessionSnapshot({
    this.phase = SessionPhase.idle,
    this.message = '',
    this.errorCode = '',
    this.errorText = '',
    this.ipv4 = '',
    this.mac = '',
    this.keepRunning = false,
    this.account = '',
  });

  final SessionPhase phase;
  final String message;
  final String errorCode;
  final String errorText;
  final String ipv4;
  final String mac;
  final bool keepRunning;
  final String account;

  bool get isBusy =>
      phase == SessionPhase.connecting ||
      phase == SessionPhase.authenticating ||
      phase == SessionPhase.disconnecting;

  bool get isOnline =>
      phase == SessionPhase.online ||
      phase == SessionPhase.keeping ||
      phase == SessionPhase.wifiWaiting;

  bool get keepRequested => keepRunning || phase == SessionPhase.wifiWaiting;

  SessionSnapshot copyWith({
    SessionPhase? phase,
    String? message,
    String? errorCode,
    String? errorText,
    String? ipv4,
    String? mac,
    bool? keepRunning,
    String? account,
  }) => SessionSnapshot(
    phase: phase ?? this.phase,
    message: message ?? this.message,
    errorCode: errorCode ?? this.errorCode,
    errorText: errorText ?? this.errorText,
    ipv4: ipv4 ?? this.ipv4,
    mac: mac ?? this.mac,
    keepRunning: keepRunning ?? this.keepRunning,
    account: account ?? this.account,
  );

  Map<String, Object?> toMap() => {
    'phase': phase.name,
    'message': message,
    'errorCode': errorCode,
    'errorText': errorText,
    'ipv4': ipv4,
    'mac': mac,
    'keepRunning': keepRunning,
    'account': account,
  };

  factory SessionSnapshot.fromMap(Map<Object?, Object?> map) => SessionSnapshot(
    phase: SessionPhase.fromName(map['phase'] as String?),
    message: map['message'] as String? ?? '',
    errorCode: map['errorCode'] as String? ?? '',
    errorText: map['errorText'] as String? ?? '',
    ipv4: map['ipv4'] as String? ?? '',
    mac: map['mac'] as String? ?? '',
    keepRunning: map['keepRunning'] as bool? ?? false,
    account: map['account'] as String? ?? '',
  );
}

class SessionWifiRoute {
  const SessionWifiRoute(this.handle, this.ipv4, this.gateway);

  final int handle;
  final String ipv4;
  final String gateway;

  bool sameLink(SessionWifiRoute other) =>
      ipv4 == other.ipv4 && gateway == other.gateway;

  bool sameRoute(SessionWifiRoute other) =>
      handle == other.handle && sameLink(other);

  Map<String, Object?> toMap() => {
    'handle': handle,
    'ipv4': ipv4,
    'gateway': gateway,
  };

  static SessionWifiRoute? fromMap(Object? value) {
    if (value is! Map) return null;
    return SessionWifiRoute(
      value['handle'] as int,
      value['ipv4'] as String,
      value['gateway'] as String,
    );
  }
}

class SessionParams {
  const SessionParams({
    required this.account,
    required this.password,
    required this.clientId,
    this.server = '',
    this.port = 0,
    this.mscgip = '',
    this.mode = 0,
    this.mac = '',
    this.keepInterval = 0,
    this.preTerm = true,
    this.wifiRoute,
    this.wifiSessionId = 0,
  });

  final String account;
  final String password;
  final String clientId;
  final String server;
  final int port;
  final String mscgip;
  final int mode;
  final String mac;
  final double keepInterval;
  final bool preTerm;
  final SessionWifiRoute? wifiRoute;
  final int wifiSessionId;

  Map<String, Object?> toMap() => {
    'account': account,
    'password': password,
    'clientId': clientId,
    'server': server,
    'port': port,
    'mscgip': mscgip,
    'mode': mode,
    'mac': mac,
    'keepInterval': keepInterval,
    'preTerm': preTerm,
    if (wifiRoute != null) 'wifiRoute': wifiRoute!.toMap(),
    if (wifiRoute != null) 'wifiSessionId': wifiSessionId,
  };

  factory SessionParams.fromMap(Map<Object?, Object?> map) => SessionParams(
    account: map['account'] as String? ?? '',
    password: map['password'] as String? ?? '',
    clientId: map['clientId'] as String? ?? '',
    server: map['server'] as String? ?? '',
    port: (map['port'] as num?)?.toInt() ?? 0,
    mscgip: map['mscgip'] as String? ?? '',
    mode: (map['mode'] as num?)?.toInt() ?? 0,
    mac: map['mac'] as String? ?? '',
    keepInterval: (map['keepInterval'] as num?)?.toDouble() ?? 0,
    preTerm: map['preTerm'] as bool? ?? true,
    wifiRoute: SessionWifiRoute.fromMap(map['wifiRoute']),
    wifiSessionId: map['wifiSessionId'] as int? ?? 0,
  );
}
