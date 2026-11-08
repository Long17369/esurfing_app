import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/log_repository.dart';
import '../state/app_controller.dart';

class LogsPage extends StatelessWidget {
  const LogsPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, controller.logs]),
      builder: (context, _) {
        final logs = controller.logs;
        final entries = logs.visible;
        final level = controller.logLevel;
        return Scaffold(
          appBar: AppBar(
            title: const Text('日志'),
            actions: [
              _LevelMenu(
                level: level,
                onChanged: controller.setLogLevel,
              ),
              IconButton(
                tooltip: '复制当前级别',
                onPressed: entries.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(
                          ClipboardData(
                            text: entries.map((e) => e.formatted).join('\n'),
                          ),
                        );
                        if (context.mounted) {
                          _toast(context, '已复制 ${entries.length} 条日志');
                        }
                      },
                icon: const Icon(Icons.copy_all),
              ),
              IconButton(
                tooltip: '导出完整历史日志',
                onPressed: () => _export(context),
                icon: const Icon(Icons.download),
              ),
            ],
          ),
          body: entries.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      '暂无 ${level.label} 及以上级别的日志',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return ListTile(
                      dense: true,
                      leading: _LevelDot(level: entry.level),
                      title: Text(entry.message),
                      subtitle: Text(
                        entry.time.toLocal().toString().split('.').first,
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  Future<void> _export(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await controller.logs.exportToFile();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('已导出历史日志'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('完整日志（含已轮转的历史文件）已写入：'),
              const SizedBox(height: 8),
              SelectableText(
                file.path,
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: file.path));
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                messenger
                  ..clearSnackBars()
                  ..showSnackBar(const SnackBar(content: Text('已复制文件路径')));
              },
              child: const Text('复制路径'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('好'),
            ),
          ],
        ),
      );
    } catch (error) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('导出失败：$error')));
    }
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 日志显示级别选择（持久化在 `ui.logLevel`，默认 INFO）。
class _LevelMenu extends StatelessWidget {
  const _LevelMenu({required this.level, required this.onChanged});

  final LogLevel level;
  final ValueChanged<LogLevel> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<LogLevel>(
      tooltip: '显示级别',
      initialValue: level,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final value in LogLevel.values.reversed)
          PopupMenuItem(
            value: value,
            child: Row(
              children: [
                Icon(
                  value == level ? Icons.check : Icons.remove,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(value.label),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Center(
          child: Row(
            children: [
              const Icon(Icons.filter_list, size: 18),
              const SizedBox(width: 4),
              Text(level.label),
            ],
          ),
        ),
      ),
    );
  }
}

class _LevelDot extends StatelessWidget {
  const _LevelDot({required this.level});

  final LogLevel level;

  @override
  Widget build(BuildContext context) {
    final color = switch (level) {
      LogLevel.error => Theme.of(context).colorScheme.error,
      LogLevel.warn => Colors.orange,
      LogLevel.info => Theme.of(context).colorScheme.primary,
      LogLevel.debug => Theme.of(context).colorScheme.outline,
    };
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
