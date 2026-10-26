import SwiftUI
import AppKit

/// Settings sheet: categories on the left, one card of options per category
/// on the right. Every option says what it does in a line.
struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case library, playback, lyrics, updates, advanced
        var id: Self { self }

        var title: String {
            switch self {
            case .library:  return "Library"
            case .playback: return "Playback"
            case .lyrics:   return "Lyrics"
            case .updates:  return "Updates"
            case .advanced: return "Advanced"
            }
        }

        var icon: String {
            switch self {
            case .library:  return "folder"
            case .playback: return "play.circle"
            case .lyrics:   return "quote.bubble"
            case .updates:  return "arrow.down.circle"
            case .advanced: return "wrench.and.screwdriver"
            }
        }
    }

    @Environment(PlayerViewModel.self) private var vm
    @Binding var isPresented: Bool
    @State private var pane: Pane = .library

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(Theme.hairline)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(pane.title)
                        .font(Theme.display(26))
                        .tracking(Theme.displayTracking(26))
                    content
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 720, height: 520)
        .background(Theme.canvas)
        .overlay(alignment: .topTrailing) {
            Button { isPresented = false } label: { Image(systemName: "xmark") }
                .buttonStyle(CircleIconButtonStyle(size: 28))
                .keyboardShortcut(.cancelAction)
                .help("Close")
                .padding(16)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Settings")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.tertiary)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            ForEach(Pane.allCases) { item in
                Button { pane = item } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.icon)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 18)
                            .foregroundStyle(pane == item ? Theme.ink : Theme.secondary)
                        Text(item.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(pane == item ? Theme.ink : Theme.ink.opacity(0.7))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(Capsule().fill(pane == item ? Theme.chip : .clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.top, 24)
        .padding(.horizontal, 12)
        .frame(width: 190)
    }

    @ViewBuilder
    private var content: some View {
        @Bindable var bvm = vm
        switch pane {
        case .library:
            card {
                if vm.libraryFolders.isEmpty {
                    Text("No music folders yet.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                        .padding(.vertical, 6)
                }
                ForEach(vm.libraryFolders) { folder in
                    folderRow(folder)
                }
                HStack(spacing: 8) {
                    Button { addFolder() } label: { Label("Add folder", systemImage: "plus") }
                        .buttonStyle(PillButtonStyle(kind: .secondary))
                    Button { Task { await vm.rescanLibraryNow() } } label: {
                        Label("Rescan now", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                    .disabled(vm.isScanning)
                    if vm.isScanning { ProgressView().controlSize(.small) }
                }
                .padding(.top, 6)
            }
            card {
                toggleRow("Watch for changes",
                          detail: "Pick up new, moved or deleted files on their own.",
                          isOn: $bvm.autoRescanEnabled)
                if vm.autoRescanEnabled {
                    divider
                    optionRow("Check every", detail: "How often Lyra looks at your folders.") {
                        HStack(spacing: 10) {
                            TickSlider(
                                value: (vm.autoRescanInterval - 5) / 175,
                                height: 16,
                                spacing: 2.5,
                                onScrub: { vm.autoRescanInterval = 5 + ($0 * 175 / 5).rounded() * 5 }
                            )
                            .frame(width: 140)
                            Text("\(Int(vm.autoRescanInterval))s")
                                .font(.system(size: 13, weight: .medium).monospacedDigit())
                                .foregroundStyle(Theme.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }
            }

        case .playback:
            card {
                toggleRow("Shuffle", detail: "Play the queue in a random order.", isOn: $bvm.isShuffleEnabled)
                divider
                optionRow("Repeat", detail: "What happens at the end of the queue or song.") {
                    HStack(spacing: 4) {
                        ForEach(RepeatMode.allCases, id: \.self) { mode in
                            Chip(title: mode.label, isSelected: vm.repeatMode == mode) { vm.repeatMode = mode }
                        }
                    }
                }
            }

        case .lyrics:
            card {
                toggleRow("Smart matching",
                          detail: "If a song isn't found, retry with cleaner titles and artists (no \"feat.\", \"remastered\"…).",
                          isOn: $bvm.lyricsSmartMatchingEnabled)
            }
            Text("Lyrics come from lrclib.net and are saved next to each song as an .lrc file, so they work offline.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.tertiary)
                .padding(.horizontal, 4)

        case .updates:
            card {
                toggleRow("Check on launch", detail: "Look for a new release each time Lyra opens.",
                          isOn: $bvm.autoCheckUpdatesOnLaunch)
                divider
                optionRow("Releases from", detail: "GitHub repository, as owner/repo.") {
                    TextField("owner/repo", text: $bvm.updatesRepoSlug)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 12)
                        .frame(width: 200, height: 30)
                        .background(Capsule().fill(Theme.raised))
                }
                divider
                HStack(spacing: 10) {
                    Button { Task { await vm.checkForUpdatesNow() } } label: { Text("Check now") }
                        .buttonStyle(PillButtonStyle(kind: .secondary))
                        .disabled(vm.isCheckingUpdates)
                    if vm.isCheckingUpdates { ProgressView().controlSize(.small) }
                    if let message = vm.updateMessage, !message.isEmpty {
                        Text(message)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    if let url = vm.updateURL {
                        Button("Open release") { NSWorkspace.shared.open(url) }
                            .buttonStyle(PillButtonStyle())
                    }
                }
            }

        case .advanced:
            card {
                toggleRow("Diagnostics log", detail: "Write a log file to help track down problems.",
                          isOn: $bvm.diagnosticsLoggingEnabled)
                if let path = DiagnosticsLogger.logFileURL()?.path {
                    divider
                    optionRow("Log file", detail: path) {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                        }
                        .buttonStyle(PillButtonStyle(kind: .secondary))
                    }
                }
            }
        }
    }

    // MARK: - Building blocks

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tileBackground(radius: 20)
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1)
    }

    private func optionRow<Control: View>(_ title: String, detail: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            control()
        }
    }

    private func toggleRow(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        optionRow(title, detail: detail) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Theme.ink)
        }
    }

    private func folderRow(_ folder: LibraryFolder) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.raised))
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.displayName)
                    .font(.system(size: 14, weight: .medium))
                Text(folder.path)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            Text("\(vm.trackCount(in: folder)) tracks")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.secondary)
            Button { Task { await vm.removeFolder(folder) } } label: { Image(systemName: "minus") }
                .buttonStyle(CircleIconButtonStyle(size: 26))
                .help("Remove from library (files stay on disk)")
        }
    }

    private func addFolder() {
        guard let url = AppKitPrompts.chooseMusicFolder() else { return }
        Task { await vm.loadFolder(url) }
    }
}
