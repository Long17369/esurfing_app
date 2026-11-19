# 校园网助手（esurfing_app）

`esurfing_c` 的图形界面前端。Flutter 负责 UI 与状态，协议、加密、网卡与会话全部
复用 `esurfing_c` 的 C API（`include/esurfing.h`），通过 `dart:ffi` 调用。

**平台范围：Windows x64、Android、macOS 14+（Apple Silicon / Intel）。**
macOS 工程与通用原生库通过 macOS CI 构建；产物采用 ad-hoc 签名，不包含
Developer ID 签名或 Apple 公证，下载后可能被 Gatekeeper 阻止直接打开。
不要为此关闭系统安全功能。**iOS 不在支持和构建范围。**

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
- macOS：菜单栏托盘、关闭到托盘、登录时自启动、启动最小化；凭据通过当前 App 的默认 Keychain 保存，不跨 App 共享
- Windows：效率模式（EcoQoS，Win10 1709+）——窗口隐藏到托盘时把进程标记成
  后台任务，减少 CPU 占用；设置页可关（`ui.efficiencyMode`，默认开）
- Android：前台服务常驻通知、开机自启、电池优化白名单引导
- Android：隐藏后台——置于后台达到设定时长后销毁界面并从最近任务里移除，
  前台服务与保活继续，点通知重新打开（`ui.hideInBackground` / `ui.backgroundDestroyMinutes`）
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
| macOS 应用与原生库 | macOS、Xcode 26+（macOS 26 SDK）、CMake、Ninja、CocoaPods；部署目标 macOS 14 |

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
# 非 macOS：Android 三个 ABI + Windows DLL（all 无 MinGW 时跳过 Windows）
# macOS：all 只构建 macOS 通用 dylib
tool/build_native.sh all
# 只做一端
tool/build_native.sh android
tool/build_native.sh windows
# macOS 主机：通用 arm64 + x86_64 dylib
tool/build_native.sh macos
```

显式指定 `windows` 时缺少 MinGW 会失败；脚本将检测到的 MinGW 编译器显式传给
CMake，支持在 Linux 上交叉编译 DLL，避免误用宿主 GCC。

产物位置：

- Android：`android/app/src/main/jniLibs/{arm64-v8a,armeabi-v7a,x86_64}/libesurfing.so`
  （已加 `-Wl,-z,max-page-size=16384`，满足 Android 15+ 的 16 KB 页要求；
  C++ 运行时静态链在库内，不依赖 `libc++_shared.so`，`jniLibs` 里只有这一个 `.so`）
- Windows：`packages/esurfing_native/windows/esurfing.dll`
  （CMake 在 `windows/` 构建时自动安装到 exe 同目录）
- macOS：`packages/esurfing_native/macos/libesurfing.dylib`，构建 App 时嵌入
  `Contents/Frameworks`；脚本需要 macOS/Xcode，不在 Linux 上假装交叉构建成功。

> **Android 的 STL 用 CMake 默认值 `c++_static`，不要传 `-DANDROID_STL=c++_shared`。**
> 传了 `c++_shared` 后 `libesurfing.so` 会带 `NEEDED libc++_shared.so`，而 Flutter 只打包
> `jniLibs` 下的东西、不会带 NDK 那份，`dlopen` 时直接抛
> `library "libc++_shared.so" not found`。
> 静态链接后体积约 970 KB（arm64），只依赖 `libdl / libm / libc`。
>
> 构建目录的 `CMakeCache.txt` 会记住上一次的 `ANDROID_STL`，所以 `tool/build_native.sh`
> 每次配置都带 `-UANDROID_STL -UCMAKE_ANDROID_STL_TYPE` 清掉残留，并在构建后用
> `readelf -d` 校验：一旦发现依赖 `libc++_shared.so` 直接报错退出。
> 同时校验所有 ELF LOAD 段至少按 16 KB 对齐；解析工具失败、缺少 LOAD 段或
> 任一段不满足要求都会中止，不把未通过校验的当前 ABI 产物复制进 `jniLibs`。
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
flutter run -d macos       # 需要 macOS/Xcode，先构建原生 dylib

tool/package_windows.sh    # -> dist/esurfing-app-windows-x64.zip
tool/package_android.sh    # -> dist/app-<abi>-release.apk
bash tool/package_macos.sh # -> dist/esurfing-app-macos-universal-<ver>.zip
```

原生核心的离线回归入口（在 `esurfing_c` 目录运行）：

```bash
cmake -S . -B build-check -DCMAKE_BUILD_TYPE=Debug \
  -DESURFING_STDLIB_STATIC=OFF -DESURFING_LTO=OFF
cmake --build build-check -j2
ctest --test-dir build-check --output-on-failure
```

