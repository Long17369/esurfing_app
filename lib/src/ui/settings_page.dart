import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../platform/android_shell.dart';
import '../platform/desktop_shell.dart';
import '../platform/wifi_shell.dart';
import '../state/app_controller.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    required this.desktopShell,
  });

  final AppController controller;
  final DesktopShell desktopShell;

  static const List<int> _destroyChoices = [5, 10, 30, 60, 120];

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
                title: const Text('效率模式'),
                subtitle: Text(
                  DesktopShell.supported
                      ? '隐藏到托盘时让 Windows 把本进程当作后台任务，减少 CPU 占用'
                      : '仅 Windows 支持',
                ),
                value: ui.efficiencyMode,
                onChanged: DesktopShell.supported
                    ? (value) async {
                        await controller.updateUi(
                          ui.copyWith(efficiencyMode: value),
                        );
                        await desktopShell.syncEfficiencyMode();
                      }
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
              const Divider(),
              const _SectionHeader('Wi-Fi 联动（实验性）'),
              _WifiTile(controller: controller),
              if (Platform.isAndroid) ...[
                const Divider(),
                const _SectionHeader('Android 后台'),
                const _BatteryTile(),
                SwitchListTile(
                  title: const Text('隐藏后台'),
                  subtitle: const Text('切到后台后把界面从最近任务里移除，保活与通知继续'),
                  value: ui.hideInBackground,
                  onChanged: (value) =>
                      controller.updateUi(ui.copyWith(hideInBackground: value)),
                ),
                if (ui.hideInBackground)
                  ListTile(
                    title: const Text('后台多久后销毁界面'),
                    subtitle: const Text('到时间后界面被销毁，点通知可重新打开'),
                    trailing: DropdownButton<int>(
                      value: _destroyChoices.contains(ui.backgroundDestroyMinutes)
                          ? ui.backgroundDestroyMinutes
                          : 30,
                      items: [
                        for (final minutes in _destroyChoices)
                          DropdownMenuItem(
                            value: minutes,
                            child: Text('$minutes 分钟'),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        controller.updateUi(
                          ui.copyWith(backgroundDestroyMinutes: value),
                        );
                      },
                    ),
                  ),
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

class _WifiTile extends StatelessWidget {
  const _WifiTile({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    if (!WifiShell.supported) {
      return const ListTile(
        title: Text('Wi-Fi 自动登录'),
        subtitle: Text('Windows 侧暂未实现；该功能目前只在 Android 生效'),
        trailing: Chip(label: Text('未实现')),
        enabled: false,
      );
    }
    final status = controller.wifi;
    final subtitle = !status.permissionGranted
        ? '未授权：需要「附近的设备 / 位置信息」权限才能读取 Wi-Fi 名称'
        : !status.enabled
        ? 'Wi-Fi 已关闭'
        : status.connected
        ? '当前 Wi-Fi：${status.ssid}'
        : '当前未连接 Wi-Fi';
    return ListTile(
      title: const Text('Wi-Fi 自动登录'),
      subtitle: Text(
        '$subtitle\n目标 Wi-Fi 在账号编辑页里设置，按账号生效',
      ),
      isThreeLine: true,
      trailing: status.permissionGranted
          ? IconButton(
              tooltip: '刷新',
              onPressed: () => controller.probeWifiSsid(),
              icon: const Icon(Icons.refresh),
            )
          : TextButton(
              onPressed: () => controller.requestWifiPermission(),
              child: const Text('授权'),
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
