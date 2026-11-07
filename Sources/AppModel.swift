import AppKit
import CryptoKit
import Foundation
import UniformTypeIdentifiers
import UserNotifications

@MainActor
final class AppModel: ObservableObject {
    /// Shared with the app delegate, which needs it to guard against quitting mid-write.
    static let shared = AppModel()

    @Published var iso: ISOInfo?
    @Published var rawTargets: [RawTarget] = []
    @Published var selectedRawID: String?
    @Published var verify = true
    @Published var phase: BurnPhase = .idle
    @Published var progress: Double?
    @Published var statusLine = ""
    @Published var logText = ""
    @Published var errorMessage: String?
    @Published var isRefreshing = false
    @Published var isDropTargeted = false

    // Throughput of the current phase.
    @Published private(set) var processedBytes: Int64?
    @Published private(set) var totalBytes: Int64?
    @Published private(set) var bytesPerSecond: Double?

    // SHA-256 of the selected image.
    @Published private(set) var checksum: String?
    @Published private(set) var checksumProgress: Double?
    @Published private(set) var checksumError: String?
    @Published var expectedChecksum = ""

    private var operation: Task<Void, Never>?
    private var hashTask: Task<Void, Never>?
    private var rateSample: (time: Date, bytes: Int64)?
    private var ratePhase: BurnPhase?
    private var stopRequested = false

    private static let logTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var selectedRaw: RawTarget? {
        rawTargets.first { $0.id == selectedRawID }
    }

    var canStart: Bool {
        iso != nil && selectedRaw != nil && !phase.isBusy
    }

    /// Stopping is offered once data is moving: not during unmount or the password prompt.
    var canStop: Bool {
        guard !stopRequested else { return false }
        switch phase {
        case .writing: return processedBytes != nil
        case .verifying: return true
        default: return false
        }
    }

    // MARK: - Image

    func chooseISO() {
        guard !phase.isBusy else { return }

        let panel = NSOpenPanel()
        panel.title = "Choose a Disk Image"
        panel.prompt = "Open"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        let types = ["iso", "img", "dmg"].compactMap {
            UTType(filenameExtension: $0)
        }
        panel.allowedContentTypes = types.isEmpty ? [.data] : types

        if panel.runModal() == .OK, let url = panel.url {
            loadISO(url)
        }
    }

