import 'dart:async';
import 'dart:io';

import 'package:esurfing_app/src/data/config_repository.dart';
import 'package:esurfing_app/src/data/credential_store.dart';
import 'package:esurfing_app/src/data/log_repository.dart';
import 'package:esurfing_app/src/ffi/esf_models.dart';
import 'package:esurfing_app/src/platform/wifi_shell.dart';
import 'package:esurfing_app/src/state/app_controller.dart';
import 'package:esurfing_app/src/state/host_client.dart';
import 'package:flutter/services.dart';
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
  bool reportOnline = false;
  Map<String, Object?> connectResult = {};
  Map<String, Object?> disconnectResult = {'ok': true};
  Future<Map<String, Object?>> Function()? onDisconnect;
  final sessionStates = StreamController<SessionSnapshot>.broadcast(sync: true);

  @override
  Stream<SessionSnapshot> get states => sessionStates.stream;

  @override
  Future<void> start() async {}

  @override
  Future<Map<String, Object?>> send(
    String type, [
    Map<String, Object?> payload = const {},
  ]) async {
    if (type == 'version') {
      return {
        'version': '1.1.0',
        'wifiRecovery': true,
        'compatibilityError': compatibilityError,
      };
    }
    if (type == 'connect') {
      connects++;
      if (reportOnline) {
        sessionStates.add(const SessionSnapshot(phase: SessionPhase.online));
      }
      return connectResult;
    }
    if (type == 'startKeep') keepStarts++;
    if (type == 'disconnect') {
      final result = onDisconnect == null
          ? disconnectResult
          : await onDisconnect!();
      sessionStates.add(const SessionSnapshot());
      return result;
    }
    return {};
  }

  @override
  Future<void> dispose() async {
    await sessionStates.close();
    await super.dispose();
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
  TestWidgetsFlutterBinding.ensureInitialized();
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

  test('退出只暂停原 Wi-Fi 链路，注销完成后新链路自动登录一次', () async {
    const channel = MethodChannel('esurfing/android');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final lateProbe = Completer<bool>();
    final probes = <int>[];
    final reports = <int>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      final handle = (call.arguments as Map<Object?, Object?>)['handle'] as int;
      switch (call.method) {
        case 'probeWifiInternet':
          probes.add(handle);
          if (handle == 1) return lateProbe.future;
          return handle == 2;
        case 'requestWifiRevalidation':
          reports.add(handle);
          return true;
        default:
          throw MissingPluginException();
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await repository.save(
      const AppConfig(
        clientId: 'test-client',
        activeAccountId: 'a',
        accounts: [
          AccountProfile(
            id: 'a',
            account: 'offline-only',
            wifiSsid: 'Campus',
            wifiAutoLogin: true,
            keepEnabled: false,
          ),
        ],
      ),
    );
    final host = FakeHost()
      ..reportOnline = true
      ..connectResult = {'ok': true};
    final updates = StreamController<WifiNetworkSnapshot>(sync: true);
    final controller = AppController(
      configRepository: repository,
      credentials: FakeCredentials(),
      logs: MemoryLogs(),
      host: host,
      wifiEvents: updates.stream,
    );
    addTearDown(() async {
      await controller.shutdown();
      controller.dispose();
      await updates.close();
    });
    Future<void> link(
      int? handle, {
      bool ready = true,
      String ssid = 'Campus',
    }) async {
      updates.add(
        WifiNetworkSnapshot(
          supported: true,
          permissionGranted: true,
          networks: [
            if (handle != null)
              WifiNetwork(
                handle: handle,
                ssid: ssid,
                interfaceName: 'wlan0',
                ipv4Addresses: const [
                  WifiLinkAddress(address: '10.0.0.5', prefixLength: 24),
                ],
                ready: ready,
              ),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
    }

    await controller.initialize();
    await link(1);
    expect(host.connects, 1);
    await link(1, ready: false);
    await controller.logout();
    lateProbe.complete(true);
    await link(1, ssid: '');
    await link(1);
    expect(host.connects, 1);
    await link(null);
    await link(2);
    await link(2);
    expect(host.connects, 2);

    final disconnect = Completer<Map<String, Object?>>();
    host.onDisconnect = () => disconnect.future;
    final logout = controller.logout();
    await link(null);
    await link(3);
    expect(host.connects, 2);
    disconnect.complete({'ok': true});
    await logout;
    await link(3);
    expect(host.connects, 3);
    expect(probes, [1, 2, 3]);
    expect(reports, [2]);
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
