import SwiftUI

struct DebugView: View {
    @Environment(PlayerViewModel.self) private var vm
    var onClose: (() -> Void)? = nil
    @State private var copyFeedback: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Debug")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    copyAllInfo()
                } label: {
                    Label("Copy All", systemImage: "doc.on.clipboard")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Copy all debug info to clipboard")

                Button {
                    onClose?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader("Track Metadata")
                    metadataSection

                    Divider()

                    sectionHeader("Artwork")
                    artworkSection

                    Divider()

                    sectionHeader("Lyrics")
                    lyricsSection

                    Divider()

                    sectionHeader("API Request")
                    apiSection

                    Divider()

                    sectionHeader("Library")
                    librarySection
                }
                .padding(16)
            }
        }
        .padding(.top, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.canvas)
        .overlay(copyToast, alignment: .bottom)
    }

    // MARK: - Sections

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let t = vm.currentTrack {
                debugRow("Title",    t.title)
                debugRow("Artist",   t.artist)
                debugRow("Album",    t.album)
                debugRow("Duration", String(format: "%.2fs", t.duration))
                debugRow("File",     t.url.lastPathComponent)
                debugRow("Path",     t.url.path, copyable: true)
            } else {
                Text("No track selected")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var artworkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                if let img = vm.currentTrack?.artwork {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 4) {
                        debugRow("Status", "Loaded ✓")
                        if let data = vm.currentTrack?.artworkData {
                            debugRow("Size", "\(data.count / 1024) KB")
                            debugRow("Pixels", "\(Int(img.size.width))×\(Int(img.size.height))")
                            let magic = data.prefix(4)
                            let fmt = magic.starts(with: [0xFF, 0xD8]) ? "JPEG"
                                    : magic.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "PNG"
                                    : "Unknown"
                            debugRow("Format", fmt)
                        }
                    }
                } else {
                    Image(systemName: "photo.slash")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                        .frame(width: 72, height: 72)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 4) {
                        if vm.currentTrack != nil {
                            debugRow("Status", "Not found in metadata")
                                .foregroundStyle(.orange)
                        } else {
                            Text("No track").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Raw metadata keys from all formats
            if !vm.debugArtworkKeys.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RAW METADATA KEYS")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(vm.debugArtworkKeys, id: \.self) { key in
                                Text(key)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.primary.opacity(0.75))
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                    }
                    .frame(maxHeight: 120)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private var lyricsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch vm.lyricsState {
            case .idle:
                debugRow("State", "Idle")
            case .loading:
                debugRow("State", "Loading…")
            case .loaded(let lines):
                debugRow("State", "Loaded ✓")
                debugRow("Lines", "\(lines.count)")
                if let first = lines.first {
                    debugRow("First line @", String(format: "%.2fs", first.timestamp))
                    debugRow("First text", "\"\(first.text)\"")
                }
            case .plain(let text):
                debugRow("State", "Loaded (plain) ✓")
                let plainLines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
                debugRow("Lines", "\(plainLines.count)")
                if let first = plainLines.first {
                    debugRow("First text", "\"\(first)\"")
                }
            case .notFound:
                debugRow("State", "Not Found")
                    .foregroundStyle(.orange)
            case .error(let msg):
                debugRow("State", "Error")
                    .foregroundStyle(.red)
                debugRow("Message", msg)
                    .foregroundStyle(.red)
            }

            if let status = vm.debugLyricsHTTPStatus {
                debugRow("HTTP Status", "\(status)")
                    .foregroundStyle(status == 200 ? Color.primary : Color.orange)
            }

            if let track = vm.currentTrack {
                let lrcURL = track.url.deletingPathExtension().appendingPathExtension("lrc")
                debugRow("Local .lrc", FileManager.default.fileExists(atPath: lrcURL.path) ? "Found ✓" : "Not found")
            }

            if let json = vm.debugLyricsRawJSON {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RAW RESPONSE (first 500 chars)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                    Text(json)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.75))
                        .textSelection(.enabled)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private var apiSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let track = vm.currentTrack {
                let url = buildDebugURL(for: track)
                debugRow("URL", url, copyable: true)
                HStack(spacing: 12) {
                    Button("Open in Browser") {
                        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)

                    if track.title.contains(" - ") {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("⚠ Title contains \" - \" — artist may be in the title")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } else {
                Text("No track selected").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            debugRow("Total tracks", "\(vm.tracks.count)")
            debugRow("Filtered",     "\(vm.filteredTracks.count)")
            debugRow("Scanning",     vm.isScanning ? "Yes" : "No")
            if let path = UserDefaults.standard.string(forKey: "lyra.musicFolderPath") {
                debugRow("Folder", path, copyable: true)
            } else {
                debugRow("Folder", "None saved")
            }
            // Tracks without artwork
            let noArt = vm.tracks.filter { $0.artworkData == nil }.count
            debugRow("Missing artwork", "\(noArt) / \(vm.tracks.count)")
                .foregroundStyle(noArt > 0 ? .orange : .primary)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.8)
    }

    @discardableResult
    private func debugRow(_ label: String, _ value: String, copyable: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label + ":")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if copyable {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                    withAnimation { copyFeedback = "Copied!" }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { copyFeedback = nil }
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var copyToast: some View {
        Group {
            if let msg = copyFeedback {
                Text(msg)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private func copyAllInfo() {
        var lines: [String] = ["=== Lyra Debug Report ===", ""]

        lines.append("--- Track Metadata ---")
        if let t = vm.currentTrack {
            lines.append("Title:    \(t.title)")
            lines.append("Artist:   \(t.artist)")
            lines.append("Album:    \(t.album)")
            lines.append(String(format: "Duration: %.2fs", t.duration))
            lines.append("File:     \(t.url.lastPathComponent)")
            lines.append("Path:     \(t.url.path)")
        } else {
            lines.append("No track selected")
        }

        lines.append("")
        lines.append("--- Artwork ---")
        if let t = vm.currentTrack {
            if let data = t.artworkData, let img = t.artwork {
                lines.append("Status: Loaded")
                lines.append("Size:   \(data.count / 1024) KB")
                lines.append("Pixels: \(Int(img.size.width))×\(Int(img.size.height))")
            } else {
                lines.append("Status: Not found in metadata")
            }
        }

        lines.append("")
        lines.append("--- Lyrics ---")
        switch vm.lyricsState {
        case .idle:       lines.append("State: Idle")
        case .loading:    lines.append("State: Loading…")
        case .loaded(let l):
            lines.append("State: Loaded")
            lines.append("Lines: \(l.count)")
            if let f = l.first { lines.append("First: \"\(f.text)\" @ \(String(format: "%.2f", f.timestamp))s") }
        case .plain(let text):
            let plainLines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
            lines.append("State: Loaded (plain)")
            lines.append("Lines: \(plainLines.count)")
            if let first = plainLines.first { lines.append("First: \"\(first)\"") }
        case .notFound:   lines.append("State: Not Found")
        case .error(let m): lines.append("State: Error — \(m)")
        }
        if let t = vm.currentTrack {
            let lrc = t.url.deletingPathExtension().appendingPathExtension("lrc")
            lines.append("Local .lrc: \(FileManager.default.fileExists(atPath: lrc.path) ? "Found" : "Not found")")
        }

        if !vm.debugArtworkKeys.isEmpty {
            lines.append("")
            lines.append("--- Raw Metadata Keys ---")
            vm.debugArtworkKeys.forEach { lines.append($0) }
        }

        if let status = vm.debugLyricsHTTPStatus {
            lines.append("HTTP Status: \(status)")
        }
        if let json = vm.debugLyricsRawJSON {
            lines.append("Raw JSON: \(json)")
        }

        lines.append("")
        lines.append("--- API Request ---")
        if let t = vm.currentTrack { lines.append("URL: \(buildDebugURL(for: t))") }

        lines.append("")
        lines.append("--- Library ---")
        lines.append("Total tracks:    \(vm.tracks.count)")
        lines.append("Filtered:        \(vm.filteredTracks.count)")
        lines.append("Missing artwork: \(vm.tracks.filter { $0.artworkData == nil }.count) / \(vm.tracks.count)")
        if let path = UserDefaults.standard.string(forKey: "lyra.musicFolderPath") {
            lines.append("Folder: \(path)")
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        withAnimation { copyFeedback = "Copied!" }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { copyFeedback = nil }
        }
    }

    private func buildDebugURL(for track: Track) -> String {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        var items: [URLQueryItem] = []
        if !track.title.isEmpty { items.append(.init(name: "track_name", value: track.title)) }
        if track.artist != "Unknown Artist" { items.append(.init(name: "artist_name", value: track.artist)) }
        if track.album  != "Unknown Album"  { items.append(.init(name: "album_name",  value: track.album))  }
        if track.duration > 0 { items.append(.init(name: "duration", value: "\(Int(track.duration))")) }
        components.queryItems = items
        return components.url?.absoluteString ?? "Invalid URL"
    }
}
