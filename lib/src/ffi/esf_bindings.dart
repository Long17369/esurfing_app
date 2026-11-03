import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'esf_types.dart';

/// 原生库加载与所有 `esf_*` 符号的绑定。
///
/// 加载顺序：
/// - Windows：exe 同目录的 `esurfing.dll`（Windows 会先搜应用目录）；
/// - Android：`libesurfing.so`（jniLibs 里的那一个）；
/// - macOS / iOS：本期不产出，保留分支给后续 Apple 分支；
/// - 其它（开发机单测）：`ESURFING_LIB` 或 `esurfing_c` 的构建产物。
class EsfBindings {
  EsfBindings._(this._lib);

  final DynamicLibrary _lib;

  static EsfBindings? _instance;

  static EsfBindings get instance {
    final existing = _instance;
    if (existing != null) return existing;
    final created = EsfBindings._(loadLibrary());
    _instance = created;
    return created;
  }

  static DynamicLibrary loadLibrary() {
    final override = Platform.environment['ESURFING_LIB'];
    if (override != null && override.isNotEmpty) {
      return DynamicLibrary.open(override);
    }

    if (Platform.isWindows) {
      return DynamicLibrary.open('esurfing.dll');
    }
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libesurfing.so');
    }
    if (Platform.isMacOS) {
      return _openBundledAppleLibrary('libesurfing.dylib');
    }
    if (Platform.isIOS) {
      // Apple 分支：静态链接后从进程里查找。本期不验证。
      return DynamicLibrary.process();
    }