App 测试覆盖旧库能力门禁、会话释放、宿主退出、配置并发持久化和后台计时；
Linux 上还会用隔离的模拟工具验证原生构建脚本，不需要真实账号或执行发布。
Android `:app:testDebugUnitTest` 提供 Activity 生命周期、权限和通知行为测试。
这些离线测试不能替代设备上的 FlutterEngine、前台服务与原生会话全链路验证，
也不能替代 Windows/macOS 对应平台的编译和运行；iOS 不纳入测试。

## CI 与分支约定

分支：`dev` 是开发分支，**所有改动先提交到 `dev`**；`main` 只放发布快照
（`dev` 通过后再快进/合并过去）。

Tag：从 App `1.3.0` 起每次发版打 `v<semver>`（与 `pubspec.yaml` 的版本一致，
不带 `+build`，例如 `v1.3.0`），打在 `dev` 的发布提交上。`main` 上没有 workflow，
把 tag 打在 `dev` 才能让 CI 出包。

`.github/workflows/build.yml` 使用精确后端 SHA 执行以下任务：

| job | 触发 | 产物 |
|---|---|---|
| `analyze & test` | 每次 push / PR | `flutter analyze` + `flutter test` |
| `windows x64` | 每次 push / PR | MSYS2 MinGW 编 `esurfing.dll` → `flutter build windows --release` → `dist/esurfing-app-windows-x64-<ver>.zip` |
| `android apk` | 每次 push / PR | 重编三个 ABI 的 `libesurfing.so` → 用固定 release 密钥签名 `flutter build apk --release` → `dist/esurfing-app-android-<ver>.apk` |
| `macOS universal` | 每次 push / PR | 重编双架构 dylib、真实插件/桌面集成测试、通用 `.app` 压缩包（ad-hoc，未公证） |
| `release` | 仅 `v*` tag | 检查及三平台构建全部通过后才发布；`ci/**` 不创建 Release |

### 绑定的 C 库版本

C 库直接由官方 `actions/checkout` 拉（`repository` + `ref` + `path: esurfing_c`），
地址与版本都走变量，仓库里不写死：

| 变量 | 默认值 | 说明 |
|---|---|---|
| `ESURFING_C_REPO`（Actions 变量） | `<当前 owner>/esurfing_c` | C 库仓库，使用 `actions/checkout` 要求的 `owner/repo` 格式，不填 Git URL |
| `ESURFING_C_TOKEN` / `PAT_TOKEN`（Secret） | 空 | **C 库私有后必需**。fine-grained PAT 要勾上 `esurfing_c` 且给 `Contents: Read-only`：只有 `Metadata: Read`（这个权限是 PAT 自带的）时 REST API 能读，但 `git clone/fetch` 仍返回 `Repository not found.` —— GitHub 用 404 隐藏私有库，不会回 403。改 PAT 权限**不会换 token 值**，Secret 不用动，直接 Re-run |
| `ESURFING_C_DEPLOY_KEY`（Secret） | 空 | 备选：只读 Deploy Key 私钥，`ESURFING_C_REPO` 仍填 `owner/repo`，checkout 根据 `ssh-key` 使用 SSH（公钥加到 `esurfing_c` → Settings → Deploy keys，不勾 write） |
| `tool/esurfing_c.ref`（版本控制文件） | 完整 40 位提交 SHA | 所有平台 CI 共用同一后端精确提交；不再被旧 `ESURFING_C_REF` 仓库变量覆盖 |

升级 C 库的流程：先推送后端提交 → 将完整 SHA 写入 `tool/esurfing_c.ref` →
CI 重编各平台原生库与 App → 核对测试和产物中的 `build-source.txt` 等来源记录。
App 版本号按发布需要递增；验证工作分支不打 tag，也不自动发布 Release。
仅修改本地 C 库源码不会更新已入库的原生二进制，必须推送该提交并更新引用。
原生缓存按来源仓库、精确 SHA 和构建脚本区分；Release 还必须等待静态检查与测试通过。

Windows 构建用的是 MSYS2 的 mingw-w64（`esurfing_c` 的 CMake 里有 `-static`、
`--gc-sections` 等 GCC 参数，MSVC 编不了）；DLL 是 CMake 的 RUNTIME 产物，
落在 `build/bin/esurfing.dll`，`tool/build_native.sh` 会先找 `bin/` 再找 `lib/`。

### release 签名密钥（本地与 CI 共用同一份）

release APK 用固定密钥签名，任何机器打出来的包签名一致 —— 换签名后旧包**无法覆盖安装**
（系统会报签名冲突），所以密钥不能每次重建、也不能各人一份。

