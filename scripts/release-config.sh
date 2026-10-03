# Sourced by the packaging scripts. A rename touches this file, plus the
# SwiftPM product name in Package.swift when EXECUTABLE_NAME changes.

# Display name: .app bundle, DMG volume, CFBundleName, artifact prefix.
APP_NAME=${APP_NAME:-Stillbreak}
# SwiftPM executable product built by `swift build` (see Package.swift).
EXECUTABLE_NAME=${EXECUTABLE_NAME:-Stillbreak}
BUNDLE_ID=${BUNDLE_ID:-com.vladimirli.Stillbreak}
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
# CFBundleVersion: the GitHub Actions run number, which GitHub serializes and
# increments for every run of the release workflow, so published builds get
# unique, increasing numbers. Local builds have no shared sequence and default
# to 0; they are not for distribution. BUILD_NUMBER overrides either; a manual
# override is validated as numeric but its uniqueness is the caller's job.
# Exported so child scripts reuse the same value.
BUILD_NUMBER=${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-0}}
if ! printf '%s' "$BUILD_NUMBER" | grep -Eq '^[0-9]+$'; then
    printf 'Invalid BUILD_NUMBER "%s"; expected digits only\n' "$BUILD_NUMBER" >&2
    exit 1
fi
export BUILD_NUMBER

APP="$ROOT/.build/$APP_NAME.app"
DIST="$ROOT/dist"
