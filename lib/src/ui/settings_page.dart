import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../platform/android_shell.dart';
import '../platform/desktop_shell.dart';
import '../state/app_controller.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    required this.desktopShell,
  });

  final AppController controller;
  final DesktopShell desktopShell;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final ui = controller.config.ui;
        return Scaffold(
          appBar: AppBar(title: const Text('设置')),
          body: ListView(
            children: [
              const _SectionHeader('启动与窗口'),
              SwitchListTile(
                title: const Text('开机自启动'),
                subtitle: Text(
                  DesktopShell.supported ? '写入当前用户启动项（UAC 外）' : '仅 Windows 支持',
                ),
                value: ui.autoStart,
                onChanged: DesktopShell.supported
                    ? (value) async {
                        await desktopShell.setAutoStart(value);
                        await controller.updateUi(
                          ui.copyWith(autoStart: value),
                        );
                      }
                    : null,
              ),
              SwitchListTile(
                title: const Text('启动后最小化到托盘'),
                value: ui.startMinimized,
                onChanged: DesktopShell.supported
                    ? (value) => controller.updateUi(
                        ui.copyWith(startMinimized: value),
                      )
                    : null,
              ),
              SwitchListTile(
                title: const Text('关闭窗口时最小化到托盘'),
                subtitle: const Text('关闭后保活继续运行'),
                value: ui.closeToTray,
                onChanged: DesktopShell.supported
                    ? (value) =>
                          controller.updateUi(ui.copyWith(closeToTray: value))
                    : null,
              ),
              SwitchListTile(
                title: const Text('退出时自动断开'),
                subtitle: const Text('避免服务端残留在线会话'),
                value: ui.logoutOnExit,
                onChanged: (value) =>
                    controller.updateUi(ui.copyWith(logoutOnExit: value)),
              ),
              const Divider(),
              const _SectionHeader('通知'),
              SwitchListTile(
                title: const Text('显示连接状态通知'),
                value: ui.notifications,
                onChanged: (value) =>
                    controller.updateUi(ui.copyWith(notifications: value)),
              ),
              if (Platform.isAndroid) ...[
                const Divider(),
                const _SectionHeader('Android 后台'),
                const _BatteryTile(),
                ListTile(
                  title: const Text('Shizuku 增强'),
                  subtitle: const Text('预留接口，本期未实现'),
                  trailing: const Chip(label: Text('后续')),
                  enabled: false,
                ),
              ],
              const Divider(),
              const _SectionHeader('关于'),
              _AboutTile(nativeVersion: controller.nativeVersion),
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

class _BatteryTile extends StatefulWidget {
  const _BatteryTile();

  @override
  State<_BatteryTile> createState() => _BatteryTileState();
}

class _BatteryTileState extends State<_BatteryTile> {
  bool? _ignoring;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final value = await AndroidShell.isIgnoringBatteryOptimizations();
    if (mounted) setState(() => _ignoring = value);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: const Text('电池优化白名单'),
      subtitle: Text(
        _ignoring == null
            ? '正在检查…'
            : _ignoring!
            ? '已加入白名单'
            : '未加入，厂商省电策略可能中断保活',
      ),
      trailing: _ignoring == true
          ? const Icon(Icons.check_circle, color: Colors.green)
          : TextButton(
              onPressed: () async {
                await AndroidShell.requestIgnoreBatteryOptimizations();
                await Future<void>.delayed(const Duration(seconds: 1));
                await _refresh();
              },
              child: const Text('去设置'),
            ),
    );
  }
}

class _AboutTile extends StatelessWidget {
  const _AboutTile({required this.nativeVersion});

  final String nativeVersion;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        return Column(
          children: [
            ListTile(
              title: const Text('应用版本'),
              trailing: Text(
                info == null ? '-' : '${info.version} (${info.buildNumber})',
              ),
            ),
            ListTile(
              title: const Text('原生后端'),
              trailing: Text(nativeVersion.isEmpty ? '-' : nativeVersion),
            ),
            ListTile(
              title: const Text('平台'),
              trailing: Text(Platform.operatingSystem),
            ),
            const ListTile(title: Text('分发方式'), trailing: Text('侧载')),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: Text(
                '原生后端与 App 通过 C ABI 通信。Apple 平台（macOS/iOS）'
                '将在单独分支实现，本期不构建、不测试。',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        );
      },
    );
  }
}