    func loadISO(_ url: URL) {
        guard !phase.isBusy else { return }

        let allowed = ["iso", "img", "dmg"]
        guard allowed.contains(url.pathExtension.lowercased()) else {
            errorMessage = "Unsupported format. Choose an .iso, .img or .dmg file."
            return
        }

        do {
            let info = try ISOInspector.inspect(url)
            iso = info
            logText = ""
            statusLine = ""
            errorMessage = nil
            phase = .idle
            progress = nil
            resetThroughput()
            expectedChecksum = ""
            appendLog("Loaded \(url.lastPathComponent) (\(info.formattedSize), \(info.formatLabel)).")
            if let boot = BootAdvisor.summary(for: info) {
                appendLog("Boot: \(boot).")
            }
            startChecksum(for: info)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Checksum

    enum ChecksumMatch {
        case matches
        case differs
        case invalid
    }

    /// Comparison with the checksum the user pasted, or `nil` if there is nothing to compare.
    var checksumMatch: ChecksumMatch? {
        // Accept "hash" as well as the "hash  filename" lines of SHA256SUMS files.
        let pasted = expectedChecksum
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .first
            .map { String($0).lowercased() } ?? ""
        guard !pasted.isEmpty, let checksum else { return nil }
        guard pasted.count == 64, pasted.allSatisfy(\.isHexDigit) else { return .invalid }
        return pasted == checksum ? .matches : .differs
    }

    private func startChecksum(for info: ISOInfo) {
        hashTask?.cancel()
        checksum = nil
        checksumError = nil
        checksumProgress = 0

        let url = info.url
        let size = info.size

        hashTask = Task.detached(priority: .utility) { [weak self] in
            let handle: FileHandle
            do {
                handle = try FileHandle(forReadingFrom: url)
            } catch {
                await self?.finishChecksum(for: url, hex: nil, error: error.localizedDescription)
                return
            }
            defer { try? handle.close() }

            var hasher = SHA256()
            var done: Int64 = 0
            var lastReport = Date.distantPast

            while true {
                if Task.isCancelled { return }
                let data: Data
                do {
                    data = try handle.read(upToCount: 4 * 1024 * 1024) ?? Data()
                } catch {
                    await self?.finishChecksum(for: url, hex: nil, error: error.localizedDescription)
                    return
                }
                if data.isEmpty { break }
                hasher.update(data: data)
                done += Int64(data.count)

                if Date().timeIntervalSince(lastReport) > 0.2 {
                    lastReport = Date()
                    let fraction = size > 0 ? min(Double(done) / Double(size), 1) : nil
                    await self?.reportChecksumProgress(for: url, fraction: fraction)
                }
            }

            let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            await self?.finishChecksum(for: url, hex: hex, error: nil)
        }
    }

    private func reportChecksumProgress(for url: URL, fraction: Double?) {
        guard iso?.url == url, checksum == nil else { return }
        checksumProgress = fraction
    }

    private func finishChecksum(for url: URL, hex: String?, error: String?) {
        guard iso?.url == url else { return }
        checksumProgress = nil
        checksum = hex
        if let hex {
            appendLog("SHA-256 of \(url.lastPathComponent): \(hex)")
        }
        if let error {
            checksumError = error
            appendLog("Could not compute SHA-256: \(error)")
        }
    }

    // MARK: - Devices

    func refreshDevices() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let newTargets = await DriveService.rawTargets()
        rawTargets = newTargets

        if let selected = selectedRawID, !newTargets.contains(where: { $0.id == selected }) {
            selectedRawID = nil
        }
        if selectedRawID == nil, newTargets.count == 1 {
            selectedRawID = newTargets[0].id
        }
    }

    // MARK: - Writing

    func startRawWrite(target: RawTarget) {
        guard let iso, !phase.isBusy else { return }
        begin()
        requestNotificationPermission()

        appendLog("Writing \(iso.url.lastPathComponent) (\(iso.formattedSize)) to \(target.name) (\(target.device), \(target.formattedSize)).")

        operation = Task { [weak self] in
            guard let self else { return }
            do {
                try await RawWriter.write(
                    image: iso.url,
                    target: target,
                    verify: self.verify
                ) { update in
                    self.apply(update)
                }
                self.finish()
                self.notify(
                    title: "Write complete",
                    body: self.verify
                        ? "\(iso.url.lastPathComponent) was written to \(target.name) and verified."
                        : "\(iso.url.lastPathComponent) was written to \(target.name)."
                )
                await self.refreshDevices()
            } catch RawWriteError.cancelled {
                self.finish()
                self.phase = .cancelled
                self.statusLine = "Operation cancelled."
                self.appendLog("Authorization cancelled: nothing was written.")
            } catch RawWriteError.stopped(let message) {
                self.finish()
                self.phase = .stopped
                self.statusLine = message
                self.appendLog(message)
                self.notify(title: "Write stopped", body: message)
                await self.refreshDevices()
            } catch {
                self.finish()
                self.fail(error)
                self.notify(title: "Write failed", body: error.localizedDescription)
            }
        }
    }

    func stop() {
        guard canStop else { return }
        stopRequested = true
        appendLog("Stop requested…")
        operation?.cancel()
    }

    func reset() {
        guard !phase.isBusy else { return }
        phase = .idle
        progress = nil
        statusLine = ""
        logText = ""
        errorMessage = nil
        resetThroughput()
    }

    // MARK: - Progress details

    /// "123 MB of 210 MB · 38 MB/s · about 2 min left"
    var progressDetail: String? {
        guard let processedBytes, let totalBytes else { return nil }
        var parts = [
            "\(Self.bytes(processedBytes)) of \(Self.bytes(totalBytes))"
        ]
        if let bytesPerSecond, bytesPerSecond > 0 {
            parts.append("\(Self.bytes(Int64(bytesPerSecond)))/s")
            let remaining = Double(max(totalBytes - processedBytes, 0)) / bytesPerSecond
            parts.append(Self.timeLeft(remaining))
        }
        return parts.joined(separator: " · ")
    }

    private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private static func timeLeft(_ seconds: Double) -> String {
        if seconds < 10 { return "a few seconds left" }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        let text = formatter.string(from: seconds.rounded()) ?? ""
        return "about \(text) left"
    }

    // MARK: - Internal

    private func begin() {
        phase = .preparing
        progress = nil
        statusLine = "Preparing…"
        logText = ""
        errorMessage = nil
        stopRequested = false
        resetThroughput()
    }

    private func finish() {
        operation = nil
        stopRequested = false
        bytesPerSecond = nil
        NSApp.dockTile.badgeLabel = nil
    }

    private func resetThroughput() {
        processedBytes = nil
        totalBytes = nil
        bytesPerSecond = nil
        rateSample = nil
        ratePhase = nil
    }

    private func apply(_ update: RawWriter.Update) {
        switch update.phase {
        case .preparing:
            statusLine = "Preparing…"
        case .writing:
            statusLine = update.processed == nil && processedBytes == nil
                ? "Waiting for authorization…"
                : "Writing…"
        case .verifying:
            statusLine = "Verifying drive…"
        case .ejecting:
            statusLine = "Ejecting…"
        case .done:
            statusLine = "Write complete."
            progress = 1
        case .cancelled, .stopped:
            break
        case .failed(let message):
            statusLine = message
        case .idle:
            break
        }

        if update.phase != ratePhase {
            ratePhase = update.phase
            processedBytes = nil
            totalBytes = nil
            bytesPerSecond = nil
            rateSample = nil
        }
        if let processed = update.processed, let total = update.total {
            updateThroughput(processed: processed, total: total)
        }

        phase = update.phase
        if let fraction = update.fraction {
            progress = fraction
        }
        if let log = update.log {
            appendLog(log)
        }

        if phase.isBusy, let progress, update.processed != nil {
            let prefix = phase == .verifying ? "✓" : ""
            NSApp.dockTile.badgeLabel = "\(prefix)\(Int(progress * 100))%"
        }
    }

    private func updateThroughput(processed: Int64, total: Int64) {
        processedBytes = processed
        totalBytes = total

        let now = Date()
        guard let sample = rateSample else {
            rateSample = (now, processed)
            return
        }
        let elapsed = now.timeIntervalSince(sample.time)
        guard elapsed >= 0.5 else { return }

        let instant = Double(processed - sample.bytes) / elapsed
        // Exponential smoothing keeps the estimate steady between chunks.
        bytesPerSecond = bytesPerSecond.map { $0 * 0.7 + instant * 0.3 } ?? instant
        rateSample = (now, processed)
    }

    private func fail(_ error: Error) {
        // Shown in the status bar and the console; no extra alert.
        let message = error.localizedDescription
        phase = .failed(message)
        statusLine = message
        appendLog("ERROR: \(message)")
    }

    func appendLog(_ line: String) {
        guard !line.isEmpty else { return }
        logText += "[\(Self.logTime.string(from: Date()))] \(line)\n"
        if logText.count > 60_000 {
            logText = String(logText.suffix(50_000))
        }
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Posts a notification only when the user is looking elsewhere.
    private func notify(title: String, body: String) {
        guard !NSApp.isActive else { return }
        NSApp.requestUserAttention(.informationalRequest)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
