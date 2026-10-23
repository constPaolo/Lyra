import SwiftUI
import AppKit

struct LyricsView: View {
    @Environment(PlayerViewModel.self) private var vm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// True while the user is scrolling manually; auto-follow is suspended and
    /// resumes (re-centering on the current line) a few seconds after the last
    /// user interaction.
    @State private var autoScrollPaused = false
    @State private var resumeAutoScrollTask: Task<Void, Never>?

    var body: some View {
        Group {
            switch vm.lyricsState {
            case .idle:
                idleView
            case .loading:
                loadingView
            case .loaded(let lines):
                scrollingLyrics(lines: lines)
            case .plain(let text):
                plainLyricsView(text)
            case .notFound:
                failureView(icon: "music.note.list", message: "No lyrics found")
            case .error(let msg):
                failureView(icon: "exclamationmark.circle", message: msg)
            }
        }
    }

    // MARK: - States

    private var idleView: some View {
        statusView(icon: "music.note", message: "Select a track to see lyrics")
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.regular)
            Text("Searching lyrics…")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }

    private func statusView(icon: String, message: String) -> some View {
        EmptyStateView(icon: icon, text: message)
            .transition(.opacity)
    }

    private func failureView(icon: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(Theme.tertiary)
            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            if vm.currentTrack != nil {
                HStack(spacing: 8) {
                    Button("Search manually") { vm.isShowingManualSearch = true }
                        .buttonStyle(PillButtonStyle())
                    Button("Retry") { vm.reloadLyrics() }
                        .buttonStyle(PillButtonStyle(kind: .secondary))
                    Button("Edit / Import") { vm.isShowingLyricsEditor = true }
                        .buttonStyle(PillButtonStyle(kind: .secondary))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 130)
        .transition(.opacity)
    }

    private func plainLyricsView(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Kicker(text: "Unsynced lyrics")
                Spacer()
                Button("Edit / Import") { vm.isShowingLyricsEditor = true }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                Button("Search manually") { vm.isShowingManualSearch = true }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)

            ScrollView(.vertical, showsIndicators: true) {
                Text(text)
                    .font(.system(size: 22, weight: .medium))
                    .lineSpacing(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32)
                    .padding(.top, 6)
                    .padding(.bottom, 150)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .transition(.opacity)
    }

    // MARK: - Scrolling lyrics

    private func scrollingLyrics(lines: [LyricLine]) -> some View {
        GeometryReader { geo in
            let hPad = max(32, min(80, geo.size.width * 0.08))
            // Half-height spacers let the first and last lines reach the center;
            // the bottom one also clears the player bar.
            let vPad = geo.size.height * 0.45
            let bottomPad = vPad + 130
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    // Not lazy: scrollTo would have to estimate unlaid-out lines
                    // and long jumps would land off-center.
                    VStack(spacing: 0) {
                        Spacer(minLength: vPad)

                        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                            lyricLine(line: line, index: index, allLines: lines, hPad: hPad)
                        }

                        Spacer(minLength: bottomPad)
                    }
                }
                .onChange(of: vm.currentLyricIndex) { _, newIndex in
                    guard !autoScrollPaused, newIndex >= 0, newIndex < lines.count else { return }
                    withAnimation(reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.55, dampingFraction: 0.85)) {
                        proxy.scrollTo(lines[newIndex].id, anchor: .center)
                    }
                }
                .onScrollPhaseChange { _, newPhase in
                    guard newPhase == .interacting || newPhase == .tracking else { return }
                    autoScrollPaused = true
                    resumeAutoScrollTask?.cancel()
                    resumeAutoScrollTask = Task {
                        try? await Task.sleep(for: .seconds(4))
                        guard !Task.isCancelled else { return }
                        autoScrollPaused = false
                        let idx = vm.currentLyricIndex
                        guard idx >= 0, idx < lines.count else { return }
                        withAnimation(reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.55, dampingFraction: 0.85)) {
                            proxy.scrollTo(lines[idx].id, anchor: .center)
                        }
                    }
                }
                .onAppear {
                    autoScrollPaused = false
                    resumeAutoScrollTask?.cancel()
                    let idx = vm.currentLyricIndex
                    guard idx >= 0, idx < lines.count else { return }
                    proxy.scrollTo(lines[idx].id, anchor: .center)
                }
            }
        }
        .transition(.opacity)
    }

    private func lyricLine(line: LyricLine, index: Int, allLines: [LyricLine], hPad: CGFloat) -> some View {
        let currentIdx = vm.currentLyricIndex
        let isCurrent  = index == currentIdx
        let isPast     = index < currentIdx

        return Text(line.text)
            // Every line uses the active size and inactive ones are scaled down,
            // so a line becoming current never re-wraps.
            .font(Theme.display(34))
            .tracking(Theme.displayTracking(34))
            .foregroundStyle(
                isCurrent ? Theme.ink : Theme.ink.opacity(isPast ? 0.16 : 0.28)
            )
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .scaleEffect(isCurrent ? 1.0 : 0.82, anchor: .center)
            .padding(.vertical, 10)
            .padding(.horizontal, hPad)
            .id(line.id)
            .contentShape(Rectangle())
            .onTapGesture { vm.seek(to: line.timestamp) }
            .animation(reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.35, dampingFraction: 0.72), value: currentIdx)
    }
}

