import 'package:esurfing_app/src/platform/android_shell.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hidden and paused share one background deadline', (
    tester,
  ) async {
    var destroyed = 0;
    final lifecycle = AndroidBackgroundUiLifecycle(
      delay: () => const Duration(minutes: 1),
      destroyUi: () => destroyed++,
    );
    addTearDown(lifecycle.dispose);

    lifecycle.didChangeAppLifecycleState(AppLifecycleState.hidden);
    await tester.pump(const Duration(seconds: 30));
    lifecycle.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 30));
    expect(destroyed, 1);
    lifecycle.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 2));
    expect(destroyed, 1);
  });

  testWidgets('resume cancels the old deadline and reopening rearms it', (
    tester,
  ) async {
    var destroyed = 0;
    final lifecycle = AndroidBackgroundUiLifecycle(
      delay: () => const Duration(minutes: 1),
      destroyUi: () => destroyed++,
    );
    addTearDown(lifecycle.dispose);

    lifecycle.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 59));
    lifecycle.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 2));
    expect(destroyed, 0);

    lifecycle.didChangeAppLifecycleState(AppLifecycleState.hidden);
    await tester.pump(const Duration(minutes: 1));
    expect(destroyed, 1);
    lifecycle.didChangeAppLifecycleState(AppLifecycleState.detached);
    lifecycle.didChangeAppLifecycleState(AppLifecycleState.resumed);
    lifecycle.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 1));
    expect(destroyed, 2);
  });

  testWidgets('inactive is not background; detach and dispose cancel timers', (
    tester,
  ) async {
    var destroyed = 0;
    final lifecycle = AndroidBackgroundUiLifecycle(
      delay: () => const Duration(minutes: 1),
      destroyUi: () => destroyed++,
    );
    lifecycle.didChangeAppLifecycleState(AppLifecycleState.inactive);
    await tester.pump(const Duration(minutes: 1));
    expect(destroyed, 0);
    lifecycle.didChangeAppLifecycleState(AppLifecycleState.paused);
    lifecycle.didChangeAppLifecycleState(AppLifecycleState.detached);
    await tester.pump(const Duration(minutes: 1));
    expect(destroyed, 0);
    lifecycle.didChangeAppLifecycleState(AppLifecycleState.resumed);
    lifecycle.didChangeAppLifecycleState(AppLifecycleState.paused);
    lifecycle.dispose();
    await tester.pump(const Duration(minutes: 1));
    expect(destroyed, 0);
  });

  testWidgets('disabled and nonpositive delays never destroy UI', (
    tester,
  ) async {
    for (final delay in [null, Duration.zero, const Duration(seconds: -1)]) {
      final lifecycle = AndroidBackgroundUiLifecycle(
        delay: () => delay,
        destroyUi: () => fail('Disabled background hiding must not destroy UI'),
      );
      lifecycle.didChangeAppLifecycleState(AppLifecycleState.hidden);
      lifecycle.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 5));
      lifecycle.dispose();
    }
  });
}
