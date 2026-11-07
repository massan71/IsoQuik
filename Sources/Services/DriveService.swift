import Foundation

enum DriveService {
    // MARK: - Removable drives

    static func rawTargets() async -> [RawTarget] {
        let listed = await Shell.run("/usr/sbin/diskutil", ["list", "-plist", "external"])
        guard
            let data = listed.stdout.data(using: .utf8),
            let root = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any],
            let disks = root["AllDisksAndPartitions"] as? [[String: Any]]
        else {
            return []
        }

        let bootDisks = await bootWholeDisks()
        var targets: [RawTarget] = []

        for disk in disks {
            guard let identifier = disk["DeviceIdentifier"] as? String else { continue }
            guard let info = await diskInfo(identifier) else { continue }

            // Whole, external, physical disks only; never the startup disk.
            if eligibilityProblem(info) != nil { continue }
            if bootDisks?.contains(identifier) ?? false { continue }

            let totalSize = (info["TotalSize"] as? NSNumber)?.int64Value
                ?? (disk["Size"] as? NSNumber)?.int64Value
                ?? 0
            guard totalSize > 0 else { continue }

            let name = (info["MediaName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? identifier
            let bus = (info["BusProtocol"] as? String) ?? "Sconosciuto"

            var volumes: [String] = []
            if let partitions = disk["Partitions"] as? [[String: Any]] {
                for partition in partitions {
                    if let mountPoint = partition["MountPoint"] as? String, !mountPoint.isEmpty {
                        volumes.append(mountPoint)
                    } else if let volumeName = partition["VolumeName"] as? String, !volumeName.isEmpty {
                        volumes.append(volumeName)
                    }
                }
            }

            targets.append(
                RawTarget(
                    id: identifier,
                    device: "/dev/\(identifier)",
                    name: name,
                    size: totalSize,
                    bus: bus,
                    volumes: volumes
                )
            )
        }

        return targets.sorted { $0.device < $1.device }
    }

    static func diskInfo(_ identifier: String) async -> [String: Any]? {
        let result = await Shell.run("/usr/sbin/diskutil", ["info", "-plist", identifier])
        guard
            let data = result.stdout.data(using: .utf8),
            let info = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any]
        else {
            return nil
        }
        return info
    }

    /// Why the disk is not a valid destination, or `nil`.
    /// A disk is rejected when any required information is missing.
    static func eligibilityProblem(_ info: [String: Any]) -> String? {
        guard let whole = (info["WholeDisk"] as? Bool) ?? (info["Whole"] as? Bool) else {
            return "Cannot determine whether the device is a whole disk."
        }
        if !whole {
            return "The selected device is not a whole disk."
        }
        guard let internalDisk = info["Internal"] as? Bool else {
            return "Cannot determine whether the disk is internal."
        }
        if internalDisk {
            return "Refused: the selected disk is internal."
        }
        guard let kind = info["VirtualOrPhysical"] as? String else {
            return "Cannot determine whether the disk is physical."
        }
        if kind == "Virtual" {
            return "Refused: the selected disk is virtual."
        }
        if let bus = info["BusProtocol"] as? String, bus == "Disk Image" {
            return "Refused: the selected disk is a disk image."
        }
        return nil
    }

    /// Whole disks holding the startup volume, including the physical disks
    /// behind an APFS container (e.g. synthesized disk3 → disk0).
    /// Returns `nil` when the startup disk cannot be determined.
    static func bootWholeDisks() async -> Set<String>? {
        guard let rootInfo = await diskInfo("/") else { return nil }

        var wholeDisks = Set<String>()
        var pending: [String] = []

        if let parent = rootInfo["ParentWholeDisk"] as? String, !parent.isEmpty {
            pending.append(parent)
        } else if let identifier = rootInfo["DeviceIdentifier"] as? String {
            pending.append(wholeDiskName(identifier))
        } else {
            return nil
        }

        // Walk from APFS containers up to their physical stores.
        while let disk = pending.popLast() {
            guard wholeDisks.insert(disk).inserted else { continue }
            guard let info = await diskInfo(disk) else { return nil }

            let stores = (info["APFSPhysicalStores"] as? [[String: Any]]) ?? []
            for store in stores {
                guard let storeID = store["APFSPhysicalStore"] as? String else { continue }
                if let storeInfo = await diskInfo(storeID),
                   let parent = storeInfo["ParentWholeDisk"] as? String,
                   !parent.isEmpty {
                    pending.append(parent)
                } else {
                    pending.append(wholeDiskName(storeID))
                }
            }
        }

        return wholeDisks
    }

    private static func wholeDiskName(_ identifier: String) -> String {
        identifier.replacingOccurrences(
            of: "^(disk[0-9]+).*$",
            with: "$1",
            options: .regularExpression
        )
    }
}
