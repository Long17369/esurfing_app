import 'package:flutter/material.dart';

import '../data/config_repository.dart';
import '../ffi/esf_types.dart';
import '../state/app_controller.dart';
import 'account_editor_page.dart';

class AccountsPage extends StatelessWidget {
  const AccountsPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final accounts = controller.accounts;
        final activeId = controller.activeAccount?.id;
        final locked = controller.hasLockedSession;
        return Scaffold(
          appBar: AppBar(title: const Text('账号')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _edit(context, null),
            icon: const Icon(Icons.add),
            label: const Text('添加账号'),
          ),
          body: accounts.isEmpty
              ? const Center(child: Text('还没有账号，点击右下角添加'))
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: accounts.length + (locked ? 1 : 0),
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    if (locked && index == 0) return const _LockBanner();
                    final account = accounts[index - (locked ? 1 : 0)];
                    final active = account.id == activeId;
                    final accountLocked = controller.isAccountLocked(
                      account.id,
                    );
                    return ListTile(
                      leading: Icon(
                        active ? Icons.check_circle : Icons.account_circle,
                        color: active
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      title: Text(account.title),
                      subtitle: Text(
                        [
                          account.account,
                          if (account.server.isNotEmpty) account.server,
                          EsfMode.label(EsfMode.normalize(account.mode)),
                          if (account.autoConnect) '自动连接',
                          if (account.wifiEnabled) 'Wi-Fi ${account.wifiSsid}',
                          if (account.keepEnabled)
                            '保活 ${AppController.keepIntervalLabel(account.keepInterval)}',
                          if (accountLocked) '使用中，已锁定',
                        ].join(' · '),
                      ),
                      onTap: active
                          ? null
                          : () => _activate(context, account, locked),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) async {
                          switch (value) {
                            case 'edit':
                              await _edit(context, account);
                              break;
                            case 'delete':
                              await _delete(context, account);
                              break;
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'edit',
                            // 在线账号的配置锁死，必须先断开。
                            enabled: !accountLocked,
                            child: Text(
                              accountLocked ? '编辑（先断开连接）' : '编辑',
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            enabled: !accountLocked,
                            child: Text(
                              accountLocked ? '删除（先断开连接）' : '删除',
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  Future<void> _edit(BuildContext context, AccountProfile? existing) async {
    if (existing != null && controller.isAccountLocked(existing.id)) {
      _toast(context, '该账号正在使用中，请先断开连接再修改配置');
      return;
    }
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            AccountEditorPage(controller: controller, existing: existing),
      ),
    );
  }

  /// 已连接时切换账号要显式确认：会先断开当前会话。
  Future<void> _activate(
    BuildContext context,
    AccountProfile account,
    bool locked,
  ) async {
    if (!locked) {
      await controller.setActiveAccount(account.id);
      return;
    }
    if (controller.snapshot.isBusy) {
      _toast(context, '操作进行中，请稍后再切换账号');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('切换账号'),
        content: Text('当前会话正在使用，切换到 ${account.title} 会先断开连接。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('断开并切换'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.setActiveAccount(account.id);
  }

  Future<void> _delete(BuildContext context, AccountProfile account) async {
    if (controller.isAccountLocked(account.id)) {
      _toast(context, '该账号正在使用中，请先断开连接再删除');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除账号'),
        content: Text('将删除 ${account.account} 的本地资料和保存的密码。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.deleteAccount(account.id);
    }
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _LockBanner extends StatelessWidget {
  const _LockBanner();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Text('当前账号正在连接/保活中：配置与客户端模式已锁定，断开后可修改。'),
      ),
    );
  }
}
