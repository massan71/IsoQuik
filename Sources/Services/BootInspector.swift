import Darwin
import Foundation

/// CPU architectures a UEFI boot loader can target.
enum BootArchitecture: String, CaseIterable, Comparable {
    case x86_64
    case arm64
    case x86
    case riscv64

    /// Default removable-media loader name (UEFI spec, section 3.5.1.1).
    var efiLoader: String {
        switch self {
        case .x86_64: return "BOOTX64.EFI"
        case .arm64: return "BOOTAA64.EFI"
        case .x86: return "BOOTIA32.EFI"
        case .riscv64: return "BOOTRISCV64.EFI"
        }
    }

    var displayName: String {
        switch self {
        case .x86_64: return "x86-64"
        case .arm64: return "ARM64"
        case .x86: return "32-bit x86"
        case .riscv64: return "RISC-V"
        }
    }

    /// "x86-64 PCs", "ARM64 computers"…
    var machines: String {
        switch self {
        case .x86_64: return "x86-64 PCs"
        case .arm64: return "ARM64 computers"
        case .x86: return "32-bit x86 PCs"
        case .riscv64: return "RISC-V computers"
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// What an image needs to start a computer once written raw to a USB drive.
struct BootInfo: Equatable {
    /// MBR boot signature (0x55AA) in the first sector.
    var hasMBR = false
    /// GPT header ("EFI PART") in the second sector.
    var hasGPT = false
    /// El Torito boot catalog entries: these make a CD/DVD bootable.
    var elToritoBIOS = false
    var elToritoEFI = false
    /// UEFI loaders found in /EFI/BOOT of the ISO 9660 file system.
    var efiArchitectures: Set<BootArchitecture> = []
    /// Architectures guessed from the file name or volume label ("amd64", "arm64"…).
    var nameArchitectures: Set<BootArchitecture> = []

    var hasPartitionTable: Bool { hasMBR || hasGPT }
    var hasElTorito: Bool { elToritoBIOS || elToritoEFI }

    /// Architectures from the boot loaders, or failing that from the name.
    var architectures: Set<BootArchitecture> {
        efiArchitectures.isEmpty ? nameArchitectures : efiArchitectures
    }

    var architecturesAreGuessed: Bool {
        efiArchitectures.isEmpty && !nameArchitectures.isEmpty
    }
}

/// The machine IsoQuik is running on.
enum HostMachine {
    /// True on Apple silicon, also when the app runs under Rosetta.
    static let isAppleSilicon: Bool = {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }()
}

/// A message about whether the written drive will boot.
struct BootNotice: Equatable {
    enum Level {
        case info
        case warning
    }

    let level: Level
    let text: String
}

enum BootAdvisor {
    /// One-line description, e.g. "UEFI x86-64 · BIOS · bootable from USB".
    static func summary(for info: ISOInfo) -> String? {
        let boot = info.boot
        var parts: [String] = []

        let architectures = boot.architectures.sorted()
        if !architectures.isEmpty {
            let names = architectures.map(\.displayName).joined(separator: " + ")
            parts.append(boot.architecturesAreGuessed ? "\(names) (from the name)" : "UEFI \(names)")
        } else if boot.elToritoEFI {
            parts.append("UEFI")
        }
        if boot.elToritoBIOS {
            parts.append("BIOS")
        }

        if info.isISO9660 {
            if boot.hasPartitionTable {
                if !parts.isEmpty { parts.append("bootable from USB") }
            } else if boot.hasElTorito {
                parts.append("CD/DVD boot only")
            }
        } else if boot.hasPartitionTable {
            parts.append(boot.hasGPT ? "GPT disk image" : "MBR disk image")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Warnings shown before writing, most important first.
    static func notices(for info: ISOInfo, appleSilicon: Bool = HostMachine.isAppleSilicon) -> [BootNotice] {
        let boot = info.boot
        var notices: [BootNotice] = []

        // 1. Will a raw copy boot from USB at all?
        if info.isISO9660 && !boot.hasPartitionTable {
            if boot.hasElTorito {
                notices.append(BootNotice(
                    level: .warning,
                    text: "This ISO can start a computer from a CD/DVD, but it has no partition table: "
                        + "written as is to a USB drive it will probably not boot. Windows ISOs, for example, "
                        + "need a dedicated tool that prepares the USB drive."
                ))
            } else {
                notices.append(BootNotice(
                    level: .warning,
                    text: "This image does not look bootable: it has no partition table and no boot catalog. "
                        + "The drive will hold its data, but a computer will not start from it."
                ))
                return notices
            }
        }

        // 2. Will it boot on this Mac?
        let architectures = boot.architectures
        // Raw .img files can be anything (a Raspberry Pi card, a data disk…):
        // only talk about this Mac when the architecture is known.
        let isBootable = info.isISO9660
            ? boot.hasPartitionTable || boot.hasElTorito || !architectures.isEmpty
            : !architectures.isEmpty
        guard isBootable else { return notices }

        let target = architectures.isEmpty
            ? "a PC"
            : architectures.sorted().map(\.machines).joined(separator: " and ")

        if appleSilicon {
            let reason = architectures.isEmpty || architectures.contains(.arm64)
                ? "Macs with Apple silicon can only start macOS from an external drive."
                : "It is built for \(target), and Macs with Apple silicon can only start macOS from an external drive."
            notices.append(BootNotice(
                level: .info,
                text: "This drive will not start this Mac. \(reason) "
                    + "Use it on \(target), or run the system in a virtual machine (for example UTM)."
            ))
        } else if !architectures.isEmpty && !architectures.contains(.x86_64) {
            notices.append(BootNotice(
                level: .info,
                text: "This image is built for \(target): it will not start this Intel Mac."
            ))
        }

        return notices
    }
}

enum BootInspector {
    static func inspect(_ handle: FileHandle, url: URL, isISO9660: Bool, label: String?) -> BootInfo {
        var info = BootInfo()

        if let sectors = read(handle, offset: 0, length: 1_024), sectors.count == 1_024 {
            info.hasMBR = sectors[510] == 0x55 && sectors[511] == 0xAA
            info.hasGPT = String(data: sectors[512..<520], encoding: .ascii) == "EFI PART"
        }

        if isISO9660 {
            readElTorito(handle, into: &info)
            info.efiArchitectures = efiLoaders(handle)
        }

        let name = (url.deletingPathExtension().lastPathComponent + " " + (label ?? "")).lowercased()
        info.nameArchitectures = architectures(inName: name)
        return info
    }

    // MARK: - El Torito

    private static func readElTorito(_ handle: FileHandle, into info: inout BootInfo) {
        // Volume descriptors start at sector 16 and end with type 255.
        for sector in 16..<48 {
            guard let descriptor = read(handle, offset: UInt64(sector) * 2_048, length: 2_048),
                  descriptor.count == 2_048,
                  String(data: descriptor[1..<6], encoding: .ascii) == "CD001" else { return }

            let type = descriptor[0]
            if type == 255 { return }
            guard type == 0,
                  let system = String(data: descriptor[7..<30], encoding: .ascii),
                  system == "EL TORITO SPECIFICATION" else { continue }

            let catalogSector = littleEndian32(descriptor, 71)
            guard let catalog = read(handle, offset: UInt64(catalogSector) * 2_048, length: 2_048),
                  catalog.count == 2_048,
                  catalog[0] == 0x01 else { return }

            // The validation entry names the platform of the default entry;
            // section headers (0x90 / 0x91) name the platform of the entries after them.
            mark(platform: catalog[1], in: &info)
            var offset = 64
            while offset + 32 <= catalog.count {
                let header = catalog[offset]
                if header == 0x90 || header == 0x91 {
                    mark(platform: catalog[offset + 1], in: &info)
                }
                offset += 32
            }
            return
        }
    }

    private static func mark(platform: UInt8, in info: inout BootInfo) {
        switch platform {
        case 0x00: info.elToritoBIOS = true
        case 0xEF: info.elToritoEFI = true
        default: break
        }
    }

    // MARK: - /EFI/BOOT

    private static func efiLoaders(_ handle: FileHandle) -> Set<BootArchitecture> {
        guard let pvd = read(handle, offset: 32_768, length: 2_048), pvd.count == 2_048 else { return [] }

        // Root directory record: 34 bytes at offset 156 of the primary volume descriptor.
        let root = DirectoryEntry(
            name: "",
            extent: littleEndian32(pvd, 156 + 2),
            length: littleEndian32(pvd, 156 + 10),
            isDirectory: true
        )

        guard let efi = entries(of: root, handle).first(where: { $0.isDirectory && $0.name == "EFI" }),
              let boot = entries(of: efi, handle).first(where: { $0.isDirectory && $0.name == "BOOT" })
        else { return [] }

        let files = Set(entries(of: boot, handle).filter { !$0.isDirectory }.map(\.name))
        return Set(BootArchitecture.allCases.filter { files.contains($0.efiLoader) })
    }

    private struct DirectoryEntry {
        let name: String
        let extent: UInt32
        let length: UInt32
        let isDirectory: Bool
    }

    private static func entries(of directory: DirectoryEntry, _ handle: FileHandle) -> [DirectoryEntry] {
        // Directories that hold boot files are small; cap the read to stay safe on odd images.
        let length = Int(min(directory.length, 1 << 20))
        guard length > 0,
              let data = read(handle, offset: UInt64(directory.extent) * 2_048, length: length),
              !data.isEmpty else { return [] }

        var result: [DirectoryEntry] = []
        var offset = 0
        while offset < data.count {
            let recordLength = Int(data[offset])
            if recordLength == 0 {
                // Records never cross a sector boundary: skip to the next sector.
                offset = (offset / 2_048 + 1) * 2_048
                continue
            }
            guard recordLength >= 34, offset + recordLength <= data.count else { break }

            let nameLength = Int(data[offset + 32])
            if nameLength > 0, offset + 33 + nameLength <= data.count {
                let rawName = data[(offset + 33)..<(offset + 33 + nameLength)]
                // Skip "." and ".." (single bytes 0x00 and 0x01).
                if !(nameLength == 1 && (rawName.first == 0 || rawName.first == 1)),
                   var name = String(data: rawName, encoding: .ascii) {
                    if let version = name.firstIndex(of: ";") { name = String(name[..<version]) }
                    if name.hasSuffix(".") { name.removeLast() }
                    result.append(DirectoryEntry(
                        name: name.uppercased(),
                        extent: littleEndian32(data, offset + 2),
                        length: littleEndian32(data, offset + 10),
                        isDirectory: data[offset + 25] & 0x02 != 0
                    ))
                }
            }
            offset += recordLength
        }
        return result
    }

    // MARK: - Name

    private static func architectures(inName name: String) -> Set<BootArchitecture> {
        let tokens = Set(name.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" }).map(String.init))
        var result: Set<BootArchitecture> = []
        if !tokens.isDisjoint(with: ["amd64", "x86_64", "x64"]) { result.insert(.x86_64) }
        if !tokens.isDisjoint(with: ["arm64", "aarch64"]) { result.insert(.arm64) }
        if !tokens.isDisjoint(with: ["i386", "i686"]) { result.insert(.x86) }
        if !tokens.isDisjoint(with: ["riscv64"]) { result.insert(.riscv64) }
        return result
    }

    // MARK: - Utilities

    private static func read(_ handle: FileHandle, offset: UInt64, length: Int) -> Data? {
        do {
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: length) else { return nil }
            // Re-base so that indices start at 0.
            return Data(data)
        } catch {
            return nil
        }
    }

    private static func littleEndian32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }
}
