# Changelog

All notable changes to IsoQuik are listed here. Versions follow [semantic versioning](https://semver.org).

## [1.1.0] (build 2) — 2026-11-06

### Changed
- The user interface, messages, documentation and source comments are now in English.
- The app version is shown in the header and printed by `build.sh`.

### Fixed
- Startup disk detection now resolves the physical disk behind the APFS container, so an external startup SSD can no longer be selected as a destination.
- If unmounting fails, the write is aborted instead of continuing with mounted volumes.
- Disk safety checks refuse a disk when required information is missing.
- I/O alignment uses the sector size reported by the device instead of a fixed 512 bytes.
- The drive capacity is re-checked on the opened device after authorization.
- `fsync` errors are reported.
- The device list keeps refreshing after a write finishes or fails.
- The `authopen` password wait no longer blocks a Swift concurrency thread.

## [1.0] (build 1)

- First release, in Italian.
