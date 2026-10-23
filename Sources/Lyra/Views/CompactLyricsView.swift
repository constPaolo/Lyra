import SwiftUI
import AppKit

/// Small always-on-top window: the current lyric line with its neighbours and
/// a minimal transport bar.
struct CompactLyricsView: View {
    @Environment(PlayerViewModel.self) private var vm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Lines shown before and after the current one.
    private let context = 2

    /// Shows the library list instead of the lyrics while a track is playing.
    @State private var showLibrary = false

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            if vm.currentTrack == nil {
                compactTrackList
            } else {
                VStack(spacing: 0) {
                    if showLibrary {
                        compactTrackList
                    } else {
                        lyricsArea
                    }
                    miniBar
                }
            }
        }
        .onAppear {
            // The window may not exist yet when launching straight into compact mode.
            vm.applyWindowPin()
        }
    }

    // MARK: - Track list

    @ViewBuilder
    private var compactTrackList: some View {
        @Bindable var bvm = vm
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("Library")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                pinButton
                exitButton
            }
            .padding(.horizontal, 12)
            .padding(.top, 34)
            .padding(.bottom, 8)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                TextField("Search", text: $bvm.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Capsule().fill(Theme.tile))
            .padding(.horizontal, 10)
            .padding(.bottom, 6)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 1) {
                    if vm.filteredTracks.isEmpty {
                        Text(vm.isScanning ? "Scanning…" : "No tracks")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.tertiary)
                            .padding(.top, 20)
                    } else {
                        ForEach(vm.filteredTracks) { track in
                            compactTrackRow(track)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
        }
    }

    private func compactTrackRow(_ track: Track) -> some View {
        HStack(spacing: 8) {
            ArtworkView(image: track.artwork, radius: 7)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if !track.artist.isEmpty && track.artist != "Unknown Artist" {
                    Text(track.artist)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(vm.currentTrack?.id == track.id ? Theme.tile : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            vm.play(track: track)
            showLibrary = false
        }
    }

    // MARK: - Lyrics

    /// Grows with the window's width, capped by its height.
    private func compactFontSize(for size: CGSize) -> CGFloat {
        let byWidth  = size.width / 13
        let byHeight = size.height / 9
        return max(13, min(byWidth, byHeight, 38))
    }

    @ViewBuilder
    private var lyricsArea: some View {
        GeometryReader { geo in
            let fontSize = compactFontSize(for: geo.size)
            let hPad = max(10, geo.size.width * 0.06)

            Group {
                switch vm.lyricsState {
                case .loaded(let lines):
                    compactLines(lines: lines, fontSize: fontSize)

                case .plain(let plain):
                    let first = plain
                        .components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .first(where: { !$0.isEmpty }) ?? plain
                    Text(first)
                        .font(Theme.display(fontSize))
                        .lineLimit(3)
                        .minimumScaleFactor(0.6)
                        .multilineTextAlignment(.center)

                case .loading:
                    ProgressView().controlSize(.small)

                default:
                    if let track = vm.currentTrack {
                        VStack(spacing: fontSize * 0.2) {
                            Text(track.title)
                                .font(Theme.display(fontSize))
                                .lineLimit(2)
                                .minimumScaleFactor(0.6)
                            Text(track.artist)
                                .font(.system(size: fontSize * 0.6, weight: .medium))
                                .foregroundStyle(Theme.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .multilineTextAlignment(.center)
                    } else {
                        Text("Nothing playing")
                            .font(.system(size: fontSize * 0.8, weight: .medium))
                            .foregroundStyle(Theme.tertiary)
                    }
                }
            }
            .padding(.horizontal, hPad)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Each line sits in a fixed slot offset by its distance from the current
    /// line; when the index advances the spring turns the offsets into a glide.
    /// Identity is the line index, so lines that stay visible keep their view.
    private func compactLines(lines: [LyricLine], fontSize: CGFloat) -> some View {
        let current = vm.currentLyricIndex
        let slotHeight = fontSize * 2.1
        // One hidden line on each side so entering lines fade in instead of popping.
        let start = max(0, current - context - 1)
        let end   = min(lines.count - 1, current + context + 1)

        return ZStack {
            if start <= end {
                ForEach(start..<(end + 1), id: \.self) { idx in
                    let distance = idx - current
                    lyricText(lines[idx].text, isCurrent: distance == 0, fontSize: fontSize)
                        .frame(height: slotHeight)
                        .scaleEffect(distance == 0 ? 1.0 : 0.86)
                        .opacity(slotOpacity(distance: distance))
                        .offset(y: CGFloat(distance) * slotHeight)
                        .contentShape(Rectangle())
                        .onTapGesture { vm.seek(to: lines[idx].timestamp) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(
            reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.45, dampingFraction: 0.85),
            value: current
        )
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.14),
                    .init(color: .black, location: 0.86),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    private func slotOpacity(distance: Int) -> Double {
        switch abs(distance) {
        case 0:  1.0
        case 1:  distance < 0 ? 0.25 : 0.4
        case 2:  distance < 0 ? 0.12 : 0.2
        default: 0
        }
    }

    private func lyricText(_ text: String, isCurrent: Bool, fontSize: CGFloat) -> some View {
        Text(text)
            .font(Theme.display(fontSize))
            .tracking(Theme.displayTracking(fontSize))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Mini bar

    private var miniBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                Text(vm.currentTrack?.title ?? "—")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    Button { vm.playPrevious() } label: {
                        Image(systemName: "backward.fill").font(.system(size: 10))
                    }
                    .buttonStyle(GlyphButtonStyle())
                    .help("Previous track")

                    Button { vm.togglePlayPause() } label: {
                        Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.canvas)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Theme.ink))
                    }
                    .buttonStyle(GlyphButtonStyle())
                    .help(vm.isPlaying ? "Pause" : "Play")

                    Button { vm.playNext() } label: {
                        Image(systemName: "forward.fill").font(.system(size: 10))
                    }
                    .buttonStyle(GlyphButtonStyle())
                    .help("Next track")

                    Button { showLibrary.toggle() } label: {
                        Image(systemName: showLibrary ? "quote.bubble" : "list.bullet")
                    }
                    .buttonStyle(CircleIconButtonStyle(isActive: showLibrary, size: 22))
                    .help(showLibrary ? "Show lyrics" : "Browse library")

                    pinButton
                    exitButton
                }
                .fixedSize()
                .padding(.leading, 8)
            }

            TickSlider(
                value: vm.duration > 0 ? max(0, min(vm.currentTime / vm.duration, 1)) : 0,
                height: 10,
                tickWidth: 1.5,
                spacing: 2,
                onCommit: { vm.seek(to: $0 * vm.duration) }
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .tileBackground(radius: 18)
        .padding(6)
    }

    private var pinButton: some View {
        Button { vm.isPinned.toggle() } label: {
            Image(systemName: vm.isPinned ? "pin.fill" : "pin")
        }
        .buttonStyle(CircleIconButtonStyle(isActive: vm.isPinned, size: 22))
        .help(vm.isPinned ? "Unpin window" : "Keep window on top")
    }

    private var exitButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                vm.isCompactMode = false
            }
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
        }
        .buttonStyle(CircleIconButtonStyle(size: 22))
        .help("Exit compact mode")
    }
}
