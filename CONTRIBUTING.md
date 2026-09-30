# Contributing

1. Keep the app native to macOS and dependency-free.
2. Add or update focused reducer tests for timing behavior.
3. Run `swift test`, `swift build -c release`, and
   `./scripts/package-app.sh`.
4. Keep privacy claims and `docs/SPEC.md` aligned with behavior.

Use small commits and do not include generated `.build` artifacts.

## Releases

Releases are built by `.github/workflows/release.yml`. Pushing a tag such as
`v1.2.3` (or `v1.2.3-rc1` for a pre-release) builds a universal app, publishes a
GitHub Release with generated notes, attaches the DMG and zip, and lists their
SHA-256 checksums in the notes. The tag sets `CFBundleShortVersionString`; the
build time (microseconds since the Unix epoch, or a numeric `BUILD_NUMBER`
override) sets `CFBundleVersion`, so it is unique and increasing for every build. Run the workflow manually (Actions >
Release > Run workflow) to build the artifacts without publishing.

The app name, bundle ID, artifact prefix and signing identity (`SIGN_IDENTITY`,
ad-hoc by default) are in `scripts/release-config.sh`. Builds are not notarized.
