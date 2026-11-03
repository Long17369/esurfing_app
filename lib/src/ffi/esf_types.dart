import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// `esf_status` 取值。失败码与核心层一一对应。
abstract final class EsfStatus {
  static const int ok = 0;
  static const int auth = 1;
  static const int prepare = 2;
  static const int session = 3;
  static const int net = 4;
  static const int unexpected = 5;
  static const int invalidArg = 6;
  static const int noMemory = 7;
  static const int cancelled = 8;

  static String describe(int rc) => switch (rc) {
    ok => '成功',
    auth => '认证失败',
    prepare => '准备阶段失败',
    session => '会话同步失败',
    net => '外网仍未放行',
    unexpected => '未预料的错误',
    invalidArg => '参数不合法',
    noMemory => '内存不足',
    cancelled => '已取消',
    _ => '未知错误($rc)',
  };
}

abstract final class EsfMode {
  static const int auto = 0;
  static const int windows = 1;
  static const int android = 2;

  static String label(int mode) => switch (mode) {
    auto => '自动',
    windows => 'Windows 模式',
    android => 'Android 模式',
    _ => '未知模式',
  };
}

abstract final class EsfEventKind {
  static const int log = 0;
  static const int step = 1;
  static const int status = 2;
  static const int error = 3;
  static const int banner = 4;
  static const int block = 5;

  static String name(int kind) => switch (kind) {
    log => 'LOG',
    step => 'STEP',
    status => 'STATUS',
    error => 'ERROR',
    banner => 'BANNER',
    block => 'BLOCK',
    _ => 'EVENT',
  };
}

final class EsfClient extends Opaque {}

final class EsfCallbacks extends Struct {
  external Pointer<Void> user;
  external Pointer<NativeFunction<EsfEventCbNative>> onEvent;
  external Pointer<NativeFunction<EsfAskCbNative>> onAsk;
  external Pointer<NativeFunction<EsfCancelCbNative>> onCancel;
}

/// 与 `esf_options` 字段一一对应。Dart FFI 会按 C ABI 自动补齐对齐。
final class EsfOptions extends Struct {
  @Int32()
  external int preTerm;

  @Int32()
  external int keep;

  @Double()
  external double keepInterval;

  @Double()
  external double keepRetry;

  @Double()
  external double keepRetryLong;

  @Int32()
  external int keepRetryTries;

  @Int32()
  external int keepReauthAfter;
}

typedef EsfEventCbNative = Void Function(
  Pointer<Void> user,
  Int32 event,
  Pointer<Utf8> text,
);
typedef EsfEventCbDart = void Function(
  Pointer<Void> user,
  int event,
  Pointer<Utf8> text,
);

typedef EsfAskCbNative = Pointer<Utf8> Function(
  Pointer<Void> user,
  Pointer<Utf8> prompt,
  Int32 isPassword,
);
typedef EsfAskCbDart = Pointer<Utf8> Function(
  Pointer<Void> user,
  Pointer<Utf8> prompt,
  int isPassword,
);

typedef EsfCancelCbNative = Int32 Function(Pointer<Void> user);
typedef EsfCancelCbDart = int Function(Pointer<Void> user);

typedef EsfCreateNative = Pointer<EsfClient> Function(Int32 mode);
typedef EsfCreateDart = Pointer<EsfClient> Function(int mode);

typedef EsfDestroyNative = Void Function(Pointer<EsfClient> client);
typedef EsfDestroyDart = void Function(Pointer<EsfClient> client);

typedef EsfSetCallbacksNative = Void Function(
  Pointer<EsfClient> client,
  Pointer<EsfCallbacks> callbacks,
);
typedef EsfSetCallbacksDart = void Function(
  Pointer<EsfClient> client,
  Pointer<EsfCallbacks> callbacks,
);

typedef EsfModeOfNative = Int32 Function(Pointer<EsfClient> client);
typedef EsfModeOfDart = int Function(Pointer<EsfClient> client);

typedef EsfSetModeNative = Int32 Function(
  Pointer<EsfClient> client,
  Int32 mode,
);
typedef EsfSetModeDart = int Function(Pointer<EsfClient> client, int mode);

typedef EsfSetAccountNative = Int32 Function(
  Pointer<EsfClient> client,
  Pointer<Utf8> account,
  Pointer<Utf8> password,
);
typedef EsfSetAccountDart = int Function(
  Pointer<EsfClient> client,
  Pointer<Utf8> account,
  Pointer<Utf8> password,
);

typedef EsfSetServerNative = Int32 Function(
  Pointer<EsfClient> client,
  Pointer<Utf8> server,
  Int32 port,
);
typedef EsfSetServerDart = int Function(
  Pointer<EsfClient> client,
  Pointer<Utf8> server,
  int port,
);

typedef EsfSetStringNative = Int32 Function(
  Pointer<EsfClient> client,
  Pointer<Utf8> value,
);
typedef EsfSetStringDart = int Function(
  Pointer<EsfClient> client,
  Pointer<Utf8> value,
);

typedef EsfSetAllowDiscoveryNative = Void Function(
  Pointer<EsfClient> client,
  Int32 allow,
);
typedef EsfSetAllowDiscoveryDart = void Function(
  Pointer<EsfClient> client,
  int allow,
);

typedef EsfQueryNative = Int32 Function(
  Pointer<EsfClient> client,
  Pointer<Pointer<Utf8>> outIpv4,
  Pointer<Pointer<Utf8>> outMac,
);
typedef EsfQueryDart = int Function(
  Pointer<EsfClient> client,
  Pointer<Pointer<Utf8>> outIpv4,
  Pointer<Pointer<Utf8>> outMac,
);

typedef EsfOptionsInitNative = Void Function(Pointer<EsfOptions> options);
typedef EsfOptionsInitDart = void Function(Pointer<EsfOptions> options);

typedef EsfLoginNative = Int32 Function(
  Pointer<EsfClient> client,
  Pointer<EsfOptions> options,
  Pointer<Pointer<Utf8>> outErrorCode,
  Pointer<Pointer<Utf8>> outErrorMessage,
);
typedef EsfLoginDart = int Function(
  Pointer<EsfClient> client,
  Pointer<EsfOptions> options,
  Pointer<Pointer<Utf8>> outErrorCode,
  Pointer<Pointer<Utf8>> outErrorMessage,
);

typedef EsfKeepStartNative = Int32 Function(
  Pointer<EsfClient> client,
  Pointer<EsfOptions> options,
);
typedef EsfKeepStartDart = int Function(
  Pointer<EsfClient> client,
  Pointer<EsfOptions> options,
);

typedef EsfKeepStopNative = Int32 Function(Pointer<EsfClient> client);
typedef EsfKeepStopDart = int Function(Pointer<EsfClient> client);

typedef EsfKeepRunningNative = Int32 Function(Pointer<EsfClient> client);
typedef EsfKeepRunningDart = int Function(Pointer<EsfClient> client);

typedef EsfErrorTextNative = Pointer<Utf8> Function(Pointer<Utf8> errorCode);
typedef EsfErrorTextDart = Pointer<Utf8> Function(Pointer<Utf8> errorCode);

typedef EsfFreeNative = Void Function(Pointer<Utf8> text);
typedef EsfFreeDart = void Function(Pointer<Utf8> text);

typedef EsfVersionNative = Pointer<Utf8> Function();
typedef EsfVersionDart = Pointer<Utf8> Function();

typedef EsfListAdaptersNative = Int32 Function(Pointer<Pointer<Utf8>> outText);
typedef EsfListAdaptersDart = int Function(Pointer<Pointer<Utf8>> outText);
