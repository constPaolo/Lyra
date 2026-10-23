import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(PlayerViewModel.self) private var vm
    @Binding var isPresented: Bool

    var body: some View {
        @Bindable var bvm = vm

        VStack(spacing: 12) {
            HStack {
                Text("Settings")
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                Button("Done") { isPresented = false }
            }

            Form {
                Section("Lyrics") {
                    Toggle("Smart matching fallback", isOn: $bvm.lyricsSmartMatchingEnabled)
                    Text("Try multiple title/artist variants before showing Not Found.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Section("Playback") {
                    Toggle("Shuffle", isOn: $bvm.isShuffleEnabled)
                    Picker("Repeat mode", selection: $bvm.repeatMode) {
                        ForEach(RepeatMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Library") {
                    Toggle("Auto-rescan library", isOn: $bvm.autoRescanEnabled)
                    HStack {
                        Slider(value: $bvm.autoRescanInterval, in: 5...180, step: 5)
                        Text("\(Int(bvm.autoRescanInterval))s")
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 46, alignment: .trailing)
                    }
                    Button("Rescan now") {
                        Task { await vm.rescanLibraryNow() }
                    }
                }

                Section("Updates") {
                    TextField("GitHub repo (owner/repo)", text: $bvm.updatesRepoSlug)
                    Toggle("Check updates on launch", isOn: $bvm.autoCheckUpdatesOnLaunch)
                    HStack(spacing: 10) {
                        Button("Check now") {
                            Task { await vm.checkForUpdatesNow() }
                        }
                        if vm.isCheckingUpdates {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }
                    if let message = vm.updateMessage, !message.isEmpty {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    if let url = vm.updateURL {
                        Button("Open latest release") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }

                Section("Diagnostics") {
                    Toggle("Enable diagnostics logging", isOn: $bvm.diagnosticsLoggingEnabled)
                    if let path = DiagnosticsLogger.logFileURL()?.path {
                        Text(path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Button("Reveal log file in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 540)
    }
}
