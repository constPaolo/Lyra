#if DEBUG
import AppKit

/// Puts the app in a given state on launch, for the README screenshots
/// (debug builds only). Driven by launch arguments; see
/// `scripts/readme_screenshots.sh`.
///
/// - `-LyraDemo <scene>`: `home`, `albums`, `album[:<name>]` (no name: the
///   playing song's album), `playlist:<name>`, `search:<query>`, `lyrics`,
///   `visualizer`, `settings`, `recap`, `onboarding`
/// - `-LyraDemoSeedHistory YES`: fill the listening history with five weeks
///   of made-up listens from the library (this process's own history file)
/// - `-LyraDemoSize <width>x<height>`: window content size
/// - `-LyraDemoPlay <title>`: start this song, muted
/// - `-LyraDemoSeek <seconds>`: jump into the song
/// - `-LyraDemoAppearance dark|light`
@MainActor
enum DemoMode {
    private static let args = UserDefaults.standard

    /// Appearance and window size; call as early as possible.
    static func prepare() {
        switch args.string(forKey: "LyraDemoAppearance") {
        case "dark":  NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default:      break
        }
        let size = (args.string(forKey: "LyraDemoSize") ?? "").split(separator: "x").compactMap { Double($0) }
        if size.count == 2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
                window.setContentSize(NSSize(width: size[0], height: size[1]))
                window.center()
            }
        }
    }

    static func run(_ vm: PlayerViewModel, openSettings: () -> Void) async {
        guard let scene = args.string(forKey: "LyraDemo"), scene != "onboarding" else { return }
        // Wait for the library scan to finish.
        for _ in 0..<150 where vm.tracks.isEmpty || vm.isScanning {
            try? await Task.sleep(for: .milliseconds(100))
        }

        if args.bool(forKey: "LyraDemoSeedHistory") { seedHistory(vm) }

        if let title = args.string(forKey: "LyraDemoPlay"),
           let track = vm.tracks.first(where: { $0.title.localizedCaseInsensitiveContains(title) }) {
            vm.play(track: track)
            vm.muteOutputForDemo()
            try? await Task.sleep(for: .milliseconds(800))
            let seek = args.double(forKey: "LyraDemoSeek")
            if seek > 0 { vm.seek(to: seek) }
        }

        let parts = scene.split(separator: ":", maxSplits: 1).map(String.init)
        let arg = parts.count > 1 ? parts[1] : ""
        switch parts[0] {
        case "albums":     vm.browsePage = .albumsIndex
        case "album":
            if arg.isEmpty, let track = vm.currentTrack {
                vm.goToAlbum(of: track)
            } else {
                vm.browsePage = .album(name: arg)
            }
        case "playlist":
            if let playlist = vm.playlists.first(where: { $0.name == arg }) {
                vm.browsePage = .playlist(id: playlist.id)
            }
        case "search":     vm.searchText = arg
        case "lyrics":     vm.mainView = .lyrics
        case "visualizer": vm.mainView = .visualizer
        case "settings":   openSettings()
        case "recap":      vm.browsePage = .recap
        default:           vm.browsePage = .home
        }
    }

    /// Five weeks of plausible listening: a few favorite artists, mostly in
    /// the evening, every day for the last twelve days. Deterministic.
    private static func seedHistory(_ vm: PlayerViewModel) {
        var seed: UInt64 = 42
        func random() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(1 << 53)
        }
        let favorites = ["Tame Impala": 7.0, "MadMan": 4, "Caparezza": 3, "Radiohead": 2]
        let tracks = vm.tracks.filter { $0.duration > 60 }
        let weights = tracks.map { track in
            favorites.first { track.artist.contains($0.key) }?.value ?? 1
        }
        let total = weights.reduce(0, +)
        func pickTrack() -> Track {
            var r = random() * total
            for (track, w) in zip(tracks, weights) { r -= w; if r <= 0 { return track } }
            return tracks[tracks.count - 1]
        }
        // Evenings and late nights, some mornings.
        let hours = [8, 9, 13, 18, 20, 21, 21, 22, 22, 23, 23, 0, 0, 1]

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var listens: [Listen] = []
        for daysAgo in 0..<35 {
            guard daysAgo < 12 || random() > 0.35, !tracks.isEmpty else { continue }
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            var time = calendar.date(byAdding: .hour, value: hours[Int(random() * Double(hours.count))], to: day)!
            for _ in 0..<(4 + Int(random() * 10)) {
                let track = pickTrack()
                let skipped = random() < 0.12
                let seconds = skipped ? 12 + random() * 15 : track.duration * (0.75 + 0.25 * random())
                guard time < Date() else { break }
                listens.append(Listen(path: track.url.standardizedFileURL.path, title: track.title,
                                      artist: track.artist, album: track.album, start: time,
                                      seconds: seconds, duration: track.duration))
                time.addTimeInterval(seconds + 2)
            }
        }
        vm.history.replaceAll(with: listens.sorted { $0.start < $1.start })
    }
}
#endif
