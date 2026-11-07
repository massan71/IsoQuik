import Foundation

@main
struct SelfTest {
    static func main() async {
        var failed = false

        if CommandLine.arguments.count > 1 {
            let url = URL(fileURLWithPath: CommandLine.arguments[1])
            do {
                let info = try ISOInspector.inspect(url)
                print("Image: \(info.url.lastPathComponent)")
                print("  size:     \(info.size) bytes")
                print("  volume:   \(info.volumeLabel ?? "-")")
                print("  ISO 9660: \(info.isISO9660)")
                print("  UDF:      \(info.isUDF)")
                print("  format:   \(info.formatLabel)")
                let boot = info.boot
                print("  MBR/GPT:  \(boot.hasMBR)/\(boot.hasGPT)")
                print("  El Torito BIOS/UEFI: \(boot.elToritoBIOS)/\(boot.elToritoEFI)")
                print("  UEFI loaders: \(boot.efiArchitectures.sorted().map(\.efiLoader).joined(separator: ", "))")
                print("  from name:    \(boot.nameArchitectures.sorted().map(\.displayName).joined(separator: ", "))")
                print("  boot:     \(BootAdvisor.summary(for: info) ?? "-")")
                for (host, appleSilicon) in [("Apple silicon", true), ("Intel Mac", false)] {
                    for notice in BootAdvisor.notices(for: info, appleSilicon: appleSilicon) {
                        print("  [\(host)] \(notice.level == .warning ? "WARNING" : "info"): \(notice.text)")
                    }
                }
            } catch {
                print("ERROR image: \(error.localizedDescription)")
                failed = true
            }
        } else {
            print("No image given: skipping the ISO test.")
        }

        #if arch(arm64)
        let slice = "arm64"
        #else
        let slice = "x86_64"
        #endif
        print("Host: \(HostMachine.isAppleSilicon ? "Apple silicon" : "Intel"), running \(slice)")

        let targets = await DriveService.rawTargets()
        print("Writable external drives: \(targets.count)")
        for target in targets {
            print("  \(target.device) — \(target.name) — \(target.formattedSize) — \(target.bus)")
        }

        if let bootDisks = await DriveService.bootWholeDisks() {
            print("Startup disks: \(bootDisks.sorted().joined(separator: ", "))")
            if !bootDisks.contains(where: { diskutilIsNotVirtual($0) }) {
                print("ERROR: no non-virtual disk among the startup disks.")
                failed = true
            }
            if targets.contains(where: { bootDisks.contains($0.id) }) {
                print("ERROR: a startup disk is listed as a destination.")
                failed = true
            }
        } else {
            print("ERROR: startup disk could not be determined.")
            failed = true
        }

        if failed { exit(1) }
    }

    private static func diskutilIsNotVirtual(_ disk: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", disk]
        let pipe = Pipe()
        process.standardOutput = pipe
        guard (try? process.run()) != nil else { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
        return info != nil && (info?["VirtualOrPhysical"] as? String) != "Virtual"
    }
}
