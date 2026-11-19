import 'dart:convert';
import 'dart:ffi';

import 'package:esurfing_app/src/ffi/native_text.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

Pointer<Utf8> _alloc(List<int> bytes) {
  final ptr = malloc<Uint8>(bytes.length + 1);
  final view = ptr.asTypedList(bytes.length + 1);
  view.setRange(0, bytes.length, bytes);
  view[bytes.length] = 0;
  return ptr.cast<Utf8>();
}

void main() {
  test('decodeNativeUtf8 解出正常 UTF-8', () {
    final ptr = _alloc(utf8.encode('保活中：已连接'));
    try {
      expect(decodeNativeUtf8(ptr), '保活中：已连接');
    } finally {
      malloc.free(ptr);
    }
  });

  test('decodeNativeUtf8 对有效缓冲中的非法字节容错', () {
    // 0xE4 后面跟着 ASCII 0x42，构成不完整的 UTF-8 序列。
    final ptr = _alloc(const [0x41, 0x42, 0xE4, 0x42, 0x43]);
    try {
      final text = decodeNativeUtf8(ptr);
      expect(text.startsWith('AB'), isTrue);
      expect(text.contains('\uFFFD'), isTrue);
    } finally {
      malloc.free(ptr);
    }
  });

  test('decodeNativeUtf8 对空指针返回空串', () {
    expect(decodeNativeUtf8(nullptr), '');
  });
}
