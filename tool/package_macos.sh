#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != Darwin ]]; then
  echo "macOS 打包需要 macOS/Xcode 主机" >&2
  exit 1
fi
if [[ ! -f packages/esurfing_native/macos/libesurfing.dylib ]]; then
  echo "缺少原生库，请先运行 tool/build_native.sh macos" >&2
  exit 1
fi

flutter build macos --release
app="$(find build/macos/Build/Products/Release -maxdepth 1 -name '*.app' -print -quit)"
[[ -n "$app" ]] || { echo "找不到 macOS App 产物" >&2; exit 1; }
executable="$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$app/Contents/Info.plist")"
app_archs="$(lipo -archs "$app/Contents/MacOS/$executable")"
dylib_archs="$(lipo -archs "$app/Contents/Frameworks/libesurfing.dylib")"
[[ "$app_archs" == *arm64* && "$app_archs" == *x86_64* ]]
[[ "$dylib_archs" == *arm64* && "$dylib_archs" == *x86_64* ]]
otool -L "$app/Contents/Frameworks/libesurfing.dylib"
backend_sha="$(tr -d '\r\n' < packages/esurfing_native/macos/backend-sha.txt)"
expected_sha="$(tr -d '\r\n' < tool/esurfing_c.ref)"
if [[ "$backend_sha" != "$expected_sha" ]]; then
  echo "macOS 原生库来源与 tool/esurfing_c.ref 不一致，请重建" >&2
  exit 1
fi
app_sha="$(git rev-parse HEAD)"
printf 'app_sha=%s\nbackend_sha=%s\narchitecture=arm64,x86_64\nmode=release\nsigning=ad-hoc,not-notarized\n' \
  "$app_sha" "$backend_sha" > "$app/Contents/Resources/build-source.txt"

entitlements="$(mktemp)"
cleanup() { rm -f "$entitlements"; }
trap cleanup EXIT
cp macos/Runner/Release.entitlements "$entitlements"
/usr/libexec/PlistBuddy -c 'Delete :com.apple.security.get-task-allow' "$entitlements" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Delete :com.apple.security.cs.allow-jit' "$entitlements" 2>/dev/null || true

# Do not preserve an earlier debug signature. Re-sign nested code first, then
# the app bundle with the release entitlement set.
while IFS= read -r nested; do
  codesign --force --sign - "$nested"
done < <(find "$app/Contents/Frameworks" \( -type d -name '*.framework' -o -type f -name '*.dylib' \) -print)
codesign --force --sign - --entitlements "$entitlements" "$app"
codesign --verify --deep --strict --verbose=2 "$app"
entitlement_dump="$(codesign -d --entitlements :- "$app" 2>/dev/null || true)"
if grep -q 'com.apple.security.get-task-allow' <<<"$entitlement_dump"; then
  echo "error: release app still contains get-task-allow" >&2
  exit 1
fi
if grep -q 'keychain-access-groups' <<<"$entitlement_dump"; then
  echo "error: release app contains an unsupported keychain access group" >&2
  exit 1
fi
if grep -q 'com.apple.security.cs.allow-jit' <<<"$entitlement_dump"; then
  echo "error: release app still contains allow-jit" >&2
  exit 1
fi
codesign -dvv "$app" 2>&1 | grep -q 'Signature=adhoc' || {
  echo "error: expected an explicitly ad-hoc test signature" >&2
  exit 1
}
mkdir -p dist
version="$(sed -n 's/^version: *//p' pubspec.yaml)"
ditto -c -k --sequesterRsrc --keepParent "$app" "dist/esurfing-app-macos-universal-$version.zip"
