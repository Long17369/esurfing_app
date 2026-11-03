import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum LogLevel { debug, info, warn, error }

class LogEntry {
  LogEntry(this.time, this.level, this.message);

  final DateTime time;
  final LogLevel level;
  final String message;

  String get formatted =>
      '${time.toIso8601String()} [${level.name.toUpperCase()}] $message';
}

/// 最近日志（内存）+ 按大小轮转的文件日志。
class LogRepository extends ChangeNotifier {
  static const int _maxRecent = 500;
  static const int _maxFileBytes = 2 * 1024 * 1024;
  static const int _maxFiles = 5;

  final List<LogEntry> _recent = [];
  File? _file;
  Future<void> _writeChain = Future.value();

  List<LogEntry> get recent => List.unmodifiable(_recent.reversed);

  Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    final logDir = Directory('${dir.path}/logs');
    await logDir.create(recursive: true);
    _file = File('${logDir.path}/app.log');
    await _rotateIfNeeded();
  }

  void add(String message, {LogLevel level = LogLevel.info}) {
    final entry = LogEntry(DateTime.now(), level, message);
    _recent.add(entry);
    if (_recent.length > _maxRecent) {
      _recent.removeRange(0, _recent.length - _maxRecent);
    }
    notifyListeners();
    _writeChain = _writeChain
        .then((_) => _append(entry.formatted))
        .catchError((Object error) => debugPrint('日志写入失败：$error'));
  }

  Future<void> _append(String line) async {
    final file = _file;
    if (file == null) return;
    await file.writeAsString('$line\n', mode: FileMode.append, flush: false);
    if (await file.length() > _maxFileBytes) await _rotate();
  }

  Future<void> _rotateIfNeeded() async {
    final file = _file;
    if (file == null) return;
    if (await file.exists() && await file.length() > _maxFileBytes) {
      await _rotate();
    }
  }

  Future<void> _rotate() async {
    final file = _file;
    if (file == null) return;
    for (var i = _maxFiles - 1; i >= 1; i--) {
      final from = File('${file.path}.$i');
      if (await from.exists()) {
        await from.rename('${file.path}.${i + 1}');
      }
    }
    if (await file.exists()) await file.rename('${file.path}.1');
  }
}
