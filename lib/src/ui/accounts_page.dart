import 'package:flutter/material.dart';

import '../data/config_repository.dart';
import '../ffi/esf_types.dart';
import '../state/app_controller.dart';

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
                  itemCount: accounts.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final account = accounts[index];
                    final active = account.id == activeId;
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
                          EsfMode.label(account.mode),
                          if (account.autoConnect) '自动连接',
                          if (account.keepEnabled) '保活',
                        ].join(' · '),
                      ),
                      onTap: () => controller.setActiveAccount(account.id),
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
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 'edit', child: Text('编辑')),
                          PopupMenuItem(value: 'delete', child: Text('删除')),
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
    await showDialog<void>(
      context: context,
      builder: (_) =>
          AccountEditorDialog(controller: controller, existing: existing),
    );
  }

  Future<void> _delete(BuildContext context, AccountProfile account) async {
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
}

class AccountEditorDialog extends StatefulWidget {
  const AccountEditorDialog({
    super.key,
    required this.controller,
    this.existing,
  });

  final AppController controller;
  final AccountProfile? existing;

  @override
  State<AccountEditorDialog> createState() => _AccountEditorDialogState();
}

class _AccountEditorDialogState extends State<AccountEditorDialog> {
  late final TextEditingController _account;
  late final TextEditingController _password;
  late final TextEditingController _displayName;
  late final TextEditingController _server;
  late final TextEditingController _port;
  late final TextEditingController _mscgip;
  late final TextEditingController _keepInterval;

  late int _mode;
  late bool _autoConnect;
  late bool _keepEnabled;
  late bool _preTerm;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _account = TextEditingController(text: existing?.account ?? '');
    _password = TextEditingController();
    _displayName = TextEditingController(text: existing?.displayName ?? '');
    _server = TextEditingController(text: existing?.server ?? '');
    _port = TextEditingController(
      text: (existing?.port ?? 0) == 0 ? '' : existing!.port.toString(),
    );
    _mscgip = TextEditingController(text: existing?.mscgip ?? '');
    _keepInterval = TextEditingController(
      text: (existing?.keepInterval ?? 0) == 0
          ? ''
          : existing!.keepInterval.toString(),
    );
    _mode = existing?.mode ?? EsfMode.auto;
    _autoConnect = existing?.autoConnect ?? false;
    _keepEnabled = existing?.keepEnabled ?? true;
    _preTerm = existing?.preTerm ?? true;
  }

  @override
  void dispose() {
    _account.dispose();
    _password.dispose();
    _displayName.dispose();
    _server.dispose();
    _port.dispose();
    _mscgip.dispose();
    _keepInterval.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? '编辑账号' : '添加账号'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _account,
                  decoration: const InputDecoration(
                    labelText: '账号',
                    hintText: '手机号 / 学号',
                  ),
                  enabled: !editing,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '请输入账号' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: '密码',
                    helperText: editing ? '留空表示不修改已保存的密码' : null,
                  ),
                  validator: (v) {
                    if (editing && (v == null || v.isEmpty)) return null;
                    return (v == null || v.isEmpty) ? '请输入密码' : null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _displayName,
                  decoration: const InputDecoration(labelText: '备注名（可选）'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _server,
                        decoration: const InputDecoration(
                          labelText: '服务器（可选）',
                          hintText: '留空自动发现',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _port,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '端口'),
                        validator: _validatePort,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _mscgip,
                  decoration: const InputDecoration(labelText: 'mscgip（高级，可选）'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _mode,
                  decoration: const InputDecoration(labelText: '客户端模式'),
                  items: const [
                    DropdownMenuItem(value: EsfMode.auto, child: Text('自动')),
                    DropdownMenuItem(
                      value: EsfMode.windows,
                      child: Text('Windows 模式'),
                    ),
                    DropdownMenuItem(
                      value: EsfMode.android,
                      child: Text('Android 模式'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _mode = value ?? EsfMode.auto),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _keepInterval,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '保活间隔（秒，0 表示默认）',
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return null;
                    final value = int.tryParse(v);
                    if (value == null || value < 0) return '请输入非负整数';
                    return null;
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启动/开机后自动连接'),
                  value: _autoConnect,
                  onChanged: (v) => setState(() => _autoConnect = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('登录后自动保活'),
                  value: _keepEnabled,
                  onChanged: (v) => setState(() => _keepEnabled = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('登录前先注销旧会话'),
                  subtitle: const Text('对应核心的 pre_term'),
                  value: _preTerm,
                  onChanged: (v) => setState(() => _preTerm = v),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }

  String? _validatePort(String? value) {
    if (value == null || value.isEmpty) return null;
    final port = int.tryParse(value);
    if (port == null || port <= 0 || port > 65535) return '端口无效';
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await widget.controller.saveAccount(
      id: widget.existing?.id,
      account: _account.text.trim(),
      password: _password.text,
      displayName: _displayName.text.trim(),
      server: _server.text.trim(),
      port: int.tryParse(_port.text.trim()) ?? 0,
      mscgip: _mscgip.text.trim(),
      mode: _mode,
      autoConnect: _autoConnect,
      keepEnabled: _keepEnabled,
      keepInterval: double.tryParse(_keepInterval.text.trim()) ?? 0,
      preTerm: _preTerm,
    );
    if (mounted) Navigator.pop(context);
  }
}
