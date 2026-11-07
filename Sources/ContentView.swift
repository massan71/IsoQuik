import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showRawConfirm = false
    @State private var showStopConfirm = false
    @State private var pendingRawTarget: RawTarget?
    @State private var showLog = false
    @State private var isDropHovering = false

    var body: some View {
        ZStack {
            ThemeBackground()

            VStack(spacing: 0) {
                header
                Divider().overlay(Theme.cardBorder)

                ScrollView {
                    HStack(alignment: .top, spacing: 18) {
                        isoPanel
                            .frame(maxWidth: .infinity, alignment: .top)

                        destinationPanel
                            .frame(width: 350)
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)

                Divider().overlay(Theme.cardBorder)
                footer
            }
        }
        .frame(minWidth: 820, minHeight: 600)
        .background(WindowCloseGuard(isBlocked: model.phase.isBusy))
        .onDrop(of: [.fileURL], isTargeted: $model.isDropTargeted) { providers in
            handleDrop(providers)
        }
        .task {
            await model.refreshDevices()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if !model.phase.isBusy && !model.isRefreshing {
                    await model.refreshDevices()
                }
            }
        }
        .onChange(of: model.phase) { _, phase in
            if phase.isFailure {
                showLog = true
            }
        }
        .alert("Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .confirmationDialog(
            "Erase \(pendingRawTarget?.name ?? "the drive") and write the image?",
            isPresented: $showRawConfirm,
            titleVisibility: .visible
        ) {
            Button("Cancel", role: .cancel) {
                pendingRawTarget = nil
            }
            Button("Erase and Write", role: .destructive) {
                if let target = pendingRawTarget {
                    model.startRawWrite(target: target)
                }
                pendingRawTarget = nil
            }
        } message: {
            Text(confirmationMessage)
        }
        .confirmationDialog(
            "Stop writing?",
            isPresented: $showStopConfirm,
            titleVisibility: .visible
        ) {
            Button("Keep Writing", role: .cancel) {}
            Button("Stop Writing", role: .destructive) {
                model.stop()
            }
        } message: {
            Text(
                "\(model.selectedRaw?.name ?? "The drive") will be left incomplete and unusable "
                + "until you write it again or erase it with Disk Utility."
            )
        }
    }

    private var confirmationMessage: String {
        guard let target = pendingRawTarget else { return "" }
        var lines: [String] = []
        if let iso = model.iso {
            lines.append("\(iso.url.lastPathComponent) (\(iso.formattedSize))")
            lines.append("→ \(target.name) · \(target.device) · \(target.formattedSize)")
        }
        let volumes = target.volumeNames
        if !volumes.isEmpty {
            lines.append("")
            lines.append("Volumes that will be erased: \(volumes.joined(separator: ", ")).")
        }
        if let iso = model.iso {
            for notice in BootAdvisor.notices(for: iso) where notice.level == .warning {
                lines.append("")
                lines.append("⚠︎ \(notice.text)")
            }
        }
        lines.append("")
        lines.append("All data on the drive will be permanently erased. This cannot be undone.")
        return lines.joined(separator: "\n")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 50, height: 50)
                .shadow(color: Theme.accent.opacity(0.35), radius: 12, x: 0, y: 5)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text("IsoQuik")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.titleGradient)

                    Text("USB / SD")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.accent.opacity(0.14)))
                        .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.30), lineWidth: 1))
                        .foregroundStyle(Theme.accent)

                    Text("v\(AppVersion.short)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .help("IsoQuik \(AppVersion.display)")
                }

                Text("Write ISO images to USB drives and SD cards")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Button {
                Task { await model.refreshDevices() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(QuietButtonStyle())
            .disabled(model.isRefreshing || model.phase.isBusy)
            .help("Refresh the list of drives (⌘R)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Image

    private var isoPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeader(icon: "doc.fill", title: "Image")

            if let iso = model.iso {
                imageRow(iso)
                ForEach(Array(BootAdvisor.notices(for: iso).enumerated()), id: \.offset) { _, notice in
                    switch notice.level {
                    case .warning: warningBox(notice.text)
                    case .info: infoBox(notice.text)
                    }
                }
                checksumBox
                if selectedImageIsDMG {
                    warningBox(
                        "The .dmg file will be written as is, without decompressing it. "
                        + "For a bootable drive, use an .iso or .img image."
                    )
                }
            } else {
                dropZone
            }
        }
        .themeCard()
    }

    private func imageRow(_ iso: ISOInfo) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.accentGradient)
                    .frame(width: 46, height: 46)
                Image(systemName: "doc.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: Theme.accent.opacity(0.30), radius: 8, x: 0, y: 4)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(iso.url.lastPathComponent)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(iso.url.path)

                HStack(spacing: 7) {
                    Text(iso.formattedSize)
                    Text("•")
                    Text(iso.formatLabel)
                    if let label = iso.volumeLabel {
                        Text("•")
                        Text(label).lineLimit(1)
                    }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)

                if let boot = BootAdvisor.summary(for: iso) {
                    Label(boot, systemImage: "power")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .help("How this image starts a computer")
                }
            }
            .accessibilityElement(children: .combine)

            Spacer()

            Button("Change") {
                model.chooseISO()
            }
            .buttonStyle(QuietButtonStyle())
            .disabled(model.phase.isBusy)
            .help("Choose another image (⌘O)")
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.fieldFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.cardBorder, lineWidth: 1)
        }
    }

    private var checksumBox: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("SHA-256")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.textSecondary)

                if let checksum = model.checksum {
                    Text(checksum)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(checksum)

                    Spacer(minLength: 4)

                    Button {
                        copyToPasteboard(checksum)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy SHA-256")
                    .accessibilityLabel("Copy SHA-256")
                } else if let error = model.checksumError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.danger)
                        .lineLimit(1)
                    Spacer()
                } else {
                    Text("Computing…")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                    if let fraction = model.checksumProgress {
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 160)
                            .tint(Theme.accent)
                    }
                    Spacer()
                }
            }

            if model.checksum != nil {
                HStack(spacing: 8) {
                    TextField("Paste the published SHA-256 to compare", text: $model.expectedChecksum)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))

                    checksumVerdict
                }
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.fieldFill.opacity(0.7))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.cardBorder, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var checksumVerdict: some View {
        switch model.checksumMatch {
        case .matches:
            Label("Matches", systemImage: "checkmark.seal.fill")
                .foregroundStyle(Theme.success)
                .font(.system(size: 11.5, weight: .semibold))
        case .differs:
            Label("Does not match", systemImage: "xmark.octagon.fill")
                .foregroundStyle(Theme.danger)
                .font(.system(size: 11.5, weight: .semibold))
        case .invalid:
            Label("Not a SHA-256", systemImage: "questionmark.circle")
                .foregroundStyle(Theme.warning)
                .font(.system(size: 11.5, weight: .semibold))
        case nil:
            EmptyView()
        }
    }

    private var dropZone: some View {
        let active = model.isDropTargeted || isDropHovering

        return VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Theme.accent.opacity(0.30), Theme.accent.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)

                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
            .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text("Drop your image here")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("or choose a file from disk")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }

            Button("Choose Image…") {
                model.chooseISO()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.phase.isBusy)
            .help("Choose an image (⌘O)")

            HStack(spacing: 6) {
                formatChip("ISO")
                formatChip("IMG")
                formatChip("DMG")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Supported formats: ISO, IMG, DMG")
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(active ? Theme.accent.opacity(0.08) : Theme.fieldFill.opacity(0.55))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    active ? Theme.accent : Theme.cardBorder,
                    style: StrokeStyle(lineWidth: 1.5, dash: [8, 6])
                )
        }
        .scaleEffect(active ? 1.006 : 1)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: active)
        .onHover { hovering in
            isDropHovering = hovering
        }
    }

    private func formatChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(0.8)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.fieldFill))
            .overlay(Capsule().strokeBorder(Theme.cardBorder, lineWidth: 1))
            .foregroundStyle(Theme.textSecondary)
    }

    // MARK: - Destination

    private var destinationPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                SectionHeader(icon: "externaldrive.fill", title: "Destination")
                Spacer()
                if !model.rawTargets.isEmpty {
                    Text("\(model.rawTargets.count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.accent.opacity(0.14)))
                        .foregroundStyle(Theme.accent)
                        .accessibilityLabel("\(model.rawTargets.count) drives")
                }
            }

            rawSection

            Spacer(minLength: 0)
        }
        .themeCard()
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var rawSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.rawTargets.isEmpty {
                emptyState(
                    icon: "externaldrive",
                    title: "No external drives",
                    message: "Connect a USB drive or SD card. Virtual disks and the startup disk are excluded for safety."
                )
            } else {
                ForEach(model.rawTargets) { target in
                    driveRow(target, selected: model.selectedRawID == target.id)
                }

                if let target = model.selectedRaw {
                    warningBox(
                        "Raw write: all data on \(target.device) will be erased. "
                        + "Make sure it is not a backup or system disk."
                    )
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 10) {
            if model.phase.isBusy {
                progressBar
            } else {
                actionBar
            }

            console
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.cardBorder)
                .frame(height: 1)
        }
    }

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: phaseSymbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)

                Text(model.statusLine)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                if let progress = model.progress {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.accent)
                }

                if model.canStop {
                    Button {
                        if model.phase == .verifying {
                            model.stop()
                        } else {
                            showStopConfirm = true
                        }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(".", modifiers: [.command])
                    .help(model.phase == .verifying ? "Stop verifying (⌘.)" : "Stop writing (⌘.)")
                }
            }

            if let progress = model.progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
                    .accessibilityLabel(model.statusLine)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
                    .accessibilityLabel(model.statusLine)
            }

            HStack {
                Label(
                    "Do not disconnect the drive until the operation is complete.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)

                Spacer()

                if let detail = model.progressDetail {
                    Text(detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            statusBadge

            Spacer(minLength: 8)

            if model.phase != .idle {
                Button("Reset") {
                    model.reset()
                }
                .buttonStyle(QuietButtonStyle())
            }

            Toggle("Verify after writing", isOn: $model.verify)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.accent)
                .fixedSize()
                .help("Reads the drive back and compares every byte with the image (recommended).")

            Button {
                startTapped()
            } label: {
                HStack(spacing: 8) {
                    Label("Write", systemImage: "arrow.down.to.line")
                    Text("⌘↩")
                        .font(.system(size: 11, weight: .medium))
                        .opacity(0.65)
                }
                .frame(minWidth: 120)
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(!model.canStart)
            .help(writeHelp)
            .accessibilityLabel("Write")
            .accessibilityHint(writeHelp)
        }
    }

    private var writeHelp: String {
        if model.iso == nil { return "Choose an image first." }
        if model.selectedRaw == nil { return "Select a destination drive first." }
        return "Erase the selected drive and write the image (⌘↩)."
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch model.phase {
        case .done:
            statusPill("Completed", icon: "checkmark.circle.fill", color: Theme.success)
        case .failed(let message):
            statusPill(message, icon: "exclamationmark.triangle.fill", color: Theme.danger)
        case .stopped:
            statusPill(model.statusLine, icon: "stop.circle.fill", color: Theme.warning)
        case .cancelled:
            statusPill("Cancelled", icon: "xmark.circle", color: Theme.textSecondary)
        default:
            EmptyView()
        }
    }

    private func statusPill(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(2)
            .truncationMode(.tail)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(color.opacity(0.13)))
            .overlay(Capsule().strokeBorder(color.opacity(0.28), lineWidth: 1))
            .foregroundStyle(color)
            .help(text)
    }

    private var console: some View {
        DisclosureGroup(isExpanded: $showLog) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(model.logText.isEmpty ? "No output yet." : model.logText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear
                            .frame(height: 1)
                            .id("consoleEnd")
                    }
                    .padding(10)
                }
                .frame(height: 120)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.fieldFill)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.cardBorder, lineWidth: 1)
                }
                .overlay(alignment: .topTrailing) {
                    Button {
                        copyToPasteboard(model.logText)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .padding(8)
                    .disabled(model.logText.isEmpty)
                    .help("Copy the console output")
                }
                .onChange(of: model.logText) { _, _ in
                    proxy.scrollTo("consoleEnd", anchor: .bottom)
                }
                .onChange(of: showLog) { _, isShown in
                    if isShown {
                        DispatchQueue.main.async {
                            proxy.scrollTo("consoleEnd", anchor: .bottom)
                        }
                    }
                }
            }
        } label: {
            Label("Console", systemImage: "terminal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var phaseSymbol: String {
        switch model.phase {
        case .preparing: return "hourglass"
        case .writing: return "arrow.down.to.line"
        case .verifying: return "checkmark.seal"
        case .ejecting: return "eject"
        case .done: return "checkmark.circle"
        default: return "circle.dotted"
        }
    }

    // MARK: - Actions

    private func startTapped() {
        guard model.canStart else { return }
        pendingRawTarget = model.selectedRaw
        showRawConfirm = pendingRawTarget != nil
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        guard !model.phase.isBusy else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let value = item as? URL {
                url = value
            } else if let value = item as? NSURL {
                url = value as URL
            } else if let value = item as? String {
                url = URL(fileURLWithPath: value)
            } else {
                url = nil
            }

            guard let url else { return }
            Task { @MainActor in
                model.loadISO(url)
            }
        }
        return true
    }

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }

    private var selectedImageIsDMG: Bool {
        model.iso?.url.pathExtension.lowercased() == "dmg"
    }

    // MARK: - Components

    private func driveRow(_ target: RawTarget, selected: Bool) -> some View {
        let details = "\(target.device) • \(target.formattedSize) • \(target.bus)"
        let volumes = target.volumeNames

        return Button {
            model.selectedRawID = target.id
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(selected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.fieldFill))
                        .frame(width: 36, height: 36)
                    Image(systemName: target.isSDCard ? "sdcard.fill" : "externaldrive.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(selected ? Color.white : Theme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(target.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(details)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !volumes.isEmpty {
                        Text("Volumes: \(volumes.joined(separator: ", "))")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer()

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(selected ? Theme.accent : Theme.textSecondary.opacity(0.45))
            }
            .padding(11)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Theme.accent.opacity(0.11) : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        selected ? Theme.accent.opacity(0.55) : Theme.cardBorder,
                        lineWidth: selected ? 1.4 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(model.phase.isBusy)
        .accessibilityLabel(target.name)
        .accessibilityValue(
            volumes.isEmpty ? details : "\(details). Volumes: \(volumes.joined(separator: ", "))"
        )
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityHint("Selects this drive as the destination.")
    }

    private func warningBox(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.warning)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.warning.opacity(0.09))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.warning.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func infoBox(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.accent.opacity(0.07))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.20), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.10))
                    .frame(width: 64, height: 64)
                Image(systemName: icon)
                    .font(.system(size: 25, weight: .light))
                    .foregroundStyle(Theme.accent)
            }
            .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 12)
    }
}
