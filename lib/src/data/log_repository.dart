import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum LogLevel { debug, info, warn, error }

extension LogLevelX on LogLevel {
  String get label => switch (this) {
    LogLevel.debug => 'DEBUG',
    LogLevel.info => 'INFO',
    LogLevel.warn => 'WARN',
    LogLevel.error => 'ERROR',
  };

  static LogLevel parse(String? value, {LogLevel fallback = LogLevel.info}) {
    for (final level in LogLevel.values) {
      if (level.name == value) return level;
    }
    return fallback;
  }
}

class LogEntry {
  LogEntry(this.time, this.level, this.message);

  final DateTime time;
  final LogLevel level;
  final String message;

  String get formatted =>
      '${time.toIso8601String()} [${level.name.toUpperCase()}] $message';
}

/// 最近日志（内存）+ 按大小轮转的文件日志。
///
/// 内存与文件都保留所有级别，级别阈值只影响 UI 展示（默认 INFO），
/// 导出时给出完整内容。
class LogRepository extends ChangeNotifier {
  static const int _maxRecent = 2000;
  static const int _maxFileBytes = 2 * 1024 * 1024;
  static const int _maxFiles = 5;

  final List<LogEntry> _recent = [];
  Directory? _logDir;
  File? _file;
  Future<void> _writeChain = Future.value();
  LogLevel _minLevel = LogLevel.info;

  /// 展示用的级别下限。低于它的条目不会出现在 [visible] 里。
  LogLevel get minLevel => _minLevel;

  set minLevel(LogLevel value) {
    if (_minLevel == value) return;
    _minLevel = value;
    notifyListeners();
  }

  /// 全部条目（最新在前）。
  List<LogEntry> get recent => List.unmodifiable(_recent.reversed);

  /// 按 [minLevel] 过滤后的条目（最新在前），供日志页展示。
  List<LogEntry> get visible => List.unmodifiable(
    _recent.reversed.where((e) => e.level.index >= _minLevel.index),
  );

  String? get logFilePath => _file?.path;

  Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    final logDir = Directory('${dir.path}/logs');
    await logDir.create(recursive: true);
    _logDir = logDir;
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
    // 轮转后最老的一份可能超出保留数量，直接删掉。
    final oldest = File('${file.path}.${_maxFiles + 1}');
    if (await oldest.exists()) await oldest.delete();
  }

  /// 合并所有轮转文件 + 当前文件（旧 → 新），返回完整历史日志文本。
  Future<String> collectAll() async {
    await _writeChain;
    final file = _file;
    if (file == null) return '';
    final buffer = StringBuffer();
    for (var i = _maxFiles; i >= 1; i--) {
      final old = File('${file.path}.$i');
      if (await old.exists()) buffer.write(await old.readAsString());
    }
    if (await file.exists()) buffer.write(await file.readAsString());
    if (buffer.isEmpty) {
      // 还没落盘时至少给出内存里的内容。
      buffer.write(_recent.map((e) => e.formatted).join('\n'));
    }
    return buffer.toString();
  }

  /// 把完整历史日志写到用户能找到的目录，返回目标文件。
  ///
  /// 桌面端优先「下载」目录；Android 用 App 的外部私有目录
  /// （`Android/data/<包名>/files/logs`），无需额外存储权限即可访问。
  Future<File> exportToFile() async {
    await _writeChain;
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-')
        .split('+')
        .first;
    final dir = await _exportDirectory();
    await dir.create(recursive: true);
    final target = File('${dir.path}${Platform.pathSeparator}'
        'esurfing-log-$stamp.log');
    await target.writeAsString(await collectAll(), flush: true);
    return target;
  }

  Future<Directory> _exportDirectory() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final external = await getExternalStorageDirectory();
      if (external != null) return Directory('${external.path}/logs');
    } else {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) return Directory('${downloads.path}/esurfing');
    }
    final fallback = _logDir ?? await getApplicationSupportDirectory();
    return Directory('${fallback.path}/exports');
  }
}
