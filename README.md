# IsoQuik

**Version 1.2.1** — see [CHANGELOG.md](CHANGELOG.md).

A native macOS app (SwiftUI, universal: Apple silicon and Intel) that writes disk images to **USB drives and SD cards** in raw mode.

No external dependencies, no network access, no telemetry.

## Install

With [Homebrew](https://brew.sh):

```bash
brew install --cask massan71/tap/isoquik
```

Update with `brew upgrade --cask isoquik`. The cask lives in
[massan71/homebrew-tap](https://github.com/massan71/homebrew-tap).

Or download `IsoQuik-<version>.dmg` from the [releases](https://github.com/massan71/IsoQuik/releases),
drag the app to **Applications** and remove the quarantine flag once (the app is not notarized):

```bash
xattr -dr com.apple.quarantine /Applications/IsoQuik.app
```

## Requirements

- macOS 14 or later (developed and built on macOS 27.2, arm64).
- Only the **Command Line Tools** are needed to build; full Xcode is not required.
- Writing requires an administrator password (asked once, when the write starts).

## Build and run

```bash
cd IsoQuik
./build.sh
open build/IsoQuik.app
```

Or:

```bash
make run
```

The app is created in `build/IsoQuik.app`, ad-hoc signed and ready for local use.

> **SDK note.** With only the Command Line Tools, SDK 27 lacks the `SwiftUIMacros`
> plugin required by SwiftUI macros, so `build.sh` uses the SDK 26.5 bundled with the
> CLT. If full Xcode is installed, the script uses Xcode's default SDK automatically.
> You can force an SDK with `SDK=/path/to/MacOSX.sdk ./build.sh`.

The app is built as a universal binary (arm64 + x86_64). To build a single architecture: `ARCH=arm64 ./build.sh` or `ARCH=x86_64 ./build.sh`.

## Versioning

The version lives in `Resources/Info.plist`:

- `CFBundleShortVersionString`: the user-facing version (semantic versioning, e.g. `1.1.0`);
- `CFBundleVersion`: the build number, increased with every release.

`build.sh` prints the version it builds; `./make_dmg.sh` (or `make dmg`) builds the app and packages it as
`build/IsoQuik-<version>.dmg`. After publishing a release, update `version` and `sha256` in the
[Homebrew cask](https://github.com/massan71/homebrew-tap/blob/main/Casks/isoquik.rb). The app shows it in the header (hover for the
build number) and in **IsoQuik → About IsoQuik**. Record every release in `CHANGELOG.md`.

## Usage

1. Drag an `.iso`, `.img` or `.dmg` file onto the left area, or click **Choose Image…** (⌘O).
2. The app shows how the image boots (for example *UEFI x86-64 · BIOS · bootable from USB*) and warns when
   the drive will not boot: ISOs that only boot from CD/DVD (such as Windows ISOs), images that are not
   bootable at all, and images built for another kind of computer. Macs with Apple silicon cannot start
   any system other than macOS from a USB drive, so IsoQuik says so for bootable images.
3. The app computes the image's **SHA-256**. Paste the checksum published by the image's
   distributor (a bare hash or a `SHA256SUMS` line) to check that the file is intact.
4. Select the USB drive or SD card as the destination. Each drive shows its device, size, bus and current volumes.
   Virtual disks, disk images and the startup disk are excluded.
5. Keep **Verify after writing** enabled (recommended).
6. Click **Write** (⌘↩): a confirmation shows the image, the drive and the volumes that will be erased,
   then macOS asks for the administrator password. The app unmounts the disk, writes, verifies and ejects.
7. During the operation the footer shows throughput and time remaining, and the Dock icon shows the percentage.
   You get a notification when it finishes while the app is in the background.
8. **Stop** (⌘.) interrupts writing (the drive is left incomplete, so it asks first) or verification.
9. The **Console** panel logs every step with a timestamp; **Copy** puts the log on the clipboard.

While an operation is running, the window cannot be closed and quitting asks for confirmation.

> `.dmg` files are written as is, without decompression: for a bootable drive, prefer `.iso` or `.img`.

## Raw write safety

A raw write permanently erases all data on the selected disk. For this reason:

- the app only lists **whole**, **external**, **physical** disks, excluding virtual disks, disk images and the startup disk (even when it is an external SSD: it walks from the APFS container to the physical disk);
- if any disk information is missing, or the startup disk cannot be determined, the write is refused;
- it re-checks the disk when writing: it must still be the confirmed drive (same identifier, name and size), not internal, not virtual and not the startup disk;
- after authorization it re-checks the capacity on the opened device before writing;
- it checks that the image is not larger than the drive;
- it shows an explicit confirmation before starting;
- the disk is unmounted with `diskutil unmountDisk force` before writing; if unmounting fails, the write does not start;
- verification reads the drive back and compares it byte by byte with the original image, using the same file descriptor as the write;
- writing can be stopped, but a stopped write leaves the drive incomplete: write it again or erase it with Disk Utility.

Raw device access goes through `/usr/libexec/authopen`, the macOS tool that opens the device after administrator authorization and hands the file descriptor to the app via `SCM_RIGHTS`. As a result:

- a **single prompt** covers writing and verification;
- you do not need to grant the app **Full Disk Access**;
- the app reads the image with user permissions and writes to the device through the authorized descriptor;
- writes and reads are aligned to the sector size reported by the device (512 or 4096 bytes), as raw devices require.

Do not disconnect the drive during writing or verification.

## Project layout

```
IsoQuik/
├── Sources/
│   ├── IsoQuikApp.swift         # SwiftUI entry point
│   ├── AppModel.swift           # state and orchestration
│   ├── ContentView.swift        # user interface
│   ├── Models.swift             # shared models and app version
│   ├── Theme.swift              # colors and visual components
│   └── Services/
│       ├── Shell.swift          # command execution
│       ├── DriveService.swift   # external disk discovery, startup disk detection
│       ├── ISOInspector.swift   # ISO 9660 / Joliet / UDF label reading
│       ├── BootInspector.swift  # partition table, El Torito, UEFI loaders, boot warnings
│       └── RawWriter.swift      # raw write via authopen
├── Resources/
│   ├── Info.plist               # bundle metadata and version
│   └── AppIcon.icns
├── Tools/
│   ├── make_icon.swift          # icon drawing
│   └── make_icon.sh             # generates AppIcon.icns
├── Tests/
│   └── SelfTest.swift           # non-destructive tests
├── build.sh
├── make_dmg.sh              # builds the app and packages it as a .dmg
├── test.sh
├── CHANGELOG.md
├── LICENSE
└── Makefile
```

## Tests

```bash
./test.sh /path/to/image.iso
```

The test:

1. builds a self-test executable;
2. checks image parsing (size, label, ISO 9660/UDF) and boot detection (MBR/GPT, El Torito, UEFI loaders, warnings for Apple silicon and Intel Macs);
3. lists the writable external drives;
4. checks startup disk detection (including the physical disk behind the APFS container) and that it never appears as a destination.

No data is written.

## Current limitations

- no manual speed selection;
- no ISO creation from folders;
- verification reads back the whole image: on slow media it can take a while;
- the app is not notarized: distributing it to others requires an Apple Developer account, Developer ID signing, hardened runtime and notarization;
- writing has been tested end to end on a USB drive with 512-byte sectors (write, byte-by-byte verification and eject); 4096-byte sector devices have not been tested on real hardware.

## Troubleshooting

**The USB drive does not appear**
Check that it is an external whole disk:

```bash
diskutil list external
```

Disk images and virtual disks are filtered out on purpose.

**Signing / Gatekeeper error**
The local build is ad-hoc signed. If you move or download the app, remove the quarantine attribute:

```bash
xattr -dr com.apple.quarantine build/IsoQuik.app
```

**The administrator password is rejected or cancelled**
Nothing is written. Try again and approve the macOS prompt.

## License

IsoQuik is released under the [MIT License](LICENSE).

Only use the app on media you own and with images you have the rights to. Raw writing is irreversible.