- 密钥库：`android/keystore/release.jks`（PKCS12，alias `esurfing`，RSA 2048，有效期 100 年），
  证书 `SHA-256 = 53:28:02:EA:DC:4C:CE:1E:3F:D4:E5:26:9C:F8:97:69:83:47:F1:4A:D2:76:11:0E:75:D6:B2:94:01:10:B8:34`。
- **这两样都不入库**：`.gitignore` 里挡了 `android/keystore/` 与 `android/key.properties`。
- Gradle 读 `android/key.properties`（`storeFile` / `storePassword` / `keyAlias` /
  `keyPassword`，格式见 `android/key.properties.example`）；没有该文件时退回 debug 签名
  并打一条 warn，方便别人 clone 后直接 `flutter run --release`。
- CI 不需要这个文件：`android apk` job 的「还原 release 签名密钥」步骤从 Secrets
  还原 keystore 与 `key.properties`，打完包再用 `apksigner --print-certs` 把实际签名者打出来。
  缺 Secrets 时：**打 tag 发版直接失败**（不允许发出 debug 签名的包），
  日常 push / PR 只打一条 warning 并退回 debug 签名 —— 免得没配密钥前流水线一直红。

换机器 / 重新配置时：

```bash
# 把 keystore 的 base64 和口令打出来，填进仓库 Settings → Secrets → Actions
tool/android_signing.sh export
# 核对 APK 是不是这套密钥签的
tool/android_signing.sh verify build/app/outputs/flutter-apk/app-release.apk
```

| Secret | 内容 |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `android/keystore/release.jks` 的 base64（单行，无换行） |
| `ANDROID_KEYSTORE_PASSWORD` | `android/key.properties` 里的 `storePassword` |

> PKCS12 不支持与 store 口令不同的 key 口令，所以 `keyPassword` 与 `storePassword` 相同，
> 只需要一个 Secret。真丢了密钥就只能换签名重新发给用户重装（无法升级覆盖）。

### 排障：android job 失败但没有任何日志

`ubuntu-latest` 只有约 14 GB 可用磁盘，而镜像里预装的 dotnet / GHC / CodeQL /
旧 NDK 本身就占 20 GB+。这套流程还要 Flutter SDK、Gradle 缓存、NDK、三个 ABI 的
`libesurfing.so` 与 APK 中间产物，**磁盘写满时 runner 直接崩，日志来不及上传**——
GitHub 上看到的就是「job 失败 + 整段日志缺失」，本地 `_diag` 里则是
`IOException: No space left on device`。

所以 android job 第一步会删掉用不到的预装件（`/usr/share/dotnet`、`/opt/ghc`、
`/usr/local/.ghcup`、`/opt/hostedtoolcache/CodeQL`、预装 NDK / `system-images` /
`emulator`）并 `docker image prune -af`，构建前后各打一次 `df -h`。
遇到莫名的失败先看这两行磁盘数字。

## 版本与兼容

App 与 `esurfing_c` **各自独立版本号**，不要求一致：

| 项目 | 位置 | 当前值 |
|---|---|---|
| App 版本 | `pubspec.yaml` 的 `version: <semver>+<build>` | `1.4.1+12` |
| 原生库 ABI | `esf_version()` 返回的 `1.2.1` | 校验主版本及安全事件接口能力 |

- App 版本只在自身有改动时递增（功能 → 次版本，修复 → 补丁号，每次发版 `+build` 加 1）；
  无需跟随原生库升级，也不要为了对齐库版本而改它。
- `+build` 映射为 Android `versionCode` / Windows 文件版本第 4 段，
  通过 `flutter` 自动注入；Windows 的 `Runner.rc` 已用 `FLUTTER_VERSION*` 宏，无需手改。
- **原生库 ABI 主版本必须匹配，且必须导出 `esf_set_owned_event_cb`**。
  不满足时显示版本或升级提示，手动登录、启动自动登录与 Wi-Fi 自动登录均不能继续；
  后台会话宿主也会在创建客户端之前再次校验。
- 原生库换新版本（同主版本）直接替换二进制即可，App 不用改版本号。
- **原生库请用 `esurfing_c` v1.2.1 及以上**：1.2.0 及更早版本在「配置里存了上次成功的
  MAC、但默认路由指向另一块网卡」的场景下，会用默认路由的 IPv4 配保存的 MAC 发报文，
  服务端按 (IP, MAC) 匹配不上，直接返回 `Error-Code = 102`（表现为「已有在线会话」
  却怎么也登不上）。App 侧对此无解，只能换原生库。
