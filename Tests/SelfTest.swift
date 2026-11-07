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
            } catch {
                print("ERROR image: \(error.localizedDescription)")
                failed = true
            }
        } else {
            print("No image given: skipping the ISO test.")
        }

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
