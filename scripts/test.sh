#!/usr/bin/env bash
# Compiles the app sources together with Tests/ into one executable and runs it.
# Works with the macOS system bash (3.2).

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/.." && pwd)"
cd "$project_dir"

source "${script_dir}/config.sh"

if ! sdk_path="$(xcrun --show-sdk-path 2>/dev/null)" || [[ -z "$sdk_path" ]]; then
    printf '%s\n' "Error: Failed to locate macOS SDK via xcrun" >&2
    exit 1
fi

# A private, unpredictable directory: a fixed name under /tmp could be pre-created or swapped by another user.
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/RunSwiftTests.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT INT TERM
test_bin="${work_dir}/RunSwiftTests"

# The test binary embeds the app's Info.plist, so NSDocumentController knows the document types,
# under its own bundle identifier, so UserDefaults written by tests never touch the real app's settings.
test_bundle_id="${BUNDLE_ID}.tests"
test_plist="${work_dir}/Info.plist"
cp Resources/Info.plist "$test_plist"
plutil -replace CFBundleIdentifier -string "$test_bundle_id" "$test_plist"

# App sources, excluding the entry point
sources=()
while IFS= read -r file; do
    if ! grep -q "@main" "$file" 2>/dev/null && [[ "$(basename "$file")" != "main.swift" ]]; then
        sources+=("$file")
    fi
done < <(find Sources -type f -name "*.swift" | sort)

tests=()
while IFS= read -r file; do
    tests+=("$file")
done < <(find Tests -type f -name "*.swift" | sort)

if [[ ${#tests[@]} -eq 0 ]]; then
    printf '%s\n' "Error: No test files found under Tests" >&2
    exit 1
fi

printf '%s\n' "Compiling unit test suite..."
swiftc -sdk "$sdk_path" -Onone \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$test_plist" \
    "${sources[@]}" \
    "${tests[@]}" \
    -o "$test_bin"

test_status=0
TEST_BUNDLE_ID="$test_bundle_id" "$test_bin" "$@" || test_status=$?

# Drop the defaults domain the run wrote to.
defaults delete "$test_bundle_id" >/dev/null 2>&1 || true

if [[ "$test_status" -ne 0 ]]; then
    printf '%s\n' "Error: Swift unit tests failed with status ${test_status}" >&2
    exit "$test_status"
fi
