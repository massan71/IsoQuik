# Changelog

All notable changes to IsoQuik are listed here. Versions follow [semantic versioning](https://semver.org).

## [1.2.0] (build 3) — 2026-11-07

### Added
- Boot check for the selected image: partition table (MBR/GPT), El Torito boot catalog and UEFI loaders
  (`BOOTX64.EFI`, `BOOTAA64.EFI`…). The image panel shows how it boots and warns when a raw copy will not
  boot from USB (e.g. Windows ISOs), when the image is not bootable, or when it cannot start this Mac.
- SHA-256 of the selected image, with a field to compare it against a published checksum.
- Throughput and estimated time remaining while writing and verifying.
- Stop button (⌘.) for writing (with confirmation) and verification.
- Notification and Dock attention request when an operation finishes in the background; percentage on the Dock icon.
- Console: timestamps, automatic scrolling and a Copy button.
- Drive rows show current volume names and an SD card icon when the drive looks like an SD card.

### Changed
- The "Technical Details" panel is now called "Console".
- Quitting during a write asks for confirmation, and the window cannot be closed while an operation is running.
- The write confirmation shows the image, the drive and the volumes that will be erased.
- Write errors are shown once, in the status bar and the console, instead of an extra alert.
- More compact layout: smaller minimum window size (820×600), and the verify switch moved next to the Write button.
- Accessibility: drive rows expose their selected state and details to VoiceOver; shortcuts are shown on the buttons and in tooltips.

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
