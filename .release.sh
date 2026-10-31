#!/usr/bin/env bash
# Release configuration for ggrel / grel / gemini-release.

if [[ -f "./scripts/config.sh" ]]; then
    # shellcheck source=./scripts/config.sh
    source "./scripts/config.sh"
fi

APP_NAME="${APP_NAME:-Minimal Notepad}"

# Pre-release verification command
TEST_CMD="make test"

# Build command executed after updating VERSION
BUILD_CMD="make dmg"

# Release assets to attach to the GitHub release
RELEASE_ASSETS=(
    "build/${APP_NAME}-\${version}.dmg"
)
