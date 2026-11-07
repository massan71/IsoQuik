import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showRawConfirm = false
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
                        VStack(spacing: 18) {
                            isoPanel
                            optionsPanel
                        }
                        .frame(maxWidth: .infinity, alignment: .top)

                        destinationPanel
                            .frame(width: 400)
                    }
                    .padding(24)
                }
                .scrollIndicators(.hidden)

                Divider().overlay(Theme.cardBorder)
                footer
            }
        }
        .frame(minWidth: 980, minHeight: 700)
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
            "Write the image to \(pendingRawTarget?.name ?? "disk")?",
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
            Text(
                "All data on \(pendingRawTarget?.device ?? "the disk") will be permanently erased. "
                + "This cannot be undone."
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 54, height: 54)
                .shadow(color: Theme.accent.opacity(0.35), radius: 12, x: 0, y: 5)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text("IsoQuik")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
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

            if !model.rawTargets.isEmpty {
                InfoPill(
                    icon: "externaldrive.fill",
                    text: "\(model.rawTargets.count) \(model.rawTargets.count == 1 ? "drive" : "drives")"
                )
            }

            Button {
                Task { await model.refreshDevices() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(QuietButtonStyle())
            .disabled(model.isRefreshing || model.phase.isBusy)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    // MARK: - Image

    private var isoPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeader(icon: "doc.fill", title: "Image")

            if let iso = model.iso {
                imageRow(iso)
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
                    .frame(width: 48, height: 48)
                Image(systemName: "doc.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: Theme.accent.opacity(0.30), radius: 8, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 5) {
                Text(iso.url.lastPathComponent)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

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
            }

            Spacer()

            Button("Change") {
                model.chooseISO()
            }
            .buttonStyle(QuietButtonStyle())
            .disabled(model.phase.isBusy)
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
                    .frame(width: 84, height: 84)

                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }

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

            HStack(spacing: 6) {
                formatChip("ISO")
                formatChip("IMG")
                formatChip("DMG")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 250)
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

    // MARK: - Options

    private var optionsPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionHeader(icon: "slider.horizontal.3", title: "Options")

            Toggle(isOn: $model.verify) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Theme.accent.opacity(0.13))
                            .frame(width: 38, height: 38)
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.accent)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Verify after writing")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Reads the drive back and compares every byte with the image.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .toggleStyle(.switch)
            .tint(Theme.accent)
            .disabled(model.phase.isBusy)
        }
        .themeCard()
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
                    selectRow(
                        selected: model.selectedRawID == target.id,
                        icon: "externaldrive.fill",
                        title: target.name,
                        subtitle: "\(target.device) • \(target.formattedSize) • \(target.bus)"
                    ) {
                        model.selectedRawID = target.id
                    }
                }

                if let target = model.selectedRaw {
                    if selectedImageIsDMG {
                        warningBox(
                            "The .dmg file will be written as is, without decompressing it. "
                            + "For a bootable drive, use an .iso or .img image."
                        )
                    }
                    if !target.volumes.isEmpty {
                        warningBox(
                            "Mounted volumes: \(target.volumes.joined(separator: ", ")). They will be unmounted before writing."
                        )
                    }
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
        VStack(spacing: 12) {
            if model.phase.isBusy {
                progressBar
            } else {
                actionBar
            }

            DisclosureGroup(isExpanded: $showLog) {
                ScrollView {
                    Text(model.logText.isEmpty ? "No output yet." : model.logText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
            } label: {
                Label("Console", systemImage: "terminal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.cardBorder)
                .frame(height: 1)
        }
    }

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: phaseSymbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)

                Text(model.statusLine)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Spacer()

                if let progress = model.progress {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.accent)
                }
            }

            if let progress = model.progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
            }

            Label("Do not disconnect the drive until the operation is complete.", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            statusBadge

            Spacer()

            if model.phase != .idle {
                Button("Reset") {
                    model.reset()
                }
                .buttonStyle(QuietButtonStyle())
            }

            Button {
                startTapped()
            } label: {
                Label("Write", systemImage: "arrow.down.to.line")
                    .frame(minWidth: 132)
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(!model.canStart)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if case .done = model.phase {
            statusPill("Completed", icon: "checkmark.circle.fill", color: Theme.success)
        } else if case .failed = model.phase {
            statusPill("Operation failed", icon: "exclamationmark.triangle.fill", color: Theme.danger)
        } else if case .cancelled = model.phase {
            statusPill("Cancelled", icon: "xmark.circle", color: Theme.textSecondary)
        }
    }

    private func statusPill(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(color.opacity(0.13)))
            .overlay(Capsule().strokeBorder(color.opacity(0.28), lineWidth: 1))
            .foregroundStyle(color)
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

    private func selectRow(
        selected: Bool,
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(selected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.fieldFill))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(selected ? Color.white : Theme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(selected ? Theme.accent : Theme.textSecondary.opacity(0.45))
            }
            .padding(11)
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
    }

    private func warningBox(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.warning)
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
