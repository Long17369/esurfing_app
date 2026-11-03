#!/usr/bin/env bash
# 构建 esurfing_c 原生后端：
#   Android -> android/app/src/main/jniLibs/<abi>/libesurfing.so
#   Windows -> packages/esurfing_native/windows/esurfing.dll （需要 MinGW）
#
# 用法：tool/build_native.sh [android|windows|all]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE="${ESURFING_C_DIR:-$ROOT/../esurfing_c}"
TARGET="${1:-all}"

ANDROID_OUT="$ROOT/android/app/src/main/jniLibs"
WINDOWS_OUT="$ROOT/packages/esurfing_native/windows"
NDK="${ANDROID_NDK_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}/ndk/28.2.13676358}"
API=24

build_android() {
  if [[ ! -f "$NDK/build/cmake/android.toolchain.cmake" ]]; then
    echo "找不到 NDK：$NDK（可设置 ANDROID_NDK_HOME）" >&2
    return 1
  fi
  local abi build_dir
  for spec in "arm64-v8a:arm64-v8a" "armeabi-v7a:armeabi-v7a" "x86_64:x86_64"; do
    abi="${spec%%:*}"
    build_dir="/tmp/esf-build-$abi"
    echo "==> Android $abi"
    cmake -S "$CORE" -B "$build_dir" \
      -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
      -DANDROID_ABI="$abi" \
      -DANDROID_PLATFORM="android-$API" \
      -DANDROID_STL=c++_static \
      -DCMAKE_BUILD_TYPE=Release \
      -DESURFING_LTO=OFF \
      -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-z,max-page-size=16384" >/dev/null
    cmake --build "$build_dir" -j"$(nproc)" >/dev/null
    mkdir -p "$ANDROID_OUT/$abi"
    cp "$build_dir/lib/esurfing.so" "$ANDROID_OUT/$abi/libesurfing.so"
    echo "    -> $ANDROID_OUT/$abi/libesurfing.so"
    readelf -lW "$ANDROID_OUT/$abi/libesurfing.so" |
      grep -q '0x4000' || echo "    警告：未检测到 16 KB 页对齐" >&2
    # Flutter 不会打包 NDK 的 libc++_shared.so，动态链接会在 dlopen 时报
    # 「library "libc++_shared.so" not found」，所以必须静态链（-DANDROID_STL=c++_static）。
    if readelf -dW "$ANDROID_OUT/$abi/libesurfing.so" | grep -q 'libc++_shared'; then
      echo "    错误：$abi 仍在动态依赖 libc++_shared.so" >&2
      return 1
    fi
  done
}

build_windows() {
  local cxx cc
  cxx="$(command -v x86_64-w64-mingw32-g++ || true)"
  cc="$(command -v x86_64-w64-mingw32-gcc || true)"
  if [[ -z "$cxx" || -z "$cc" ]]; then
    echo "跳过 Windows：未安装 MinGW（x86_64-w64-mingw32-g++）。" >&2
    echo "在 MSYS2 下执行：pacman -S mingw-w64-x86_64-gcc mingw-w64-x86_64-cmake" >&2
    return 0
  fi
  local build_dir="/tmp/esf-build-windows"
  echo "==> Windows x64"
  cmake -S "$CORE" -B "$build_dir" \
    -DCMAKE_SYSTEM_NAME=Windows \
    -DCMAKE_C_COMPILER="$cc" \
    -DCMAKE_CXX_COMPILER="$cxx" \
    -DCMAKE_BUILD_TYPE=Release \
    -DESURFING_LTO=OFF >/dev/null
  cmake --build "$build_dir" -j"$(nproc)" >/dev/null
  mkdir -p "$WINDOWS_OUT"
  cp "$build_dir/lib/esurfing.dll" "$WINDOWS_OUT/esurfing.dll"
  echo "    -> $WINDOWS_OUT/esurfing.dll"
}

case "$TARGET" in
  android) build_android ;;
  windows) build_windows ;;
  all) build_android; build_windows ;;
  *) echo "用法：$0 [android|windows|all]" >&2; exit 2 ;;
esac
