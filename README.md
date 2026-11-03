# 校园网助手（esurfing_app）

`esurfing_c` 的图形界面前端。Flutter 负责 UI 与状态，协议、加密、网卡与会话全部
复用 `esurfing_c` 的 C API（`include/esurfing.h`），通过 `dart:ffi` 调用。

**本期范围：Windows x64 + Android。** macOS / iOS 的原生产物、平台壳与验证
留到后续 Apple 分支；代码里保留了对应加载分支，但本期不构建、不测试、不打包。

## 功能

- 登录 / 登出，错误码引导（102 已有会话、105 账号受限、14 无会话等）
- 保活（默认永久保活，登录后自动启动）
- 多账号档案、单活动会话、切换账号
- Windows：托盘常驻、关闭到托盘、开机自启、启动最小化、单实例
- Android：前台服务常驻通知、开机自启、电池优化白名单引导
- 日志页（最近 500 条 + 文件轮转）

## 目录

```
lib/src/ffi/       esf_* 绑定、结构体、后台会话 isolate
lib/src/state/     AppController（ChangeNotifier）与 isolate 客户端
lib/src/data/      配置 JSON、安全存储、Client-ID / 伪 MAC、日志
lib/src/ui/        主页、账号、设置、日志
lib/src/platform/  桌面托盘壳、Android 权限壳
android/           Kotlin 前台服务 / 常驻 FlutterEngine / 开机广播
tool/              原生库构建与打包脚本
```

## 构建前置

| 用途 | 依赖 |
|---|---|
| Flutter | Flutter 3.47+ / Dart 3.13+ |
| Android | Android SDK、NDK **28.2.13676358**、JDK 17+ |
| Windows 原生库 | MSYS2 MinGW-w64（`mingw-w64-x86_64-gcc` + `cmake`） |
| Windows 应用 | Visual Studio 2022（Desktop development with C++） |

> 首次 Android 构建需要访问 `services.gradle.org` 和 `maven.google.com`
> 下载 Gradle 与 Android 依赖；网络受限时会长时间停在依赖解析阶段。

国内网络可改用镜像并只构建一个 ABI（首次会下载约 180 MB 引擎包）：

```bash
FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn \
  flutter build apk --debug --target-platform android-arm64
```

## 构建原生后端

```bash
# Android 三个 ABI + Windows DLL（Windows 部分无 MinGW 时自动跳过）
tool/build_native.sh all
# 只做一端
tool/build_native.sh android
tool/build_native.sh windows
```

产物位置：

- Android：`android/app/src/main/jniLibs/{arm64-v8a,armeabi-v7a,x86_64}/libesurfing.so`
  （已加 `-Wl,-z,max-page-size=16384`，满足 Android 15+ 的 16 KB 页要求；
  C++ 运行时静态链在库内，不依赖 `libc++_shared.so`，`jniLibs` 里只有这一个 `.so`）
- Windows：`packages/esurfing_native/windows/esurfing.dll`
  （CMake 在 `windows/` 构建时自动安装到 exe 同目录）

> **Android 的 STL 用 CMake 默认值 `c++_static`，不要传 `-DANDROID_STL=c++_shared`。**
> 传了 `c++_shared` 后 `libesurfing.so` 会带 `NEEDED libc++_shared.so`，而 Flutter 只打包
> `jniLibs` 下的东西、不会带 NDK 那份，`dlopen` 时直接抛
> `library "libc++_shared.so" not found`。
> 静态链接后体积约 970 KB（arm64），只依赖 `libdl / libm / libc`。
>
> 构建目录的 `CMakeCache.txt` 会记住上一次的 `ANDROID_STL`，所以 `tool/build_native.sh`
> 每次配置都带 `-UANDROID_STL -UCMAKE_ANDROID_STL_TYPE` 清掉残留，并在构建后用
> `readelf -d` 校验：一旦发现依赖 `libc++_shared.so` 直接报错退出。
>
> 也不要指望系统自带的 `/system/lib64/libc++_shared.so`：`adb shell` 里的进程能加载它，
> 但 App 的 linker namespace 只放行 `public.libraries.txt` 白名单，该库不在其中。

## 运行与打包

```bash
flutter pub get
flutter analyze
flutter test

flutter run -d windows     # 需要 Windows + VS2022
flutter run -d android     # 需要真机/模拟器

tool/package_windows.sh    # -> dist/esurfing-app-windows-x64.zip
tool/package_android.sh    # -> dist/app-<abi>-release.apk
```

## 应用图标

图标全部由 `tool/make_icons.py` 用 Pillow 生成（渐变圆角底 + Wi-Fi 弧 + 绿色在线徽章），
换配色或形状只需改脚本里的常量后重跑：

```bash
python3 tool/make_icons.py
```

一次性写出：

| 产物 | 用途 |
|---|---|
| `assets/icon/app_icon.png`（1024） | 源图，用于商店/文档 |
| `windows/runner/resources/app_icon.ico`（16–256） | Windows exe 图标 |
| `assets/tray.ico`（16–64） | 系统托盘图标（深蓝圆底，小尺寸简化） |
| `android/.../mipmap-*/ic_launcher.png`（48–192） | Android 旧版图标 |
| `android/.../mipmap-*/ic_launcher_foreground.png` | 自适应图标前景（内容缩至 0.66 安全区） |
| `android/.../drawable/ic_launcher_background.xml` | 自适应图标渐变背景 |
| `android/.../mipmap-anydpi-v26\|v33/ic_launcher.xml` | 自适应图标（v33 带单色主题图标） |

需要 `pip install pillow numpy`。

## 侧载说明

- **Windows**：解压 zip 直接运行 `esurfing_app.exe`，`esurfing.dll` 必须与 exe 同目录。
  未签名会触发 SmartScreen，选择「更多信息 → 仍要运行」。
- **Android**：安装 APK 时允许「安装未知应用」。首次启动请授予通知权限，
  并在系统设置里关闭本应用的电池优化、允许自启动，否则后台保活会被厂商策略中断。
- 两端都只支持侧载，不上架应用商店。

## 已知限制

- 账号配置与 `esurfing_c` CLI 的配置文件不互通，需在 App 内重新录入。
- Android 10+ 拿不到真实 Wi-Fi MAC，App 会生成并持久化一个本地管理伪 MAC
  （首字节 `0x02`）传给 `esf_set_mac`；它只影响报文，不修改网卡。
- 同一时刻只有一个活动会话，不支持多账号同时在线。
- 暂不支持手动选择网卡、Shizuku 接入、原生后端热更新。
- macOS / iOS：见后续 Apple 分支（`en0` 出口、iOS 网关探测、静态链接、
  Keychain 与侧载证书等）。
