#if DEBUG
import AppKit

/// Puts the app in a given state on launch, for the README screenshots
/// (debug builds only). Driven by launch arguments; see
/// `scripts/readme_screenshots.sh`.
///
/// - `-LyraDemo <scene>`: `home`, `albums`, `album[:<name>]` (no name: the
///   playing song's album), `playlist:<name>`, `search:<query>`, `lyrics`,
///   `visualizer`, `settings`, `onboarding`
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
        default:           vm.browsePage = .home
        }
    }
}
#endif
