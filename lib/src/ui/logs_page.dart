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
      listenable: controller.logs,
      builder: (context, _) {
        final entries = controller.logs.recent;
        return Scaffold(
          appBar: AppBar(
            title: const Text('日志'),
            actions: [
              IconButton(
                tooltip: '复制全部',
                onPressed: entries.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(
                          ClipboardData(
                            text: entries.map((e) => e.formatted).join('\n'),
                          ),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已复制到剪贴板')),
                          );
                        }
                      },
                icon: const Icon(Icons.copy_all),
              ),
            ],
          ),
          body: entries.isEmpty
              ? const Center(child: Text('暂无日志'))
              : ListView.builder(
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
