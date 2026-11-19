import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('原生构建脚本', () {
    late Directory fixture;
    late Directory bin;
    late Map<String, String> environment;

    Future<void> executable(String name, String source) async {
      final file = File('${bin.path}/$name');
      await file.writeAsString('#!/bin/bash\nset -euo pipefail\n$source\n');
      final result = await Process.run('/bin/chmod', ['+x', file.path]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
    }

    Future<ProcessResult> build(String target) => Process.run(
      '/bin/bash',
      ['${fixture.path}/tool/build_native.sh', target],
      environment: environment,
      includeParentEnvironment: false,
    );

    setUp(() async {
      fixture = await Directory.systemTemp.createTemp('esurfing-native-test-');
      bin = await Directory('${fixture.path}/bin').create();
      await Directory('${fixture.path}/tool').create();
      await File('tool/build_native.sh')
          .copy('${fixture.path}/tool/build_native.sh');
      for (final tool in ['dirname', 'mkdir', 'cp', 'rm', 'awk']) {
        await Link('${bin.path}/$tool').create('/bin/$tool');
      }
      await executable('nproc', 'echo 2');
      await executable('uname', 'echo Linux');
      await executable('git', 'echo 980192c536980aaf4cc7d02a6a90d18a3eee6c2f');
      await executable('ninja', 'exit 0');
      await executable('cmake', r'''
printf '%s\n' "$*" >> "$BUILD_LOG"
if [[ "$1" == --build ]]; then
  mkdir -p "$2/lib" "$2/bin"
  printf 'test library' > "$2/lib/esurfing.so"
  printf 'test library' > "$2/bin/esurfing.dll"
  printf 'test library' > "$2/lib/libesurfing.dylib"
fi
''');
      await executable('readelf', r'''
if [[ "${READELF_FAIL:-}" == true || ( "${READELF_FAIL:-}" == dynamic && "$1" == -dW ) ]]; then
  echo "readelf failed" >&2
  exit 1
fi
if [[ "$1" == -lW ]]; then
  if [[ "${ELF_NO_LOAD:-}" == true ]]; then exit 0; fi
  printf '  LOAD 0x0 0x0 0x0 0x20 0x20 R E %s\n' "${ELF_ALIGNMENT:-0x4000}"
  printf '  LOAD 0x4000 0x4000 0x4000 0x20 0x20 RW 0x4000\n'
else
  printf '%s\n' "${ELF_DYNAMIC:-no shared C++ dependency}"
fi
''');
      final ndk = '${fixture.path}/ndk';
      await Directory('$ndk/build/cmake').create(recursive: true);
      await File('$ndk/build/cmake/android.toolchain.cmake').writeAsString('');
      environment = {
        'PATH': bin.path,
        'HOME': fixture.path,
        'ESURFING_C_DIR': '${fixture.path}/core',
        'ESURFING_BUILD_BASE': '${fixture.path}/build',
        'ANDROID_NDK_HOME': ndk,
        'BUILD_LOG': '${fixture.path}/cmake.log',
      };
    });

    tearDown(() async {
      await fixture.delete(recursive: true);
    });

    test('显式 Windows 构建在缺少 MinGW 时失败', () async {
      final result = await build('windows');
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('MinGW'));
    });

    test('Windows 构建使用检测到的交叉编译器', () async {
      await executable('x86_64-w64-mingw32-gcc', 'exit 0');
      await executable('x86_64-w64-mingw32-g++', 'exit 0');
      final result = await build('windows');
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final log = await File(environment['BUILD_LOG']!).readAsString();
      expect(log, contains('-DCMAKE_SYSTEM_NAME=Windows'));
      expect(
        log,
        contains('-DCMAKE_C_COMPILER=${bin.path}/x86_64-w64-mingw32-gcc'),
      );
      expect(
        log,
        contains('-DCMAKE_CXX_COMPILER=${bin.path}/x86_64-w64-mingw32-g++'),
      );
      expect(
        File('${fixture.path}/packages/esurfing_native/windows/esurfing.dll')
            .existsSync(),
        isTrue,
      );
    });

    test('MSYS 编译器传给原生 CMake 时包含 exe 扩展名', () async {
      for (final name in ['x86_64-w64-mingw32-gcc', 'x86_64-w64-mingw32-g++']) {
        await executable(name, 'exit 0');
        await executable('$name.exe', 'exit 0');
      }
      await executable('cygpath', r'printf "%s\n" "$2"');
      final result = await build('windows');
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final log = await File(environment['BUILD_LOG']!).readAsString();
      expect(
        log,
        contains('-DCMAKE_C_COMPILER=${bin.path}/x86_64-w64-mingw32-gcc.exe'),
      );
      expect(
        log,
        contains('-DCMAKE_CXX_COMPILER=${bin.path}/x86_64-w64-mingw32-g++.exe'),
      );
    });

    test('Android 校验所有 LOAD 段而非任意一个匹配段', () async {
      environment['ELF_ALIGNMENT'] = '0x1000';
      final result = await build('android');
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('16 KB'));
      expect(
        Directory('${fixture.path}/android/app/src/main/jniLibs').existsSync(),
        isFalse,
      );
    });

    test('Android 校验失败和动态 STL 依赖必须阻止复制产物', () async {
      environment['READELF_FAIL'] = 'true';
      var result = await build('android');
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('readelf failed'));

      environment['READELF_FAIL'] = 'dynamic';
      result = await build('android');
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('readelf failed'));

      environment.remove('READELF_FAIL');
      environment['ELF_DYNAMIC'] = 'NEEDED libc++_shared.so';
      result = await build('android');
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('libc++_shared.so'));
      expect(
        Directory('${fixture.path}/android/app/src/main/jniLibs').existsSync(),
        isFalse,
      );
    });

    test('缺少 ELF LOAD 段不能作为有效原生库复制', () async {
      environment['ELF_NO_LOAD'] = 'true';
      final result = await build('android');
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('LOAD'));
      expect(
        Directory('${fixture.path}/android/app/src/main/jniLibs').existsSync(),
        isFalse,
      );
    });

    test('all 保留缺少 Windows 工具链时跳过的行为', () async {
      environment['ELF_ALIGNMENT'] = '0x10000';
      final result = await build('all');
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stderr, contains('跳过 Windows'));
      for (final abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64']) {
        expect(
          File(
            '${fixture.path}/android/app/src/main/jniLibs/$abi/libesurfing.so',
          ).existsSync(),
          isTrue,
        );
      }
    });

    test('macOS 显式目标在非 macOS 主机上失败', () async {
      await executable('uname', 'echo Linux');
      final result = await build('macos');
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('macOS/Xcode'));
    });

    test('macOS 构建双架构并校验后复制 dylib', () async {
      await executable('uname', 'echo Darwin');
      await executable('lipo', r'''
[[ "$1" == -archs && -f "$2" ]] && printf 'arm64 x86_64\n'
''');
      await executable('otool', r'[[ "$1" == -L && -f "$2" ]]');
      final result = await build('macos');
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final log = await File(environment['BUILD_LOG']!).readAsString();
      expect(log, contains('-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64'));
      expect(log, contains('-DBUILD_TESTING=OFF'));
      expect(
        File('${fixture.path}/packages/esurfing_native/macos/libesurfing.dylib')
            .existsSync(),
        isTrue,
      );
    });

    test('macOS 不把构建机 Homebrew 动态依赖复制进应用', () async {
      await executable('uname', 'echo Darwin');
      await executable('lipo', r'''
if [[ "$1" == -archs ]]; then
  printf 'arm64 x86_64\n'
else
  exit 1
fi
''');
      await executable(
        'otool',
        r"printf '\t/opt/homebrew/lib/libz.dylib (compatibility version 1.0.0)\n'",
      );
      final result = await build('macos');
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('/opt/homebrew'));
      expect(
        File('${fixture.path}/packages/esurfing_native/macos/libesurfing.dylib')
            .existsSync(),
        isFalse,
      );
    });
  }, skip: !Platform.isLinux);
}
