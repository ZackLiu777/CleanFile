#!/bin/sh

set -eu

# LAME 3.100.3 is distributed without its matching dSYM. Generate the bundle
# from the exact processed framework binary so App Store Connect can match its
# Mach-O UUID when an archive is uploaded.
if [ "${ACTION:-}" != "install" ] || [ "${PLATFORM_NAME:-}" != "iphoneos" ]; then
    exit 0
fi

lame_binary="${BUILT_PRODUCTS_DIR}/LAME.framework/LAME"
lame_dsym="${DWARF_DSYM_FOLDER_PATH}/LAME.framework.dSYM"

if [ ! -f "$lame_binary" ]; then
    echo "error: LAME binary not found at $lame_binary"
    exit 1
fi

binary_uuid="$(xcrun dwarfdump --uuid "$lame_binary" | awk '{print $2}')"

if [ -d "$lame_dsym" ]; then
    existing_dsym_uuid="$(xcrun dwarfdump --uuid "$lame_dsym" 2>/dev/null | awk '{print $2}')"
    if [ -n "$binary_uuid" ] && [ "$binary_uuid" = "$existing_dsym_uuid" ]; then
        echo "Existing LAME.framework.dSYM matches UUID $binary_uuid"
        exit 0
    fi
fi

rm -rf "$lame_dsym"
xcrun dsymutil "$lame_binary" -o "$lame_dsym"

dsym_uuid="$(xcrun dwarfdump --uuid "$lame_dsym" | awk '{print $2}')"

if [ -z "$binary_uuid" ] || [ "$binary_uuid" != "$dsym_uuid" ]; then
    echo "error: Generated LAME dSYM UUID does not match the framework binary"
    exit 1
fi

echo "Generated LAME.framework.dSYM for UUID $binary_uuid"
