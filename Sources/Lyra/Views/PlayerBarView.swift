import SwiftUI
import AppKit

struct PlayerBarView: View {
    @Environment(PlayerViewModel.self) private var vm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isScrubbing = false
    @State private var scrubTime: Double = 0
    @State private var showVolumePopover = false
    @State private var volumeBeforeMute: Float = 0.7

    var body: some View {
        GeometryReader { geo in
            let isNarrow = geo.size.width < 760

            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    nowPlaying
                        .frame(maxWidth: .infinity, alignment: .leading)
                    transport
                    HStack(spacing: 6) {
                        lyricsToggle
                        visualizerToggle
                        shuffleToggle
                        repeatToggle
                        if isNarrow { volumeButton } else { volumeControl.padding(.leading, 6) }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                seekRow
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .tileBackground()
        }
        .frame(height: 112)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        // Content scrolls under the bar: fade it out instead of showing through.
        .background {
            VStack(spacing: 0) {
                LinearGradient(colors: [Theme.canvas.opacity(0), Theme.canvas], startPoint: .top, endPoint: .bottom)
                    .frame(height: 28)
                Theme.canvas
            }
            .padding(.top, -28)
            .allowsHitTesting(false)
        }
        .onAppear { if vm.volume > 0.001 { volumeBeforeMute = vm.volume } }
    }

    // MARK: - Now playing

    private var nowPlaying: some View {
        HStack(spacing: 12) {
            ArtworkView(image: vm.currentTrack?.artwork, radius: 12)
                .frame(width: 44, height: 44)
                .raisedShadow()
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.currentTrack?.title ?? "Nothing playing")
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .onTapGesture {
                        if let track = vm.currentTrack { vm.goToAlbum(of: track) }
                    }
                    .help("Go to album")
                Text(vm.currentTrack?.artist ?? "—")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .onTapGesture {
                        if let track = vm.currentTrack { vm.goToArtist(of: track) }
                    }
                    .help("Go to artist")
            }
            if let track = vm.currentTrack {
                Button { vm.toggleLiked(track) } label: {
                    Image(systemName: vm.isLiked(track) ? "heart.fill" : "heart")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(vm.isLiked(track) ? Theme.ink : Theme.tertiary)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(vm.isLiked(track) ? "Unlike" : "Like")
            }
        }
    }

    // MARK: - Transport

    private var transport: some View {
        HStack(spacing: 18) {
            Button { vm.playPrevious() } label: {
                Image(systemName: "backward.fill").font(.system(size: 15))
            }
            .buttonStyle(GlyphButtonStyle())
            .help("Previous track")

            Button { vm.togglePlayPause() } label: {
                Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.canvas)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.ink))
            }
            .buttonStyle(GlyphButtonStyle())
            .help(vm.isPlaying ? "Pause" : "Play")

            Button { vm.playNext() } label: {
                Image(systemName: "forward.fill").font(.system(size: 15))
            }
            .buttonStyle(GlyphButtonStyle())
            .help("Next track")
        }
        .fixedSize()
    }

    // MARK: - Seek

    private var seekRow: some View {
        let shown = isScrubbing ? scrubTime : vm.currentTime
        return HStack(spacing: 12) {
            Text(vm.formatTime(shown))
                .timeLabel()
                .rollingDigits(floor(shown))
            TickSlider(
                value: vm.duration > 0 ? max(0, min(shown / vm.duration, 1)) : 0,
                height: 18,
                onScrub: { f in
                    isScrubbing = true
                    scrubTime = f * vm.duration
                },
                onCommit: { f in
                    vm.seek(to: f * vm.duration)
                    isScrubbing = false
                }
            )
            Text(vm.formattedDuration)
                .timeLabel()
        }
    }

    // MARK: - Volume

    private var volumeControl: some View {
        HStack(spacing: 8) {
            muteButton
            TickSlider(
                value: Double(vm.volume),
                height: 14,
                spacing: 2.5,
                onScrub: { vm.setVolume(Float($0)) }
            )
            .frame(width: 72)
            Text("\(Int((vm.volume * 100).rounded()))")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .rollingDigits(Double((vm.volume * 100).rounded()))
                .frame(width: 24, alignment: .trailing)
        }
        .help("Volume")
    }

    private var volumeButton: some View {
        Button { showVolumePopover.toggle() } label: {
            Image(systemName: volumeSymbol)
        }
        .buttonStyle(CircleIconButtonStyle(size: 30))
        .help("Volume")
        .popover(isPresented: $showVolumePopover, arrowEdge: .top) {
            volumeControl
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
    }

    private var muteButton: some View {
        Button {
            if vm.volume > 0.001 {
                volumeBeforeMute = vm.volume
                vm.setVolume(0)
            } else {
                vm.setVolume(volumeBeforeMute > 0.001 ? volumeBeforeMute : 0.5)
            }
        } label: {
            Image(systemName: volumeSymbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .frame(width: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(vm.volume > 0.001 ? "Mute" : "Unmute")
    }

    private var volumeSymbol: String {
        if vm.volume <= 0.001 { return "speaker.slash.fill" }
        if vm.volume < 0.34 { return "speaker.fill" }
        if vm.volume < 0.67 { return "speaker.wave.1.fill" }
        return "speaker.wave.2.fill"
    }

    // MARK: - Toggles

    private var lyricsToggle: some View {
        toggleButton(icon: "quote.bubble", isActive: vm.mainView == .lyrics,
                     help: vm.mainView == .lyrics ? "Show library" : "Show lyrics") {
            withAnimation(reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 0.2)) {
                vm.mainView = (vm.mainView == .lyrics) ? .browse : .lyrics
            }
        }
    }

    private var visualizerToggle: some View {
        toggleButton(icon: "circle.grid.3x3", isActive: vm.mainView == .visualizer,
                     help: vm.mainView == .visualizer ? "Show library" : "Visualizer") {
            withAnimation(reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 0.2)) {
                vm.mainView = (vm.mainView == .visualizer) ? .browse : .visualizer
            }
        }
    }

    private var shuffleToggle: some View {
        toggleButton(icon: "shuffle", isActive: vm.isShuffleEnabled,
                     help: vm.isShuffleEnabled ? "Shuffle on" : "Shuffle off") {
            vm.toggleShuffle()
        }
    }

    private var repeatToggle: some View {
        toggleButton(icon: vm.repeatMode.symbolName, isActive: vm.repeatMode != .off,
                     help: "Repeat: \(vm.repeatMode.label)") {
            vm.cycleRepeatMode()
        }
    }

    private func toggleButton(icon: String, isActive: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
        }
        .buttonStyle(CircleIconButtonStyle(isActive: isActive, size: 30))
        .help(help)
    }
}

private extension Text {
    func timeLabel() -> some View {
        self
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.secondary)
            .frame(width: 40)
    }
}
