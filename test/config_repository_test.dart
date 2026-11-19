import 'dart:io';

import 'package:esurfing_app/src/data/config_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = Directory(
      '.dart_tool/config-repository-${DateTime.now().microsecondsSinceEpoch}',
    );
    await directory.create(recursive: true);
  });
  tearDown(() async => directory.delete(recursive: true));

  test('JSON结构或字段类型损坏均备份并恢复默认值', () async {
    for (final content in [
      '[]',
      '{"accounts":7}',
      '{"ui":{"autoStart":"yes"}}',
    ]) {
      await File('${directory.path}/config.json').writeAsString(content);
      final repository = await ConfigRepository.open(directory: directory);
      expect(repository.value.accounts, isEmpty);
      expect(
        await File('${directory.path}/config.json.broken').readAsString(),
        content,
      );
    }
  });

  test('并发保存串行执行，最后一次配置完整落盘', () async {
    final repository = await ConfigRepository.open(directory: directory);
    await Future.wait([
      for (var i = 0; i < 10; i++)
        repository.save(AppConfig(clientId: 'client-$i')),
    ]);
    await repository.reload();
    expect(repository.value.clientId, 'client-9');
  });

  test('保存失败不更新缓存，后续保存可恢复', () async {
    final repository = await ConfigRepository.open(directory: directory);
    await repository.save(const AppConfig(clientId: 'before'));
    final blocker = Directory('${directory.path}/config.json.tmp');
    await blocker.create();
    await expectLater(
      repository.save(const AppConfig(clientId: 'failed')),
      throwsA(isA<FileSystemException>()),
    );
    expect(repository.value.clientId, 'before');
    await blocker.delete();
    await repository.save(const AppConfig(clientId: 'recovered'));
    await repository.reload();
    expect(repository.value.clientId, 'recovered');
  });
}
