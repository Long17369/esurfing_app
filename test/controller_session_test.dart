import 'dart:async';
import 'dart:io';

import 'package:esurfing_app/src/data/config_repository.dart';
import 'package:esurfing_app/src/data/credential_store.dart';
import 'package:esurfing_app/src/data/log_repository.dart';
import 'package:esurfing_app/src/state/app_controller.dart';
import 'package:esurfing_app/src/state/host_client.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryLogs extends LogRepository {
  @override
  Future<void> init() async {}
}

class FakeHost extends HostClient {
  FakeHost({this.compatibilityError});
  final String? compatibilityError;
  int connects = 0;
  int keepStarts = 0;
  Map<String, Object?> connectResult = {};
  Map<String, Object?> disconnectResult = {'ok': true};

  @override
  Future<void> start() async {}

  @override
  Future<Map<String, Object?>> send(
    String type, [
    Map<String, Object?> payload = const {},
  ]) async {
    if (type == 'version') {
      return {'version': '1.1.0', 'compatibilityError': compatibilityError};
    }
    if (type == 'connect') {
      connects++;
      return connectResult;
    }
    if (type == 'startKeep') keepStarts++;
    if (type == 'disconnect') return disconnectResult;
    return {};
  }
}

class FakeCredentials extends CredentialStore {
  int reads = 0;
  final deleted = <String>[];
  Future<String?> Function()? onRead;

  @override
  Future<String?> read(String account) async {
    reads++;
    return onRead == null ? 'offline-only' : await onRead!();
  }

  @override
  Future<void> delete(String account) async => deleted.add(account);

  @override
  Future<void> write(String account, String password) async {}
}

class DelayedShutdownHost extends FakeHost {
  final stopped = Completer<void>();
  int disposals = 0;

  @override
  Future<void> dispose() async {
    disposals++;
    await stopped.future;
    await super.dispose();
  }
}

