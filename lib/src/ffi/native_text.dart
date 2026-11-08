import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// 读取原生侧的 C 字符串（UTF-8、以 NUL 结尾），并对非法字节容错。
///
/// 为什么不能直接用 `Pointer<Utf8>.toDartString()`：
/// `esurfing_c` 约定 `on_event` 的 text **仅在回调期间有效**，而 Dart 的
/// `NativeCallable.listener` 是异步投递 —— 等 Dart 回调真正执行时，原生侧的
/// 临时缓冲可能已经释放或被复用，严格 UTF-8 解码就会抛
/// `FormatException: Unexpected extension byte`。这个异常没人接，会打到宿主
/// isolate 的 onError 端口，把当时所有在途命令都判为失败。
///
/// 因此这里统一做「限长扫描 + allowMalformed 解码」：宁可显示乱码，也不能让
/// 一条日志事件把会话宿主搞挂。
String decodeNativeUtf8(Pointer<Utf8> text, {int maxBytes = 4096}) {
  if (text == nullptr) return '';
  final units = text.cast<Uint8>();
  var len = 0;
  while (len < maxBytes && units[len] != 0) {
    len++;
  }
  return utf8.decode(units.asTypedList(len), allowMalformed: true);
}
