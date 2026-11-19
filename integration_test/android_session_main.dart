// This target is never used by production main and never reads stored accounts.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:esurfing_app/src/ffi/esf_models.dart';
import 'package:esurfing_app/src/ffi/esf_types.dart';
import 'package:esurfing_app/src/platform/android_shell.dart';
import 'package:esurfing_app/src/state/host_client.dart';

import 'android_loopback_fixture.dart';

const _check = MethodChannel('esurfing/session-check');
const _android = MethodChannel('esurfing/android');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: _SessionCheck()));
}

class _SessionCheck extends StatefulWidget {
  const _SessionCheck();

  @override
  State<_SessionCheck> createState() => _SessionCheckState();
}

class _SessionCheckState extends State<_SessionCheck>
    with WidgetsBindingObserver {
  final _host = HostClient();
  final _identity = DateTime.now().microsecondsSinceEpoch.toString();
  final _counts = <String, int>{};
  final _history = <String>[];
  late final AndroidBackgroundUiLifecycle _lifecycle;
  HttpServer? _server;
  Timer? _reporter;
  String _phase = 'starting';
  String _error = '';
  bool _running = false;
  bool _disposed = false;
  int _destroyCalls = 0;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _lifecycle = AndroidBackgroundUiLifecycle(
      delay: () => const Duration(seconds: 6),
      destroyUi: () {
        _destroyCalls++;
        unawaited(AndroidShell.destroyUi());
      },
    );
    WidgetsBinding.instance.addObserver(this);
    _check.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'permission':
          await AndroidShell.requestNotificationPermission();
        case 'wifiPermission':
          await _android.invokeMethod<bool>('requestWifiPermission');
        case 'stop':
          _reporter?.cancel();
          await _host.dispose();
          await _android.invokeMethod<void>('stopSessionService');
          await _server?.close(force: true);
          _disposed = true;
          _running = false;
          _phase = 'disposed';
        case 'status':
          break;
        default:
          throw StateError('Unknown isolated command ${call.method}');
      }
      await _report();
    });
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server = server;
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        final path = request.uri.path;
        _counts.update(path, (n) => n + 1, ifAbsent: () => 1);
        request.response.headers.set('Error-Code', '0');
        if (body == 'tarce log algo auto compstr null value') {
          request.response.add(base64Decode(loopbackLibrary));
        } else if (path.endsWith('ticket.cgi')) {
          request.response.write(loopbackTicket);
        }
        // Empty auth/keep/term bodies are valid with Error-Code: 0.
        await request.response.close();
      });
      await _host.start();
      final version = await _host.send('version');
      _version = '${version['version']}';
      if (version['compatibilityError'] != null) {
        throw StateError('${version['compatibilityError']}');
      }
      final connected = await _host.send(
        'connect',
        SessionParams(
          account: 'isolated-loopback-user',
          password: 'isolated-not-a-real-password',
          clientId: 'isolated-session-check',
          server: '127.0.0.1',
          port: server.port,
          mode: EsfMode.android,
          mac: '02:00:00:17:36:90',
          preTerm: false,
          keepInterval: 1,
        ).toMap(),
      );
      if (connected['ok'] != true) throw StateError('$connected');
      await _host.send('startKeep');
      await _android.invokeMethod<void>('startSessionService');
      _phase = 'keeping';
      _reporter = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(_report()),
      );
      await _report();
    } catch (error) {
      _error = '$error';
      _phase = 'error';
      await _report();
    }
  }

  Future<void> _report() async {
    if (!_disposed && _phase == 'keeping') {
      _running = (await _host.send('keepRunning'))['running'] == true;
      await _android.invokeMethod<void>('updateNotification', {
        'text': 'Isolated native keep check',
      });
    }
    await _check.invokeMethod<void>(
      'evidence',
      jsonEncode({
        'host': _identity,
        'version': _version,
        'phase': _phase,
        'nativeKeepRunning': _running,
        'destroyCalls': _destroyCalls,
        'lifecycle': _history,
        'requests': _counts,
        'error': _error,
      }),
    );
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _history.add(state.name);
    _lifecycle.didChangeAppLifecycleState(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lifecycle.dispose();
    _reporter?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Isolated Android session check')),
    body: Text('$_phase\nhost=$_identity\nnative=$_running\n$_error'),
  );
}