void main() {
  late Directory directory;
  late ConfigRepository repository;

  setUp(() async {
    directory = Directory(
      '.dart_tool/controller-session-${DateTime.now().microsecondsSinceEpoch}',
    );
    repository = await ConfigRepository.open(directory: directory);
    await repository.save(
      const AppConfig(
        clientId: 'test-client',
        activeAccountId: 'a',
        accounts: [
          AccountProfile(id: 'a', account: 'offline-only', autoConnect: true),
        ],
      ),
    );
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('桌面退出等待宿主停止，重复 shutdown 不重复清理', () async {
    final host = DelayedShutdownHost();
    final controller = AppController(
      configRepository: repository,
      credentials: FakeCredentials(),
      logs: MemoryLogs(),
      host: host,
    );
    final first = controller.shutdown();
    expect(identical(first, controller.shutdown()), isTrue);
    var completed = false;
    unawaited(first.then((_) => completed = true));
    await Future<void>.delayed(Duration.zero);
    expect(host.disposals, 1);
    expect(completed, isFalse);
    host.stopped.complete();
    await first;
    expect(completed, isTrue);
    controller.dispose();
    expect(host.disposals, 1);
  });

  test('旧库阻挡启动自动、手动、Wi-Fi入口，不读取凭据或创建会话', () async {
    final host = FakeHost(compatibilityError: '请升级原生库');
    final credentials = FakeCredentials();
    final controller = AppController(
      configRepository: repository,
      credentials: credentials,
      logs: MemoryLogs(),
      host: host,
    );
    await controller.initialize();
    await controller.autoConnectIfNeeded();
    await controller.login();
    await controller.loginWithWifi();
    expect(host.connects, 0);
    expect(credentials.reads, 0);
    expect(controller.lastError, contains('升级'));
    expect(controller.snapshot.isBusy, false);
    controller.dispose();
  });

  test('读取凭据期间账号锁定，重复登录和账号切换不可绕过', () async {
    await repository.save(
      repository.value.copyWith(
        activeAccountId: '',
        accounts: [
          const AccountProfile(id: 'a', account: 'offline-only'),
          const AccountProfile(id: 'b', account: 'other-offline'),
        ],
      ),
    );
    final pending = Completer<String?>();
    final credentials = FakeCredentials()..onRead = () => pending.future;
    final host = FakeHost();
    final controller = AppController(
      configRepository: repository,
      credentials: credentials,
      logs: MemoryLogs(),
      host: host,
    );
    await controller.initialize();
    final loggingIn = controller.login();
    expect(controller.isAccountLocked('a'), true);
    await controller.setActiveAccount('b');
    await controller.saveAccount(account: 'new-offline', password: 'offline');
    await controller.login();
    expect(controller.activeAccount?.id, 'a');
    expect(credentials.reads, 1);
    pending.completeError(StateError('系统凭据库不可用'));
    await loggingIn;
    expect(controller.snapshot.isBusy, false);
    expect(controller.isAccountLocked('a'), false);
    expect(controller.lastError, contains('凭据库'));
    expect(host.connects, 0);
    controller.dispose();
  });

  test('删除重复账号配置不删除另一份配置仍依赖的密码', () async {
    await repository.save(
      repository.value.copyWith(
        accounts: [
          const AccountProfile(id: 'a', account: 'offline-only'),
          const AccountProfile(id: 'b', account: 'offline-only'),
        ],
      ),
    );
    final credentials = FakeCredentials();
    final controller = AppController(
      configRepository: repository,
      credentials: credentials,
      logs: MemoryLogs(),
      host: FakeHost(),
    );
    await controller.initialize();
    await controller.deleteAccount('a');
    expect(credentials.deleted, isEmpty);
    await controller.deleteAccount('b');
    expect(credentials.deleted, ['offline-only']);
    controller.dispose();
  });

  test('持久化失败不发布未保存的 UI 设置', () async {
    final controller = AppController(
      configRepository: repository,
      credentials: FakeCredentials(),
      logs: MemoryLogs(),
      host: FakeHost(compatibilityError: '请升级原生库'),
    );
    await controller.initialize();
    await Directory('${directory.path}/config.json.tmp').create();
    await expectLater(
      controller.updateUi(controller.config.ui.copyWith(logLevel: 'debug')),
      throwsA(isA<FileSystemException>()),
    );
    expect(controller.config.ui.logLevel, 'info');
    expect(controller.logs.minLevel, LogLevel.info);
    controller.dispose();
  });

  test('销毁 controller 时进行中的凭据读取不会再创建会话或通知已销毁 UI', () async {
    await repository.save(
      repository.value.copyWith(
        accounts: [const AccountProfile(id: 'a', account: 'offline-only')],
      ),
    );
    final pending = Completer<String?>();
    final credentials = FakeCredentials()..onRead = () => pending.future;
    final host = FakeHost();
    final controller = AppController(
      configRepository: repository,
      credentials: credentials,
      logs: MemoryLogs(),
      host: host,
    );
    await controller.initialize();
    final loggingIn = controller.login();
    controller.dispose();
    pending.complete('offline-only');
    await loggingIn;
    expect(host.connects, 0);
  });

  test('服务器注销返回失败不会显示为成功', () async {
    final host = FakeHost(compatibilityError: '请升级原生库')
      ..disconnectResult = {'ok': false, 'errorMessage': '离线模拟失败'};
    final controller = AppController(
      configRepository: repository,
      credentials: FakeCredentials(),
      logs: MemoryLogs(),
      host: host,
    );
    await controller.initialize();
    await controller.logout();
    expect(controller.lastError, contains('离线模拟失败'));
    expect(
      controller.logs.recent.any((entry) => entry.message == '已断开连接'),
      false,
    );
    controller.dispose();
  });

  test('登录后的 MAC 持久化失败不阻止启动保活', () async {
    await repository.save(
      repository.value.copyWith(
        accounts: [const AccountProfile(id: 'a', account: 'offline-only')],
      ),
    );
    final host = FakeHost()
      ..connectResult = {'ok': true, 'mac': '02:00:00:00:00:01'};
    final controller = AppController(
      configRepository: repository,
      credentials: FakeCredentials(),
      logs: MemoryLogs(),
      host: host,
    );
    await controller.initialize();
    await Directory('${directory.path}/config.json.tmp').create();
    await controller.login();
    expect(host.keepStarts, 1);
    expect(controller.config.savedMac, '');
    expect(controller.lastError, '');
    controller.dispose();
  });
}
