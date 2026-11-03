import 'package:flutter/material.dart';

import '../data/config_repository.dart';
import '../ffi/esf_models.dart';
import '../state/app_controller.dart';
import 'widgets/error_banner.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final snapshot = controller.snapshot;
        final account = controller.activeAccount;
        return Scaffold(
          appBar: AppBar(
            title: const Text('校园网助手'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(
                    controller.nativeVersion.isEmpty
                        ? '后端未加载'
                        : '后端 ${controller.nativeVersion}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!controller.ready)
                const LinearProgressIndicator(minHeight: 2)
              else if (controller.lastError.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ErrorBanner(
                    message: controller.lastError,
                    onDismiss: controller.clearError,
                  ),
                ),
              _StatusCard(snapshot: snapshot, account: account),
              const SizedBox(height: 16),
              if (account == null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '还没有账号',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text('先到「账号」页添加校园网账号，再回到这里连接。'),
                      ],
                    ),
                  ),
                )
              else
                _Actions(controller: controller, snapshot: snapshot),
              const SizedBox(height: 16),
              _Details(
                snapshot: snapshot,
                account: account,
                clientId: controller.config.clientId,
              ),
              if (snapshot.phase == SessionPhase.error) ...[
                const SizedBox(height: 16),
                _RecoveryHints(snapshot: snapshot),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.snapshot, required this.account});

  final SessionSnapshot snapshot;
  final AccountProfile? account;

  Color _color(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (snapshot.phase) {
      SessionPhase.online || SessionPhase.keeping => Colors.green,
      SessionPhase.error => scheme.error,
      SessionPhase.connecting || SessionPhase.authenticating => scheme.primary,
      _ => scheme.outline,
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                snapshot.isOnline
                    ? Icons.wifi
                    : snapshot.phase == SessionPhase.error
                    ? Icons.error_outline
                    : Icons.wifi_off,
                color: color,
                size: 30,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    snapshot.phase.label,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(color: color),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    account == null
                        ? '未选择账号'
                        : '${account!.title}'
                              '${account!.server.isEmpty ? '' : ' · ${account!.server}'}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (snapshot.message.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      snapshot.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            if (snapshot.isBusy)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.controller, required this.snapshot});

  final AppController controller;
  final SessionSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final online = snapshot.isOnline;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: snapshot.isBusy
                  ? null
                  : online
                  ? controller.logout
                  : controller.login,
              icon: Icon(online ? Icons.link_off : Icons.login),
              label: Text(online ? '断开连接' : '登录'),
            ),
            OutlinedButton.icon(
              onPressed: !online || snapshot.isBusy
                  ? null
                  : snapshot.keepRunning
                  ? controller.stopKeep
                  : controller.startKeep,
              icon: Icon(
                snapshot.keepRunning
                    ? Icons.pause_circle_outline
                    : Icons.autorenew,
              ),
              label: Text(snapshot.keepRunning ? '停止保活' : '开始保活'),
            ),
            OutlinedButton.icon(
              onPressed: snapshot.isBusy
                  ? null
                  : controller.autoConnectIfNeeded,
              icon: const Icon(Icons.restart_alt),
              label: const Text('重试自动连接'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({
    required this.snapshot,
    required this.account,
    required this.clientId,
  });

  final SessionSnapshot snapshot;
  final AccountProfile? account;
  final String clientId;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      if (snapshot.ipv4.isNotEmpty) ('本机 IP', snapshot.ipv4),
      if (snapshot.mac.isNotEmpty) ('MAC', snapshot.mac),
      if (account != null) ('模式', _modeLabel(account!.mode)),
      if (account != null && account!.keepEnabled)
        ('保活间隔', '${account!.keepInterval} 秒'),
      if (clientId.isNotEmpty) ('Client-ID', clientId),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Column(
        children: [
          for (final row in rows)
            ListTile(dense: true, title: Text(row.$1), trailing: Text(row.$2)),
        ],
      ),
    );
  }

  String _modeLabel(int mode) => switch (mode) {
    1 => 'Windows 模式',
    2 => 'Android 模式',
    _ => '自动',
  };
}

class _RecoveryHints extends StatelessWidget {
  const _RecoveryHints({required this.snapshot});

  final SessionSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final hints = switch (snapshot.errorCode) {
      '102' => const ['先断开已有会话，再重新登录；避免多设备同时在线。'],
      '105' => const ['账号已受限，请确认是否到期/欠费/超流量，不要反复重试。'],
      '14' => const ['会话已失效，重新登录即可。'],
      '1' => const ['尝试到设置页切换 Windows/Android 模式，并确认服务器地址。'],
      _ => const ['确认已连上校园 Wi-Fi，然后重新登录；必要时查看日志。'],
    };
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('建议', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final hint in hints) Text('• $hint'),
          ],
        ),
      ),
    );
  }
}
