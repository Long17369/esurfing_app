import 'package:flutter/material.dart';

import '../data/config_repository.dart';
import '../ffi/esf_types.dart';
import '../platform/wifi_shell.dart';
import '../state/app_controller.dart';

/// 账号编辑的独立页面（添加 / 编辑共用）。
///
/// 用页面而不是弹窗：字段多，键盘弹出时弹窗会被挤压，也很难滚动。
class AccountEditorPage extends StatefulWidget {
  const AccountEditorPage({super.key, required this.controller, this.existing});

  final AppController controller;
  final AccountProfile? existing;

  @override
  State<AccountEditorPage> createState() => _AccountEditorPageState();
}

class _AccountEditorPageState extends State<AccountEditorPage> {
  late final TextEditingController _account;
  late final TextEditingController _password;
  late final TextEditingController _displayName;
  late final TextEditingController _server;
  late final TextEditingController _port;
  late final TextEditingController _mscgip;
  late final TextEditingController _keepInterval;
  late final TextEditingController _wifiSsid;

  late int _mode;
  late bool _autoConnect;
  late bool _keepEnabled;
  late bool _preTerm;
  late bool _wifiAutoLogin;
  late bool _wifiConnectOnLogin;
  bool _saving = false;
  bool _probingWifi = false;
  final _formKey = GlobalKey<FormState>();

  bool get _editing => widget.existing != null;

  bool get _locked =>
      _editing && widget.controller.isAccountLocked(widget.existing!.id);

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
    final interval = existing?.keepInterval ?? 0;
    _keepInterval = TextEditingController(
      text: interval <= 0
          ? ''
          : interval == interval.roundToDouble()
          ? interval.toStringAsFixed(0)
          : interval.toString(),
    );
    _mode = EsfMode.normalize(existing?.mode ?? EsfMode.auto);
    _autoConnect = existing?.autoConnect ?? false;
    _keepEnabled = existing?.keepEnabled ?? true;
    _preTerm = existing?.preTerm ?? true;
    _wifiSsid = TextEditingController(text: existing?.wifiSsid ?? '');
    _wifiAutoLogin = existing?.wifiAutoLogin ?? false;
    _wifiConnectOnLogin = existing?.wifiConnectOnLogin ?? true;
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
    _wifiSsid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? '编辑账号' : '添加账号')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            if (_locked)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('该账号正在使用中，请先在主页断开连接再修改配置。'),
                ),
              ),
            TextFormField(
              controller: _account,
              decoration: const InputDecoration(
                labelText: '账号',
                hintText: '手机号 / 学号',
              ),
              enabled: !_editing,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '请输入账号' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                labelText: '密码',
                helperText: _editing ? '留空表示不修改已保存的密码' : null,
              ),
              validator: (v) {
                if (_editing && (v == null || v.isEmpty)) return null;
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
              decoration: const InputDecoration(
                labelText: '客户端模式（登录页可临时覆盖）',
              ),
              items: const [
                DropdownMenuItem(
                  value: EsfMode.windows,
                  child: Text('Windows 模式'),
                ),
                DropdownMenuItem(
                  value: EsfMode.android,
                  child: Text('Android 模式'),
                ),
              ],
              onChanged: (value) => setState(
                () => _mode = value ?? EsfMode.platformDefault,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _keepInterval,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: '保活间隔（秒）',
                helperText: '留空或 0 = 核心默认 10 秒；成功保活之间的等待时间',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final value = double.tryParse(v.trim());
                if (value == null || value <= 0) return '请输入正数（留空表示默认）';
                return null;
              },
            ),
            const SizedBox(height: 16),
            _wifiSection(context),
            const SizedBox(height: 8),
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
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ),
      ),
    );
  }

  /// Wi-Fi 联动（实验性）。绑在账号上：每个账号可以有自己的目标 Wi-Fi。
  Widget _wifiSection(BuildContext context) {
    final theme = Theme.of(context);
    final supported = WifiShell.supported;
    final hasTarget = _wifiSsid.text.trim().isNotEmpty;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.wifi_find, size: 20),
                const SizedBox(width: 8),
                Text('Wi-Fi 联动', style: theme.textTheme.titleSmall),
                const SizedBox(width: 8),
                const Chip(
                  label: Text('实验性'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              supported
                  ? '连上目标 Wi-Fi 才自动登录；点「登录」时若还没连上，会唤起系统 '
                        'Wi-Fi 面板等你选好后自动继续。'
                  : 'Windows 侧暂未实现，该项只在 Android 生效。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _wifiSsid,
              enabled: supported,
              decoration: InputDecoration(
                labelText: '目标 Wi-Fi（SSID）',
                hintText: '留空表示不管理 Wi-Fi',
                suffixIcon: TextButton(
                  onPressed: supported && !_probingWifi ? _useCurrentWifi : null,
                  child: _probingWifi
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('用当前'),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (supported && !widget.controller.wifi.permissionGranted)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '读取 Wi-Fi 名称需要「附近的设备 / 位置信息」权限。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('发现该 Wi-Fi 时自动登录'),
              subtitle: const Text('只在这一刻登录一次；已有会话时沿用原票据，不重复登录'),
              value: _wifiAutoLogin && hasTarget,
              onChanged: supported && hasTarget
                  ? (v) => setState(() => _wifiAutoLogin = v)
                  : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('点登录时自动连该 Wi-Fi'),
              subtitle: const Text('Android 10+ 无法静默连接，会打开系统 Wi-Fi 面板'),
              value: _wifiConnectOnLogin && hasTarget,
              onChanged: supported && hasTarget
                  ? (v) => setState(() => _wifiConnectOnLogin = v)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _useCurrentWifi() async {
    setState(() => _probingWifi = true);
    try {
      await widget.controller.requestWifiPermission();
      final ssid = await widget.controller.probeWifiSsid();
      if (!mounted) return;
      if (ssid.isEmpty) {
        _toast('没读到 Wi-Fi 名称：请先连上 Wi-Fi，或检查权限');
        return;
      }
      _wifiSsid.text = ssid;
      setState(() {});
    } finally {
      if (mounted) setState(() => _probingWifi = false);
    }
  }

  void _toast(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  String? _validatePort(String? value) {
    if (value == null || value.isEmpty) return null;
    final port = int.tryParse(value);
    if (port == null || port <= 0 || port > 65535) return '端口无效';
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final saved = await widget.controller.saveAccount(
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
      wifiSsid: _wifiSsid.text,
      wifiAutoLogin: _wifiAutoLogin,
      wifiConnectOnLogin: _wifiConnectOnLogin,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved) Navigator.pop(context, true);
  }
}
