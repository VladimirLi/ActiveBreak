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
# CFBundleVersion: microseconds since the Unix epoch, so every build gets a
# unique, increasing number regardless of git history or tag, even for builds
# started within the same second. Override with a numeric BUILD_NUMBER. Exported
# so child scripts reuse the same value.
BUILD_NUMBER=${BUILD_NUMBER:-$(perl -MTime::HiRes=gettimeofday -e '($s, $u) = gettimeofday; printf "%d%06d", $s, $u')}
if ! printf '%s' "$BUILD_NUMBER" | grep -Eq '^[0-9]+$'; then
    printf 'Invalid BUILD_NUMBER "%s"; expected digits only\n' "$BUILD_NUMBER" >&2
    exit 1
fi
export BUILD_NUMBER

APP="$ROOT/.build/$APP_NAME.app"
DIST="$ROOT/dist"
