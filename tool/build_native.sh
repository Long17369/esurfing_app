#!/usr/bin/env bash
# 构建 esurfing_c 原生后端：
#   Android -> android/app/src/main/jniLibs/<abi>/libesurfing.so
#   Windows -> packages/esurfing_native/windows/esurfing.dll （需要 MinGW）
#
# 用法：tool/build_native.sh [android|windows|macos|all]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE="${ESURFING_C_DIR:-$ROOT/../esurfing_c}"
TARGET="${1:-all}"
# 构建目录默认放 /tmp；CI（MSYS2）里必须传 Windows 形式（cygpath -m），
# 否则 cmake.exe 写的是 C:/tmp/...，而 bash 的 cp 看的是 MSYS 的 /tmp。
BUILD_BASE="${ESURFING_BUILD_BASE:-/tmp}"
# MSYS2 里 cmake/ninja 是原生程序，只认 D:/... 形式的路径。
# CI 传进来的 $GITHUB_WORKSPACE / $RUNNER_TEMP 是 Windows 原生写法（D:\a\...），先统一成 /。
if command -v cygpath >/dev/null 2>&1; then
  CORE="$(cygpath -m "${CORE//\\//}")"
  BUILD_BASE="$(cygpath -m "${BUILD_BASE//\\//}")"
fi
JOBS="${ESURFING_BUILD_JOBS:-$(nproc 2>/dev/null || echo 4)}"

ANDROID_OUT="$ROOT/android/app/src/main/jniLibs"
WINDOWS_OUT="$ROOT/packages/esurfing_native/windows"
MACOS_OUT="$ROOT/packages/esurfing_native/macos"
NDK="${ANDROID_NDK_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}/ndk/28.2.13676358}"
API="${ESURFING_ANDROID_API:-24}"

build_android() {
  if [[ ! -f "$NDK/build/cmake/android.toolchain.cmake" ]]; then
    echo "找不到 NDK：$NDK（可设置 ANDROID_NDK_HOME）" >&2
    return 1
  fi
  local abi build_dir library headers dynamic line alignment found_load
  for spec in "arm64-v8a" "armeabi-v7a" "x86_64"; do
    abi="$spec"
    build_dir="$BUILD_BASE/esf-build-$abi"
    echo "==> Android $abi"
    # 不传 -DANDROID_STL：CMake 的 CMAKE_ANDROID_STL_TYPE 默认就是 c++_static，
    # 也就是 C++ 运行时静态链进 libesurfing.so，只有一个 .so、无需 libc++_shared.so。
    # 特别注意别传 -DANDROID_STL=c++_shared —— 那会让 dlopen 时报
    # library "libc++_shared.so" not found（Flutter 不会打包 NDK 的这份）。
    cmake -S "$CORE" -B "$build_dir" \
      -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
      -DANDROID_ABI="$abi" \
      -DANDROID_PLATFORM="android-$API" \
      -UANDROID_STL -UCMAKE_ANDROID_STL_TYPE \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_TESTING=OFF \
      -DESURFING_LTO=OFF \
      -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-z,max-page-size=16384" >/dev/null
    cmake --build "$build_dir" --target esurfing_capi_shared -j"$JOBS" >/dev/null
    library="$build_dir/lib/esurfing.so"
    headers="$(readelf -lW "$library")"
    found_load=false
    while IFS= read -r line; do
      if [[ "$line" =~ ^[[:space:]]*LOAD[[:space:]] ]]; then
        found_load=true
        alignment="${line##* }"
        if [[ ! "$alignment" =~ ^0x[0-9a-fA-F]+$ ]] || (( alignment < 0x4000 )); then
          echo "错误：$abi 的 LOAD 段未满足 16 KB 页对齐：$alignment" >&2
          return 1
        fi
      fi
    done <<< "$headers"
    if [[ "$found_load" != true ]]; then
      echo "错误：$abi 未检测到 ELF LOAD 段" >&2
      return 1
    fi
    dynamic="$(readelf -dW "$library")"
    if [[ "$dynamic" == *libc++_shared* ]]; then
      echo "    错误：$abi 动态依赖 libc++_shared.so，App 内会 dlopen 失败。" >&2
      echo "    多半是构建目录里残留了 -DANDROID_STL=c++_shared，删掉 $build_dir 重跑。" >&2
      return 1
    fi
    mkdir -p "$ANDROID_OUT/$abi"
    cp "$library" "$ANDROID_OUT/$abi/libesurfing.so"
    echo "    -> $ANDROID_OUT/$abi/libesurfing.so"
    rm -f "$ANDROID_OUT/$abi/libc++_shared.so"
  done
}

build_windows() {
  local cxx cc
  cxx="$(command -v x86_64-w64-mingw32-g++ || true)"
  cc="$(command -v x86_64-w64-mingw32-gcc || true)"
  if [[ -z "$cxx" || -z "$cc" ]]; then
    if [[ "${1:-}" == allow_skip ]]; then
      echo "跳过 Windows：未安装 MinGW（x86_64-w64-mingw32-g++）。" >&2
    else
      echo "无法构建 Windows：未安装 MinGW（x86_64-w64-mingw32-g++）。" >&2
    fi
    echo "在 MSYS2 下执行：pacman -S mingw-w64-x86_64-gcc mingw-w64-x86_64-cmake" >&2
    [[ "${1:-}" == allow_skip ]] && return 0
    return 1
  fi
  if command -v cygpath >/dev/null 2>&1; then
    [[ ! -f "$cxx.exe" ]] || cxx="$cxx.exe"
    [[ ! -f "$cc.exe" ]] || cc="$cc.exe"
    cxx="$(cygpath -m "$cxx")"
    cc="$(cygpath -m "$cc")"
  fi
  local build_dir="$BUILD_BASE/esf-build-windows"
  echo "==> Windows x64"
  # 生成器必须是 Ninja：CMake 在 Windows 上默认挑 Visual Studio（配 GCC 直接失败），
  # MinGW Makefiles 又会在 MSYS2 里报「sh.exe was found in your PATH」。
  # 显式选择 MinGW，避免在 Linux 交叉编译时误用宿主 GCC。
  if ! command -v ninja >/dev/null 2>&1; then
    echo "缺少 ninja：pacman -S mingw-w64-x86_64-ninja（MinGW Makefiles 在 MSYS2 里会因 PATH 里有 sh.exe 而拒绝配置）" >&2
    return 1
  fi
  cmake -S "$CORE" -B "$build_dir" -G Ninja \
    -DCMAKE_SYSTEM_NAME=Windows \
    -DCMAKE_C_COMPILER="$cc" \
    -DCMAKE_CXX_COMPILER="$cxx" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_TESTING=OFF \
    -DESURFING_LTO=OFF >/dev/null
  cmake --build "$build_dir" --target esurfing_capi_shared -j"$JOBS" >/dev/null
  mkdir -p "$WINDOWS_OUT"
  # Windows 的 DLL 是 RUNTIME 产物，capi/CMakeLists.txt 把它放在 build/bin；
  # Linux 的 .so 才是 LIBRARY 产物，放在 build/lib。两个都找一遍。
  local dll=""
  for candidate in "$build_dir/bin/esurfing.dll" "$build_dir/lib/esurfing.dll"; do
    if [[ -f "$candidate" ]]; then dll="$candidate"; break; fi
  done
  if [[ -z "$dll" ]]; then
    echo "找不到 esurfing.dll（看过 $build_dir/bin 与 $build_dir/lib）" >&2
    return 1
  fi
  cp "$dll" "$WINDOWS_OUT/esurfing.dll"
  echo "    -> $WINDOWS_OUT/esurfing.dll"
}

build_macos() {
  if [[ "$(uname -s)" != Darwin ]]; then
    echo "macOS 构建需要 macOS/Xcode 主机" >&2
    return 1
  fi
  local build_dir="$BUILD_BASE/esf-build-macos"
  local library="$build_dir/lib/libesurfing.dylib"
  local dependencies dependency
  cmake -S "$CORE" -B "$build_dir" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    '-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64' \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DESURFING_ZLIB=bundled -DESURFING_ZLIB_STATIC=ON \
    -DBUILD_TESTING=OFF -DESURFING_LTO=OFF
  cmake --build "$build_dir" --target esurfing_capi_shared -j"$JOBS"
  archs="$(lipo -archs "$library")"
  [[ "$archs" == *arm64* && "$archs" == *x86_64* ]] || {
    echo "macOS dylib 缺少 arm64/x86_64 架构：$archs" >&2
    return 1
  }
  dependencies="$(otool -L "$library")"
  echo "$dependencies"
  while IFS= read -r dependency; do
    case "$dependency" in
      @rpath/libesurfing*.dylib|/usr/lib/*|/System/Library/*) ;;
      *) echo "不允许的 macOS 动态库依赖：$dependency" >&2; return 1 ;;
    esac
  done < <(printf '%s\n' "$dependencies" | awk '/^[[:space:]]+/{print $1}')
  mkdir -p "$MACOS_OUT"
  cp -L "$library" "$MACOS_OUT/libesurfing.dylib"
  git -C "$CORE" rev-parse HEAD > "$MACOS_OUT/backend-sha.txt"
  echo "    -> $MACOS_OUT/libesurfing.dylib"
}

case "$TARGET" in
  android) build_android ;;
  windows) build_windows ;;
  macos) build_macos ;;
  all)
    if [[ "$(uname -s)" == Darwin ]]; then
      build_macos
    else
      build_android
      build_windows allow_skip
    fi
    ;;
  *) echo "用法：$0 [android|windows|macos|all]" >&2; exit 2 ;;
esac
