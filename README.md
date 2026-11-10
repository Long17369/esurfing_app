# 校园网助手（esurfing_app）

`esurfing_c` 的图形界面前端。Flutter 负责 UI 与状态，协议、加密、网卡与会话全部
复用 `esurfing_c` 的 C API（`include/esurfing.h`），通过 `dart:ffi` 调用。

**本期范围：Windows x64 + Android。** macOS / iOS 的原生产物、平台壳与验证
留到后续 Apple 分支；代码里保留了对应加载分支，但本期不构建、不测试、不打包。

## 功能

- 登录 / 登出，错误码引导（102 已有会话、105 账号受限、14 无会话等）
- 客户端模式只有 **Windows / Android** 两种（无「自动」）：
  - 账号里保存的是该账号的默认模式；
  - 主页（登录页）可临时覆盖，优先级高于账号配置，**只对本次登录生效，不写回配置文件**；
  - 主页可点「恢复账号设置」回到账号模式；
  - 同一时刻只允许一个账号在线，已在线时需先断开再登录其它账号
- 保活（默认永久保活，登录后自动启动）；保活间隔按账号配置，
  留空/0 表示用核心内置默认 10 秒（`esf_options.keep_interval`）
- 多账号档案、单活动会话、切换账号；账号编辑是独立页面
- 在线锁定：连接中/已连接/保活中时，当前账号的配置与客户端模式不可修改，
  需先在主页断开；已连接时切换账号会先弹确认再断开
- Windows：托盘常驻、关闭到托盘、开机自启、启动最小化、单实例
- Android：前台服务常驻通知、开机自启、电池优化白名单引导
- 日志页：显示级别可选（DEBUG / INFO / WARN / ERROR，默认 INFO 且持久化在
  `ui.logLevel`），可复制当前级别，也可一键导出完整历史日志（含轮转文件）
- Wi-Fi 联动（**实验性，仅 Android**）：每个账号可绑定一个目标 Wi-Fi，
  发现连上该 Wi-Fi 就自动登录；点「登录」时若还没连上，会唤起系统 Wi-Fi 面板，
  连上后自动继续登录

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
| Windows 原生库 | MSYS2 MinGW-w64（`mingw-w64-x86_64-gcc` + `cmake` + `ninja`） |
| Windows 应用 | Visual Studio 2022（Desktop development with C++） |

> Windows 端不用本地装 MinGW：CI 会编好 `esurfing.dll` 并出 zip，本地只跑
> `flutter run -d windows` 的话把 CI 的 zip 解开用即可；要本地编原生库见上一节。
>
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

## CI 与分支约定

分支：`dev` 是开发分支，**所有改动先提交到 `dev`**；`main` 只放发布快照
（`dev` 通过后再快进/合并过去）。

Tag：从 App `1.3.0` 起每次发版打 `v<semver>`（与 `pubspec.yaml` 的版本一致，
不带 `+build`，例如 `v1.3.0`），打在 `dev` 的发布提交上。`main` 上没有 workflow，
把 tag 打在 `dev` 才能让 CI 出包。

`.github/workflows/build.yml` 做四件事：

| job | 触发 | 产物 |
|---|---|---|
| `analyze & test` | 每次 push / PR | `flutter analyze` + `flutter test` |
| `windows x64` | 每次 push / PR | MSYS2 MinGW 编 `esurfing.dll` → `flutter build windows --release` → `dist/esurfing-app-windows-x64-<ver>.zip` |
| `android apk` | 每次 push / PR | 重编三个 ABI 的 `libesurfing.so` → `flutter build apk --release` → `dist/esurfing-app-android-<ver>.apk` |
| `release` | 仅 `v*` tag | 把上面两个产物挂到 GitHub Release |

### 绑定的 C 库版本

C 库直接由官方 `actions/checkout` 拉（`repository` + `ref` + `path: esurfing_c`），
地址与版本都走变量，仓库里不写死：

| 变量 | 默认值 | 说明 |
|---|---|---|
| `ESURFING_C_REPO`（Actions 变量） | `<当前 owner>/esurfing_c` | C 库仓库，`owner/repo` 或完整 git 地址都行 |
| `ESURFING_C_TOKEN` / `PAT_TOKEN`（Secret） | 空 | **C 库私有后必需**。fine-grained PAT 要勾上 `esurfing_c` 且给 `Contents: Read-only`：只有 `Metadata: Read`（这个权限是 PAT 自带的）时 REST API 能读，但 `git clone/fetch` 仍返回 `Repository not found.` —— GitHub 用 404 隐藏私有库，不会回 403。改 PAT 权限**不会换 token 值**，Secret 不用动，直接 Re-run |
| `ESURFING_C_DEPLOY_KEY`（Secret） | 空 | 备选：只读 Deploy Key 私钥。用时把 `ESURFING_C_REPO` 写成 `git@github.com:<owner>/esurfing_c.git`（公钥加到 `esurfing_c` → Settings → Deploy keys，不勾 write） |
| `ESURFING_C_REF`（Actions 变量） | `v1.2.1` | **必须是 tag**，tag 不存在就直接失败，没有回退 commit |

升级 C 库的流程：C 库仓库打 tag 并推送 → 改 `ESURFING_C_REF`（或仓库变量）→
本地 `tool/build_native.sh all` 重编 `jniLibs` 与 DLL 并提交 → App 版本号按需递增。

