#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/.." && pwd)"
cd "$project_dir"

source "${script_dir}/config.sh"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/$(printf "%s" "$APP_NAME" | tr "[:upper:]" "[:lower:]")"
mkdir -p "$cache_dir"

sdk_file="${cache_dir}/sdk_path.tmp"
xcrun --show-sdk-path >"$sdk_file" 2>/dev/null
if [[ ! -s "$sdk_file" ]]; then
    rm -f "$sdk_file"
    printf '%s\n' "Error: Failed to obtain SDK path from xcrun" >&2
    exit 1
fi
IFS= read -r sdk_path <"$sdk_file"
rm -f "$sdk_file"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s\n' "Error: VERSION file must contain a version like 1.2.3 (found '${VERSION}')" >&2
    exit 1
fi

# Every build increments BUILD_NUMBER; the file is the single source of truth.
if [[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    build_number=$((10#$BUILD_NUMBER + 1))
else
    build_number=1
fi
printf '%s\n' "$build_number" >"$build_num_file"
export BUILD_NUMBER="$build_number"

build_dir="build"
app_name="${APP_NAME}"
bundle_id="${BUNDLE_ID}"
app_dir="${build_dir}/${app_name}.app"
contents_dir="${app_dir}/Contents"
macos_dir="${contents_dir}/MacOS"
resources_dir="${contents_dir}/Resources"

mkdir -p "$macos_dir" "$resources_dir"

if [[ -d "Resources" ]]; then
    cp -R Resources/. "${resources_dir}/"
fi

if [[ -f "VERSION" ]]; then
    cp "VERSION" "${resources_dir}/VERSION"
fi
printf '%s\n' "$build_number" >"${resources_dir}/BUILD_NUMBER"

sources=()
while IFS= read -r file; do
    sources+=("$file")
done < <(find Sources -type f -name "*.swift" | sort)

# Universal binary: one slice per architecture, joined with lipo, so the app runs natively on
# Apple silicon and Intel Macs. BUILD_ARCHS can narrow this (e.g. BUILD_ARCHS=x86_64 for a quick local build).
archs=(${BUILD_ARCHS:-arm64 x86_64})
slices_dir="${build_dir}/slices"
mkdir -p "$slices_dir"
slices=()
for arch in "${archs[@]}"; do
    printf '%s\n' "Compiling ${app_name} v${VERSION} (Build ${BUILD_NUMBER}) for ${arch} (${#sources[@]} source files)..."
    swiftc -sdk "$sdk_path" \
        -target "${arch}-apple-macos${MIN_MACOS_VERSION}" \
        -O \
        -whole-module-optimization \
        -Xlinker -dead_strip \
        "${sources[@]}" \
        -o "${slices_dir}/${app_name}-${arch}"
    slices+=("${slices_dir}/${app_name}-${arch}")
done
lipo -create "${slices[@]}" -output "${macos_dir}/${app_name}"
printf '%s\n' "Architectures: $(lipo -archs "${macos_dir}/${app_name}")"

printf '%s\n' "Generating ${app_name} Info.plist..."
cat <<EOF >"${contents_dir}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${app_name}</string>
    <key>CFBundleIdentifier</key>
    <string>${bundle_id}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${app_name}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS_VERSION}</string>
    <key>LSUIElement</key>
    <${LS_UI_ELEMENT}/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>
    <string>${COPYRIGHT}</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Plain Text</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.plain-text</string>
                <string>public.data</string>
            </array>
            <key>NSDocumentClass</key>
            <string>TextDocument</string>
            <key>CFBundleTypeIconFile</key>
            <string>AppIcon</string>
        </dict>
    </array>
</dict>
</plist>
EOF

# macOS remembers granted permissions (TCC) against the app's designated requirement (DR).
#
# - SIGN_IDENTITY set (e.g. "Developer ID Application: Name (TEAMID)"): real signing with the
#   hardened runtime. The DR includes the team ID, so no one else can satisfy it. Use for releases.
# - Otherwise ad-hoc. The default ad-hoc DR is the build's cdhash: only this exact binary satisfies it,
#   so permissions are re-requested after each rebuild, but no other program can inherit them.
# - LOCAL_DEV_SIGNING=1 (set by `make run`): ad-hoc with the DR pinned to the bundle ID, so permissions
#   survive rebuilds. Any program ad-hoc signed with the same identifier would also satisfy that DR and
#   inherit the permissions, so this is refused for anything that gets distributed (build_dmg.sh).
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    printf '%s\n' "Signing ${app_name} bundle with '${SIGN_IDENTITY}' (hardened runtime)..."
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$app_dir"
elif [[ "${LOCAL_DEV_SIGNING:-0}" == 1 ]]; then
    designated_requirement="designated => identifier \"${bundle_id}\""
    printf '%s\n' "Signing ${app_name} bundle (ad-hoc, local development only: ${designated_requirement})..."
    codesign --force --sign - --requirements "=${designated_requirement}" "$app_dir"

    signed_requirement="$(codesign -d -r- "$app_dir" 2>&1 | grep '^designated => ' || true)"
    if [[ "$signed_requirement" != "$designated_requirement" ]]; then
        printf '%s\n' "Error: Unexpected designated requirement '${signed_requirement}'; permissions would not persist." >&2
        exit 1
    fi
else
    printf '%s\n' "Signing ${app_name} bundle (ad-hoc)..."
    codesign --force --sign - "$app_dir"
fi
codesign --verify --strict "$app_dir"

printf '%s\n' "Refreshing macOS LaunchServices cache..."
touch "$app_dir"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R "$app_dir" >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true

printf '%s\n' "✅ Build complete:"
printf '%s\n' "   - ${app_dir}"