struct LyricsEditorSheet: View {
    @Environment(PlayerViewModel.self) private var vm
    @Binding var isPresented: Bool

    @State private var text: String = ""
    @State private var initialized = false

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Edit / Import Lyrics")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button("Close") { isPresented = false }
            }

            if let path = vm.currentTrackLyricsFilePath() {
                Text(path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
            }

            TextEditor(text: $text)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Theme.tile, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

            HStack {
                Button("Reload from current") {
                    text = vm.editableLyricsText()
                }
                .buttonStyle(.bordered)

                Button("Clear local lyrics") {
                    text = ""
                    vm.saveManualLyricsText("")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Save") {
                    vm.saveManualLyricsText(text)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(minWidth: 700, minHeight: 500)
        .task {
            guard !initialized else { return }
            initialized = true
            text = vm.editableLyricsText()
        }
    }
}

struct ManualLyricsSearchSheet: View {
    @Environment(PlayerViewModel.self) private var vm
    @Binding var isPresented: Bool

    @State private var trackName: String = ""
    @State private var artistName: String = ""
    @State private var initialized = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Manual Lyrics Search")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button("Close") { isPresented = false }
            }

            HStack(spacing: 8) {
                TextField("Track name", text: $trackName)
                TextField("Artist (optional)", text: $artistName)
                Button("Search") {
                    Task { await runSearch() }
                }
                .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 8) {
                Button("Open Query In Browser") { openSearchInBrowser() }
                    .buttonStyle(.bordered)
                Spacer()
                if vm.isManualLyricsSearchLoading {
                    ProgressView()
                } else if let err = vm.manualLyricsSearchError {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }
            }

            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if vm.manualLyricsResults.isEmpty && !vm.isManualLyricsSearchLoading {
                        Text("No results yet.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.top, 18)
                    } else {
                        ForEach(vm.manualLyricsResults) { result in
                            resultRow(result)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            }
        }
        .padding(16)
        .frame(minWidth: 680, minHeight: 440)
        .task {
            guard !initialized else { return }
            initialized = true
            if let track = vm.currentTrack {
                trackName = track.title
                artistName = track.artist == "Unknown Artist" ? "" : track.artist
                await runSearch()
            }
        }
    }

    private func resultRow(_ result: LyricsSearchResult) -> some View {
        let details = resultDetails(result)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(result.trackName)
                    .font(.system(size: 14, weight: .semibold))
                if !result.artistName.isEmpty {
                    Text("• \(result.artistName)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if hasSyncedLyrics(result) {
                    Kicker(text: "Synced")
                } else if hasPlainLyrics(result) {
                    Kicker(text: "Plain")
                }
                Button("Use") {
                    vm.applyManualLyricsResult(result)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }

            if !details.isEmpty {
                Text(details)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if let preview = lyricsPreview(result) {
                Text(preview)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.tile, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func runSearch() async {
        await vm.searchLyricsManually(trackName: trackName, artistName: artistName)
    }

    private func openSearchInBrowser() {
        let track = trackName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !track.isEmpty else { return }
        var components = URLComponents(string: "https://lrclib.net/api/search")
        var items: [URLQueryItem] = [.init(name: "track_name", value: track)]
        let artist = artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !artist.isEmpty {
            items.append(.init(name: "artist_name", value: artist))
        }
        components?.queryItems = items
        if let url = components?.url {
            NSWorkspace.shared.open(url)
        }
    }

    private func hasSyncedLyrics(_ result: LyricsSearchResult) -> Bool {
        guard let synced = result.syncedLyrics else { return false }
        return !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func hasPlainLyrics(_ result: LyricsSearchResult) -> Bool {
        guard let plain = result.plainLyrics else { return false }
        return !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func lyricsPreview(_ result: LyricsSearchResult) -> String? {
        if let synced = result.syncedLyrics, !synced.isEmpty {
            let lines = LRCParser.parse(synced)
            if let first = lines.first?.text, !first.isEmpty { return first }
        }
        if let plain = result.plainLyrics, !plain.isEmpty {
            return plain.components(separatedBy: .newlines).first(where: { !$0.isEmpty })
        }
        return nil
    }

    private func resultDetails(_ result: LyricsSearchResult) -> String {
        var details: [String] = []
        if !result.albumName.isEmpty { details.append(result.albumName) }
        if let d = result.duration, d > 0 { details.append("\(Int(d))s") }
        return details.joined(separator: " • ")
    }
}
