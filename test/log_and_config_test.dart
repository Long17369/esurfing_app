import 'package:esurfing_app/src/data/config_repository.dart';
import 'package:esurfing_app/src/data/log_repository.dart';
import 'package:esurfing_app/src/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('日志级别过滤', () {
    test('默认只看 INFO 及以上', () {
      final logs = LogRepository();
      logs.add('细节', level: LogLevel.debug);
      logs.add('正常', level: LogLevel.info);
      logs.add('警告', level: LogLevel.warn);
      logs.add('错误', level: LogLevel.error);

      expect(logs.minLevel, LogLevel.info);
      // visible 最新在前，且不含 debug。
      expect(logs.visible.map((e) => e.message), ['错误', '警告', '正常']);
      // recent 保留全部级别，导出不受展示阈值影响。
      expect(logs.recent.length, 4);
    });

    test('切到 DEBUG 后能看到全部，切到 ERROR 后只剩错误', () {
      final logs = LogRepository()
        ..add('细节', level: LogLevel.debug)
        ..add('错误', level: LogLevel.error);

      logs.minLevel = LogLevel.debug;
      expect(logs.visible.length, 2);

      logs.minLevel = LogLevel.error;
      expect(logs.visible.map((e) => e.message), ['错误']);
    });

    test('非法级别名回落为 INFO', () {
      expect(LogLevelX.parse('verbose'), LogLevel.info);
      expect(LogLevelX.parse(null), LogLevel.info);
      expect(LogLevelX.parse('warn'), LogLevel.warn);
    });
  });

  group('配置持久化', () {
    test('ui.logLevel 默认 info 且能往返', () {
      expect(const UiConfig().logLevel, 'info');
      final json = const UiConfig().copyWith(logLevel: 'debug').toJson();
      expect(json['logLevel'], 'debug');
      expect(UiConfig.fromJson(json).logLevel, 'debug');
      // 老配置文件没有该字段时回落 info。
      expect(UiConfig.fromJson(const {}).logLevel, 'info');
    });
  });

  group('保活间隔展示', () {
    test('0 表示跟随核心默认值', () {
      expect(AppController.keepIntervalLabel(0), contains('默认'));
      expect(AppController.keepIntervalLabel(15), '15 秒');
      expect(AppController.keepIntervalLabel(2.5), '2.5 秒');
    });
  });
}
