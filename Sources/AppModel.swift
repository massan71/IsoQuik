import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
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

    private var operation: Task<Void, Never>?

    var selectedRaw: RawTarget? {
        rawTargets.first { $0.id == selectedRawID }
    }

    var canStart: Bool {
        iso != nil && selectedRaw != nil && !phase.isBusy
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
        } catch {
            errorMessage = error.localizedDescription
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
                await self.refreshDevices()
            } catch RawWriteError.cancelled {
                self.phase = .cancelled
                self.statusLine = "Operation cancelled."
            } catch {
                self.fail(error)
            }
        }
    }

    func reset() {
        guard !phase.isBusy else { return }
        phase = .idle
        progress = nil
        statusLine = ""
        logText = ""
        errorMessage = nil
    }

    // MARK: - Internal

    private func begin() {
        phase = .preparing
        progress = nil
        statusLine = "Preparing…"
        logText = ""
        errorMessage = nil
    }

    private func apply(_ update: RawWriter.Update) {
        switch update.phase {
        case .preparing:
            statusLine = "Preparing…"
        case .writing:
            statusLine = progress == nil ? "Preparing and writing…" : "Writing…"
        case .verifying:
            statusLine = "Verifying drive…"
        case .ejecting:
            statusLine = "Ejecting…"
        case .done:
            statusLine = "Write complete."
            progress = 1
        case .cancelled:
            statusLine = "Operation cancelled."
        case .failed(let message):
            statusLine = message
        case .idle:
            break
        }

        phase = update.phase
        if let fraction = update.fraction {
            progress = fraction
        }
        if let log = update.log {
            appendLog(log)
        }
    }

    private func fail(_ error: Error) {
        let message = error.localizedDescription
        phase = .failed(message)
        statusLine = message
        errorMessage = message
        appendLog("ERROR: \(message)")
    }

    func appendLog(_ line: String) {
        guard !line.isEmpty else { return }
        logText += line + "\n"
        if logText.count > 60_000 {
            logText = String(logText.suffix(50_000))
        }
    }
}
