import 'package:esurfing_app/src/platform/desktop_shell.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS login item uses complete app bundle, including spaces', () {
    expect(
      DesktopShell.launchPath(
        '/Applications/Campus Helper.app/Contents/MacOS/esurfing_app',
        macOS: true,
      ),
      '/Applications/Campus Helper.app',
    );
  });

  test('macOS rejects unpackaged executables instead of registering them', () {
    for (final executable in [
      '/usr/local/bin/esurfing_app',
      '/Applications/Test.app/esurfing_app',
      '/Applications/Test.app/Contents/Resources/esurfing_app',
    ]) {
      expect(
        () => DesktopShell.launchPath(executable, macOS: true),
        throwsStateError,
      );
    }
  });

  test('Windows retains executable startup path', () {
    const executable = r'C:\Program Files\Esurfing\esurfing_app.exe';
    expect(DesktopShell.launchPath(executable, macOS: false), executable);
  });
}
