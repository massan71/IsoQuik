import Foundation

struct ISOInfo: Equatable {
    let url: URL
    let size: Int64
    let volumeLabel: String?
    let isISO9660: Bool
    let isUDF: Bool

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var formatLabel: String {
        if isUDF { return "UDF" }
        if isISO9660 { return "ISO 9660" }
        return "Image"
    }
}

struct RawTarget: Identifiable, Hashable {
    let id: String
    let device: String
    let name: String
    let size: Int64
    let bus: String
    let volumes: [String]

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

enum BurnPhase: Equatable {
    case idle
    case preparing
    case writing
    case verifying
    case ejecting
    case done
    case cancelled
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .preparing, .writing, .verifying, .ejecting:
            return true
        default:
            return false
        }
    }

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

enum AppVersion {
    /// Marketing version and build number from Info.plist, e.g. "1.1.0 (2)".
    static var display: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "dev"
        guard let build = info?["CFBundleVersion"] as? String else { return version }
        return "\(version) (\(build))"
    }

    static var short: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}
