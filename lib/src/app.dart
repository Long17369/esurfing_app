import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'platform/android_shell.dart';
import 'platform/desktop_shell.dart';
import 'state/app_controller.dart';
import 'ui/accounts_page.dart';
import 'ui/home_page.dart';
import 'ui/logs_page.dart';
import 'ui/settings_page.dart';

class EsurfingApp extends StatelessWidget {
  const EsurfingApp({
    super.key,
    required this.controller,
    required this.desktopShell,
  });

  final AppController controller;
  final DesktopShell desktopShell;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '校园网助手',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1668DC)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1668DC),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: AppShell(controller: controller, desktopShell: desktopShell),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.controller,
    required this.desktopShell,
  });

  final AppController controller;
  final DesktopShell desktopShell;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _index = 0;
  Timer? _backgroundTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _backgroundTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!Platform.isAndroid) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _cancelBackgroundDestroy();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _armBackgroundDestroy();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  void _cancelBackgroundDestroy() {
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
  }

  /// 长时间留在后台就销毁界面（也从最近任务里移除），保活与前台服务不动。
  void _armBackgroundDestroy() {
    _cancelBackgroundDestroy();
    final ui = widget.controller.config.ui;
    final minutes = ui.backgroundDestroyMinutes;
    if (!ui.hideInBackground || minutes <= 0) return;
    _backgroundTimer = Timer(Duration(minutes: minutes), () {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        return;
      }
      widget.controller.logs.add(
        '已置于后台 $minutes 分钟，销毁界面（保活继续）',
      );
      AndroidShell.destroyUi();
    });
  }

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.power_settings_new_outlined),
      selectedIcon: Icon(Icons.power_settings_new),
      label: '连接',
    ),
    NavigationDestination(
      icon: Icon(Icons.people_outline),
      selectedIcon: Icon(Icons.people),
      label: '账号',
    ),
    NavigationDestination(
      icon: Icon(Icons.tune_outlined),
      selectedIcon: Icon(Icons.tune),
      label: '设置',
    ),
    NavigationDestination(
      icon: Icon(Icons.article_outlined),
      selectedIcon: Icon(Icons.article),
      label: '日志',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(controller: widget.controller),
      AccountsPage(controller: widget.controller),
      SettingsPage(
        controller: widget.controller,
        desktopShell: widget.desktopShell,
      ),
      LogsPage(controller: widget.controller),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        final body = pages[_index];
        if (!wide) {
          return Scaffold(
            body: body,
            bottomNavigationBar: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: _destinations,
            ),
          );
        }
        return Scaffold(
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                labelType: NavigationRailLabelType.all,
                leading: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Icon(Icons.wifi_tethering, size: 32),
                ),
                destinations: _destinations
                    .map(
                      (d) => NavigationRailDestination(
                        icon: d.icon,
                        selectedIcon: d.selectedIcon,
                        label: Text(d.label),
                      ),
                    )
                    .toList(),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ],
          ),
        );
      },
    );
  }
}
