#!/bin/sh
set -eu

source_library="${PROJECT_DIR}/../packages/esurfing_native/macos/libesurfing.dylib"
destination="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/libesurfing.dylib"
if [ ! -f "$source_library" ]; then
  echo "error: Build the universal backend first: tool/build_native.sh macos" >&2
  exit 1
fi
archs="$(/usr/bin/lipo -archs "$source_library")"
case "$archs" in
  *arm64*x86_64*|*x86_64*arm64*) ;;
  *) echo "error: universal backend missing arm64/x86_64 slices: $archs" >&2; exit 1 ;;
esac
/bin/mkdir -p "$(dirname "$destination")"
/bin/cp -f "$source_library" "$destination"
/bin/chmod u+w "$destination"
if [ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
  /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$destination"
fi