- 事件回调只使用 `esf_set_owned_event_cb`（v1.2.0 起，文本所有权转移给宿主，
  读完 `esf_free`）—— Dart 的 `NativeCallable.listener` 是异步投递，旧的
  `on_event` 约定「text 只在回调期间有效」会读到悬空指针，容错文本解码不能修复
  已释放指针。运行时探测不到安全接口时拒绝登录，必须升级原生库，不再回退。

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
`ACCESS_FINE_LOCATION`；仅获得 Android 13+ 的 `NEARBY_WIFI_DEVICES` 不等于能够读取
当前 SSID。Android 12+ 同时申请 coarse/fine 位置权限，13+ 另申请 nearby 权限。
首次使用请在设置页点「授权」，位置服务关闭时系统仍可能隐藏 SSID。

**票据保护**（容易踩的坑）

- 一个 Wi-Fi 连接周期**只自动登录一次**，不会反复 login。重复 `esf_login` 会先
  `term` 掉服务端会话再重新取票，票据作废后保活会连环失败。
- 已有会话时连上目标 Wi-Fi **什么都不做**，沿用现有票据；
  断网重连的恢复交给核心保活线程自己退避重试（`keep_retry*`）。
- 目标 Wi-Fi 断开时**不会**自动登出、也不会停止保活，会话与票据原样保留，
  只写一条日志。

## 后台运行：Android 隐藏后台 / Windows 效率模式

### Android 隐藏后台

| 字段 | 含义 | 默认 |
|---|---|---|
| `ui.hideInBackground` | 置于后台达到设定时长后销毁界面 | `false` |
| `ui.backgroundDestroyMinutes` | 后台停留多久后销毁（分钟），0 表示不销毁 | `30` |

- Dart 侧监听 `AppLifecycleState.paused/hidden` 起计时，`resumed` 立即取消；
  到点后经 `esurfing/android` channel 调 `destroyUi`，Kotlin 侧用
  `finishAndRemoveTask()` 销毁 Activity 并把它从最近任务里移除。
- `FlutterEngine` 由 `EsurfingApplication` 持有（`shouldDestroyEngineWithHost() = false`），
  所以界面销毁后 Dart isolate、`SessionHost`、前台服务与保活都不受影响；
  点通知会新建 Activity 挂回同一个 engine，界面状态直接复用，不会重新初始化。
- 计时只在后台进行，回前台立刻取消；切换到 `inactive`（下拉通知栏等）不触发。
- `hidden/paused` 连续通知共用同一截止时间，`detached` 取消旧计时，通知重开后
  可再次计时，避免 Activity 重建沿用过期任务。
- 原生端保留尚未销毁 Activity 的弱引用，直到 `onDestroy()` 才按实例解绑；
  销毁前再次确认仍在后台。权限交互只使用处于前台的 Activity。

### Windows 效率模式

- `windows/runner/flutter_window.cpp` 在 `esurfing/windows` channel 上暴露
  `setEfficiencyMode(bool)`，内部调 `SetProcessInformation(ProcessPowerThrottling,
  PROCESS_POWER_THROTTLING_EXECUTION_SPEED)`；该 API 用 `GetProcAddress` 动态探测，
  Windows 10 1709 以下返回 `false`，App 只写一条警告日志，不影响其它功能。
- 窗口隐藏到托盘 → 开启；重新显示 → 关闭。设置页开关是 `ui.efficiencyMode`（默认开）。
- 开启后任务管理器里该进程显示「效率模式」，保活与网络 I/O 照常，只是 CPU 被系统降级调度。

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
- **macOS**：解压通用包后将 `.app` 放入 Applications 等固定位置再设置自启动，
  避免移动后登录项失效。CI 使用 ad-hoc 签名而非 Developer ID，不提供 Apple 公证；
  Release 测试包不启用 App Sandbox，以便无 Team ID 时使用默认 Keychain；它不是正式
  发行安全模型，系统仍可能阻止打开。按组织政策与系统提供的批准入口处理，不关闭 Gatekeeper。
- 两端都只支持侧载，不上架应用商店。

## 已知限制

- 账号配置与 `esurfing_c` CLI 的配置文件不互通，需在 App 内重新录入。
- Android 10+ 拿不到真实 Wi-Fi MAC，App 会生成并持久化一个本地管理伪 MAC
  （首字节 `0x02`）传给 `esf_set_mac`；它只影响报文，不修改网卡。
- 同一时刻只有一个活动会话，不支持多账号同时在线。
- 暂不支持手动选择网卡、Shizuku 接入、原生后端热更新。
- Wi-Fi 联动是实验性功能，只在 Android 生效；Windows 侧未实现，
  Android 10+ 也无法让 App 自己开关 Wi-Fi 或静默连接 SSID。
- iOS：本阶段不实现，不提供工程、构建或安装包。
