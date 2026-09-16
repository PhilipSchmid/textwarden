#!/bin/sh
set -eu

EXTENSION="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/BrowserExtension"
python3 "${PROJECT_DIR}/Scripts/browser-extension.py" prepare "${PROJECT_DIR}/Info.plist" "$EXTENSION" --browser chromium
python3 "${PROJECT_DIR}/Scripts/browser-extension.py" prepare "${PROJECT_DIR}/Info.plist" "${EXTENSION}-Firefox" --browser firefox

OUTPUT="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/MacOS/TextWardenBrowserHost"
WORK="${DERIVED_FILE_DIR}/browser-host"
mkdir -p "$WORK" "$(dirname "$OUTPUT")"
for ARCH in $ARCHS; do
    /usr/bin/xcrun swiftc -O -target "${ARCH}-apple-macosx14.0" \
        "${PROJECT_DIR}/Sources/Browser/BrowserMessage.swift" \
        "${PROJECT_DIR}/Sources/Browser/BrowserSocket.swift" \
        "${PROJECT_DIR}/BrowserNativeHost/main.swift" \
        -o "${WORK}/${ARCH}"
done
set --
for ARCH in $ARCHS; do set -- "$@" "${WORK}/${ARCH}"; done
/usr/bin/lipo -create "$@" -output "$OUTPUT"
if [ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ]; then
    /usr/bin/codesign --force --options runtime --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$OUTPUT"
fi
