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
  local abi build_dir triple host_tag llvm_strip ndk_lib
  host_tag="$(ls -d "$NDK/toolchains/llvm/prebuilt/"* 2>/dev/null | head -1)"
  llvm_strip="$host_tag/bin/llvm-strip"
  ndk_lib="$host_tag/sysroot/usr/lib"
  for spec in "arm64-v8a:aarch64-linux-android" \
              "armeabi-v7a:arm-linux-androideabi" \
              "x86_64:x86_64-linux-android"; do
    abi="${spec%%:*}"
    triple="${spec##*:}"
    build_dir="/tmp/esf-build-$abi"
    echo "==> Android $abi"
    cmake -S "$CORE" -B "$build_dir" \
      -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
      -DANDROID_ABI="$abi" \
      -DANDROID_PLATFORM="android-$API" \
      -DANDROID_STL=c++_shared \
      -DCMAKE_BUILD_TYPE=Release \
      -DESURFING_LTO=OFF \
      -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-z,max-page-size=16384" >/dev/null
    cmake --build "$build_dir" -j"$(nproc)" >/dev/null
    mkdir -p "$ANDROID_OUT/$abi"
    cp "$build_dir/lib/esurfing.so" "$ANDROID_OUT/$abi/libesurfing.so"
    echo "    -> $ANDROID_OUT/$abi/libesurfing.so"

    # Flutter 只打包 jniLibs 下的库，不会自动带上 NDK 的 libc++_shared.so；
    # 不带就会在 dlopen("libesurfing.so") 时报 library "libc++_shared.so" not found。
    # NDK 自带的这份是未 strip 的（约 9 MB），strip 后约 1 MB。
    if [[ ! -f "$ndk_lib/$triple/libc++_shared.so" ]]; then
      echo "找不到 NDK 的 libc++_shared.so：$ndk_lib/$triple" >&2
      return 1
    fi
    "$llvm_strip" --strip-unneeded \
      -o "$ANDROID_OUT/$abi/libc++_shared.so" \
      "$ndk_lib/$triple/libc++_shared.so"
    chmod 644 "$ANDROID_OUT/$abi/libc++_shared.so"
    echo "    -> $ANDROID_OUT/$abi/libc++_shared.so ($(stat -c%s "$ANDROID_OUT/$abi/libc++_shared.so") 字节)"

    readelf -lW "$ANDROID_OUT/$abi/libesurfing.so" |
      grep -q '0x4000' || echo "    警告：未检测到 16 KB 页对齐" >&2
    readelf -dW "$ANDROID_OUT/$abi/libesurfing.so" | grep -q 'libc++_shared' ||
      echo "    提示：$abi 未动态依赖 libc++_shared.so（静态链接？）" >&2
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
