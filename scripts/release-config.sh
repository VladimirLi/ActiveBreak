# Sourced by the packaging scripts. A rename touches this file, plus the
# SwiftPM product name in Package.swift when EXECUTABLE_NAME changes.

# Display name: .app bundle, DMG volume, CFBundleName, artifact prefix.
APP_NAME=${APP_NAME:-ActiveBreak}
# SwiftPM executable product built by `swift build` (see Package.swift).
EXECUTABLE_NAME=${EXECUTABLE_NAME:-ActiveBreak}
BUNDLE_ID=${BUNDLE_ID:-com.vladimirli.ActiveBreak}
ARTIFACT_PREFIX=${ARTIFACT_PREFIX:-$APP_NAME}
MIN_MACOS=${MIN_MACOS:-14.0}

# "-" is an ad-hoc signature. Set to a "Developer ID Application: ..." identity
# to sign for distribution; hardened runtime and a timestamp are then enabled.
SIGN_IDENTITY=${SIGN_IDENTITY:--}

# Release version: VERSION (e.g. 1.2.3 or 1.2.3-rc1, optional leading "v"),
# defaulting to 0.0.0-dev for local builds. CI passes the pushed v* tag.
VERSION=${VERSION:-0.0.0-dev}
VERSION=${VERSION#v}
if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'; then
    printf 'Invalid VERSION "%s"; expected MAJOR.MINOR.PATCH[-suffix]\n' "$VERSION" >&2
    exit 1
fi
# CFBundleShortVersionString allows digits and periods only, so drop any suffix.
BUNDLE_SHORT_VERSION=${VERSION%%-*}
# CFBundleVersion: monotonically increasing; commit count unless overridden.
BUILD_NUMBER=${BUILD_NUMBER:-$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)}

APP="$ROOT/.build/$APP_NAME.app"
DIST="$ROOT/dist"
