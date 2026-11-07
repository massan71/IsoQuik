import Foundation

enum ISOInspector {
    static func inspect(_ url: URL) throws -> ISOInfo {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else {
            throw InspectionError.notAFile
        }

        let size = Int64(values.fileSize ?? 0)
        guard size > 0 else {
            throw InspectionError.emptyFile
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var isISO9660 = false
        var isUDF = false
        var label: String?

        // Primary Volume Descriptor: sector 16, offset 32768.
        if let pvd = try read(handle, offset: 32_768, length: 2_048),
           pvd.count == 2_048,
           byte(pvd, 0) == 1,
           ascii(pvd, 1, 5) == "CD001" {
            isISO9660 = true
            label = clean(ascii(pvd, 40, 32))
        }

        // Joliet Supplementary Volume Descriptor: sector 17.
        if isISO9660,
           let svd = try read(handle, offset: 34_816, length: 2_048),
           svd.count == 2_048,
           byte(svd, 0) == 2 {
            let escape = ascii(svd, 88, 3)
            if escape == "%/@" || escape == "%/C" || escape == "%/E" {
                if let jolietLabel = utf16be(svd, 40, 32) {
                    label = jolietLabel
                }
            }
        }

        // Volume Recognition Sequence UDF (BEA01 / NSR02 / NSR03).
        if let vrs = try read(handle, offset: 32_768, length: 2_048),
           let text = String(data: vrs, encoding: .ascii),
           text.contains("BEA01") || text.contains("NSR02") || text.contains("NSR03") {
            isUDF = true
        }

        return ISOInfo(
            url: url,
            size: size,
            volumeLabel: label,
            isISO9660: isISO9660,
            isUDF: isUDF,
            boot: BootInspector.inspect(handle, url: url, isISO9660: isISO9660, label: label)
        )
    }

    private static func read(_ handle: FileHandle, offset: UInt64, length: Int) throws -> Data? {
        try handle.seek(toOffset: offset)
        return try handle.read(upToCount: length)
    }

    private static func byte(_ data: Data, _ offset: Int) -> UInt8 {
        data[data.startIndex + offset]
    }

    private static func ascii(_ data: Data, _ start: Int, _ length: Int) -> String {
        let lower = data.startIndex + start
        let upper = min(lower + length, data.endIndex)
        guard lower < upper else { return "" }
        return String(data: data[lower..<upper], encoding: .ascii) ?? ""
    }

    private static func utf16be(_ data: Data, _ start: Int, _ length: Int) -> String? {
        let lower = data.startIndex + start
        let upper = min(lower + length, data.endIndex)
        guard lower < upper else { return nil }

        var units: [UInt16] = []
        var index = lower
        while index + 1 < upper {
            units.append((UInt16(data[index]) << 8) | UInt16(data[index + 1]))
            index += 2
        }

        let string = String(decoding: units, as: UTF16.self)
        return clean(string)
    }

    private static func clean(_ value: String) -> String? {
        let cleaned = value
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}

enum InspectionError: LocalizedError {
    case notAFile
    case emptyFile

    var errorDescription: String? {
        switch self {
        case .notAFile:
            return "The selected path is not a file."
        case .emptyFile:
            return "The image file is empty."
        }
    }
}
