import AppKit
import SwiftUI

@main
struct IsoQuikApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup("IsoQuik") {
            ContentView()
                .environmentObject(model)
                .tint(Theme.accent)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Image…") {
                    model.chooseISO()
                }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(model.phase.isBusy)

                Button("Refresh Devices") {
                    Task { await model.refreshDevices() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.phase.isBusy)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Quitting mid-write leaves the drive half written: ask first.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let model = AppModel.shared
        guard model.phase.isBusy else { return .terminateNow }

        let drive = model.selectedRaw?.name ?? "the drive"
        let alert = NSAlert()
        alert.alertStyle = .critical
        if model.phase == .verifying {
            alert.messageText = "Verification is in progress"
            alert.informativeText = "The write has finished, but \(drive) has not been fully verified yet."
        } else {
            alert.messageText = "A write is in progress"
            alert.informativeText = "If you quit now, \(drive) will be left incomplete and unusable "
                + "until you write it again or erase it with Disk Utility."
        }
        alert.addButton(withTitle: "Keep Going")
        alert.addButton(withTitle: "Quit Anyway")

        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}

/// Disables the window's close button (and ⌘W) while `isBlocked` is true.
struct WindowCloseGuard: NSViewRepresentable {
    let isBlocked: Bool

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        let blocked = isBlocked
        DispatchQueue.main.async {
            view.window?.standardWindowButton(.closeButton)?.isEnabled = !blocked
        }
    }
}
