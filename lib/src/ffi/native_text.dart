import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// 读取原生侧的 C 字符串（UTF-8、以 NUL 结尾），并对非法字节容错。
///
/// 调用者必须保证指针在整个读取期间有效。限长及容错只处理文本内容，
/// 不能让已释放的指针变得安全。
String decodeNativeUtf8(Pointer<Utf8> text, {int maxBytes = 4096}) {
  if (text == nullptr) return '';
  final units = text.cast<Uint8>();
  var len = 0;
  while (len < maxBytes && units[len] != 0) {
    len++;
  }
  return utf8.decode(units.asTypedList(len), allowMalformed: true);
}