    // Linux / 测试环境：优先用工作区里现成的构建产物。
    for (final candidate in const [
      'libesurfing.so',
      'libesurfing.so.1',
      'esurfing_c/build-linux/lib/libesurfing.so.1.0.1',
      'esurfing_c/build/lib/libesurfing.so',
    ]) {
      try {
        return DynamicLibrary.open(candidate);
      } on ArgumentError {
        continue;
      }
    }
    throw StateError('找不到原生库：请设置 ESURFING_LIB 或先构建 esurfing_c');
  }

  static DynamicLibrary _openBundledAppleLibrary(String name) {
    final exe = File(Platform.resolvedExecutable);
    final candidates = [
      exe.parent.uri.resolve('Frameworks/$name').toFilePath(),
      exe.parent.uri.resolve(name).toFilePath(),
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) {
        return DynamicLibrary.open(path);
      }
    }
    return DynamicLibrary.open(name);
  }

  String get version => _esfVersion().toDartString();

  late final EsfCreateDart _esfCreate = _lib
      .lookupFunction<EsfCreateNative, EsfCreateDart>('esf_create');
  late final EsfDestroyDart _esfDestroy = _lib
      .lookupFunction<EsfDestroyNative, EsfDestroyDart>('esf_destroy');
  late final EsfSetCallbacksDart _esfSetCallbacks = _lib
      .lookupFunction<EsfSetCallbacksNative, EsfSetCallbacksDart>(
        'esf_set_callbacks',
      );
  late final EsfModeOfDart _esfModeOf = _lib
      .lookupFunction<EsfModeOfNative, EsfModeOfDart>('esf_mode_of');
  late final EsfSetModeDart _esfSetMode = _lib
      .lookupFunction<EsfSetModeNative, EsfSetModeDart>('esf_set_mode');
  late final EsfSetAccountDart _esfSetAccount = _lib
      .lookupFunction<EsfSetAccountNative, EsfSetAccountDart>(
        'esf_set_account',
      );
  late final EsfSetServerDart _esfSetServer = _lib
      .lookupFunction<EsfSetServerNative, EsfSetServerDart>('esf_set_server');
  late final EsfSetStringDart _esfSetMscgip = _lib
      .lookupFunction<EsfSetStringNative, EsfSetStringDart>('esf_set_mscgip');
  late final EsfSetStringDart _esfSetClientId = _lib
      .lookupFunction<EsfSetStringNative, EsfSetStringDart>(
        'esf_set_client_id',
      );
  late final EsfSetStringDart _esfSetMac = _lib
      .lookupFunction<EsfSetStringNative, EsfSetStringDart>('esf_set_mac');
  late final EsfSetServerDart _esfSetFallbackServer = _lib
      .lookupFunction<EsfSetServerNative, EsfSetServerDart>(
        'esf_set_fallback_server',
      );
  late final EsfSetAllowDiscoveryDart _esfSetAllowDiscovery = _lib
      .lookupFunction<EsfSetAllowDiscoveryNative, EsfSetAllowDiscoveryDart>(
        'esf_set_allow_discovery',
      );
  late final EsfQueryDart _esfQuery = _lib
      .lookupFunction<EsfQueryNative, EsfQueryDart>('esf_query');
  late final EsfOptionsInitDart _esfOptionsInit = _lib
      .lookupFunction<EsfOptionsInitNative, EsfOptionsInitDart>(
        'esf_options_init',
      );
  late final EsfLoginDart _esfLogin = _lib
      .lookupFunction<EsfLoginNative, EsfLoginDart>('esf_login');
  late final EsfLoginDart _esfLogout = _lib
      .lookupFunction<EsfLoginNative, EsfLoginDart>('esf_logout');
  late final EsfKeepStartDart _esfKeepStart = _lib
      .lookupFunction<EsfKeepStartNative, EsfKeepStartDart>('esf_keep_start');
  late final EsfKeepStopDart _esfKeepStop = _lib
      .lookupFunction<EsfKeepStopNative, EsfKeepStopDart>('esf_keep_stop');
  late final EsfKeepRunningDart _esfKeepRunning = _lib
      .lookupFunction<EsfKeepRunningNative, EsfKeepRunningDart>(
        'esf_keep_running',
      );
  late final EsfErrorTextDart _esfErrorText = _lib
      .lookupFunction<EsfErrorTextNative, EsfErrorTextDart>('esf_error_text');
  late final EsfFreeDart _esfFree = _lib
      .lookupFunction<EsfFreeNative, EsfFreeDart>('esf_free');
  late final EsfVersionDart _esfVersion = _lib
      .lookupFunction<EsfVersionNative, EsfVersionDart>('esf_version');
  late final EsfListAdaptersDart _esfListAdapters = _lib
      .lookupFunction<EsfListAdaptersNative, EsfListAdaptersDart>(
        'esf_list_adapters',
      );

  Pointer<EsfClient> create(int mode) => _esfCreate(mode);
  void destroy(Pointer<EsfClient> client) => _esfDestroy(client);
  void setCallbacks(Pointer<EsfClient> client, Pointer<EsfCallbacks> cb) =>
      _esfSetCallbacks(client, cb);
  int modeOf(Pointer<EsfClient> client) => _esfModeOf(client);
  int setMode(Pointer<EsfClient> client, int mode) => _esfSetMode(client, mode);
  int setAccount(Pointer<EsfClient> client, String account, String password) {
    final accountPtr = account.toNativeUtf8();
    final passwordPtr = password.toNativeUtf8();
    try {
      return _esfSetAccount(client, accountPtr, passwordPtr);
    } finally {
      malloc.free(accountPtr);
      malloc.free(passwordPtr);
    }
  }

  int setServer(Pointer<EsfClient> client, String? server, int port) {
    final ptr = server == null || server.isEmpty
        ? nullptr.cast<Utf8>()
        : server.toNativeUtf8();
    try {
      return _esfSetServer(client, ptr, port);
    } finally {
      if (ptr.address != 0) malloc.free(ptr);
    }
  }

  int setMscgip(Pointer<EsfClient> client, String? value) =>
      _setOptionalString(client, value, _esfSetMscgip);
  int setClientId(Pointer<EsfClient> client, String? value) =>
      _setOptionalString(client, value, _esfSetClientId);
  int setMac(Pointer<EsfClient> client, String? value) =>
      _setOptionalString(client, value, _esfSetMac);
  int setFallbackServer(Pointer<EsfClient> client, String? server, int port) {
    final ptr = server == null || server.isEmpty
        ? nullptr.cast<Utf8>()
        : server.toNativeUtf8();
    try {
      return _esfSetFallbackServer(client, ptr, port);
    } finally {
      if (ptr.address != 0) malloc.free(ptr);
    }
  }

  int _setOptionalString(
    Pointer<EsfClient> client,
    String? value,
    EsfSetStringDart fn,
  ) {
    final ptr = value == null || value.isEmpty
        ? nullptr.cast<Utf8>()
        : value.toNativeUtf8();
    try {
      return fn(client, ptr);
    } finally {
      if (ptr.address != 0) malloc.free(ptr);
    }
  }

  void setAllowDiscovery(Pointer<EsfClient> client, bool allow) =>
      _esfSetAllowDiscovery(client, allow ? 1 : 0);

  void optionsInit(Pointer<EsfOptions> options) => _esfOptionsInit(options);

  int login(
    Pointer<EsfClient> client,
    Pointer<EsfOptions> options,
    Pointer<Pointer<Utf8>> outCode,
    Pointer<Pointer<Utf8>> outMessage,
  ) => _esfLogin(client, options, outCode, outMessage);
  int logout(
    Pointer<EsfClient> client,
    Pointer<EsfOptions> options,
    Pointer<Pointer<Utf8>> outCode,
    Pointer<Pointer<Utf8>> outMessage,
  ) => _esfLogout(client, options, outCode, outMessage);
  int keepStart(Pointer<EsfClient> client, Pointer<EsfOptions> options) =>
      _esfKeepStart(client, options);
  int keepStop(Pointer<EsfClient> client) => _esfKeepStop(client);
  bool keepRunning(Pointer<EsfClient> client) => _esfKeepRunning(client) != 0;
  int query(
    Pointer<EsfClient> client,
    Pointer<Pointer<Utf8>> outIpv4,
    Pointer<Pointer<Utf8>> outMac,
  ) => _esfQuery(client, outIpv4, outMac);
  int listAdapters(Pointer<Pointer<Utf8>> outText) => _esfListAdapters(outText);

  String errorText(String? code) {
    final input = code == null || code.isEmpty
        ? nullptr.cast<Utf8>()
        : code.toNativeUtf8();
    final ptr = _esfErrorText(input);
    try {
      return ptr == nullptr ? '' : ptr.toDartString();
    } finally {
      if (ptr != nullptr) _esfFree(ptr);
      if (input.address != 0) malloc.free(input);
    }
  }

  String takeString(Pointer<Pointer<Utf8>> out) {
    final ptr = out.value;
    if (ptr == nullptr) return '';
    final text = ptr.toDartString();
    _esfFree(ptr);
    out.value = nullptr;
    return text;
  }

  void free(Pointer<Utf8> ptr) {
    if (ptr != nullptr) _esfFree(ptr);
  }
}
