#!/usr/bin/env bash
# 生成通用和分架构 Android 侧载包。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

abis=(arm64-v8a armeabi-v7a x86_64)
output=build/app/outputs/flutter-apk
version="$(sed -n 's/^version: *//p' pubspec.yaml)"
mkdir -p dist

flutter build apk --release
cp "$output/app-release.apk" "dist/esurfing-app-android-$version.apk"

flutter build apk --release --split-per-abi
for abi in "${abis[@]}"; do
  cp "$output/app-$abi-release.apk" "dist/esurfing-app-android-$abi-$version.apk"
done