Windows 构建用的是 MSYS2 的 mingw-w64（`esurfing_c` 的 CMake 里有 `-static`、
`--gc-sections` 等 GCC 参数，MSVC 编不了）；DLL 是 CMake 的 RUNTIME 产物，
落在 `build/bin/esurfing.dll`，`tool/build_native.sh` 会先找 `bin/` 再找 `lib/`。

## 版本与兼容

App 与 `esurfing_c` **各自独立版本号**，不要求一致：

| 项目 | 位置 | 当前值 |
|---|---|---|
| App 版本 | `pubspec.yaml` 的 `version: <semver>+<build>` | `1.3.0+7` |
| 原生库 ABI | `esf_version()` 返回的 `1.2.1` | 只校验主版本 |

- App 版本只在自身有改动时递增（功能 → 次版本，修复 → 补丁号，每次发版 `+build` 加 1）；
  无需跟随原生库升级，也不要为了对齐库版本而改它。
- `+build` 映射为 Android `versionCode` / Windows 文件版本第 4 段，
  通过 `flutter` 自动注入；Windows 的 `Runner.rc` 已用 `FLUTTER_VERSION*` 宏，无需手改。
- 唯一硬约束是**原生库 ABI 主版本必须匹配**（`AppController._versionCompatible`），
  不匹配时启动即报「原生后端版本不符」，不继续登录。
- 原生库换新版本（同主版本）直接替换二进制即可，App 不用改版本号。
- **原生库请用 `esurfing_c` v1.2.1 及以上**：1.2.0 及更早版本在「配置里存了上次成功的
  MAC、但默认路由指向另一块网卡」的场景下，会用默认路由的 IPv4 配保存的 MAC 发报文，
  服务端按 (IP, MAC) 匹配不上，直接返回 `Error-Code = 102`（表现为「已有在线会话」
  却怎么也登不上）。App 侧对此无解，只能换原生库。
- 事件回调优先使用 `esf_set_owned_event_cb`（v1.2.0 起，文本所有权转移给宿主，
  读完 `esf_free`）—— Dart 的 `NativeCallable.listener` 是异步投递，旧的
  `on_event` 约定「text 只在回调期间有效」会读到悬空指针。运行时探测不到该符号时
  自动回退到旧的 `on_event`，并用容错解码（`decodeNativeUtf8`）兜底。

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

## Wi-Fi 联动（实验性）

按**账号**绑定，不是全局设置：`config.json` 的 `accounts[].wifiSsid` /
`wifiAutoLogin` / `wifiConnectOnLogin`。

| 字段 | 含义 |
|---|---|
| `wifiSsid` | 目标 Wi-Fi 的 SSID；留空表示该账号不管理 Wi-Fi |
| `wifiAutoLogin` | 发现刚连上该 Wi-Fi 且当前没有会话时，自动登录 |
| `wifiConnectOnLogin` | 点「登录」时若还没连上，先唤起系统 Wi-Fi 面板，连上后自动继续 |

**平台事实（决定了实现边界）**

- **Android 10+**：App 既不能直接开关 Wi-Fi（`setWifiEnabled` 已废弃且返回 false），
  也不能静默连接任意 SSID（`addNetwork` + `enableNetwork` 需要系统权限）。
  所以只能「读当前 SSID」+「唤起系统 Wi-Fi 面板」+「检测到连上后继续登录」，
  真正的连接由系统自动连接或用户点一下完成。Android 9 及以下会顺手把 Wi-Fi 打开。
- **Windows**：本期不实现（`netsh wlan` 要建配置文件、还要处理 GBK 输出），
  设置页会显示「未实现」，账号编辑页的 Wi-Fi 区块置灰。

**权限（Android）**：`ACCESS_WIFI_STATE`、`CHANGE_WIFI_STATE`，读取 SSID 还需要
`NEARBY_WIFI_DEVICES`（13+）或 `ACCESS_FINE_LOCATION`（12 及以下，13+ 也一并申请作兜底）。
首次使用请在设置页点「授权」。

**票据保护**（容易踩的坑）

- 一个 Wi-Fi 连接周期**只自动登录一次**，不会反复 login。重复 `esf_login` 会先
  `term` 掉服务端会话再重新取票，票据作废后保活会连环失败。
- 已有会话时连上目标 Wi-Fi **什么都不做**，沿用现有票据；
  断网重连的恢复交给核心保活线程自己退避重试（`keep_retry*`）。
- 目标 Wi-Fi 断开时**不会**自动登出、也不会停止保活，会话与票据原样保留，
  只写一条日志。

## 日志

- 文件：应用支持目录下的 `logs/app.log`，超过 2 MB 轮转，保留 `app.log.1`–`app.log.5`。
- 内存里保留最近 2000 条，供日志页实时查看。
- 日志页默认只显示 **INFO** 及以上级别；切换级别会写入配置（`ui.logLevel`），
  重启后保持。
- 级别只影响**展示**：文件和导出始终包含全部级别（含 DEBUG），方便排障。
- 「导出」把 `app.log.5 → app.log` 全部合并写成一个文件：
  - Windows：`<下载目录>/esurfing/esurfing-log-<时间>.log`
  - Android：`Android/data/<包名>/files/logs/esurfing-log-<时间>.log`
  - 找不到上述目录时回落到应用支持目录的 `exports/`；导出后弹窗显示完整路径，可复制。

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
- Wi-Fi 联动是实验性功能，只在 Android 生效；Windows 侧未实现，
  Android 10+ 也无法让 App 自己开关 Wi-Fi 或静默连接 SSID。
- macOS / iOS：见后续 Apple 分支（`en0` 出口、iOS 网关探测、静态链接、
  Keychain 与侧载证书等）。
