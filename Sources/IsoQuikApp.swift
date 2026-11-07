import SwiftUI

@main
struct IsoQuikApp: App {
    @StateObject private var model = AppModel()

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
