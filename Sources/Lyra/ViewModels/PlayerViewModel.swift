import Foundation
import AVFoundation
import SwiftUI
import AppKit
import MediaPlayer

@MainActor
@Observable
final class PlayerViewModel {
    private enum defaults {
        static let shuffleEnabled = "lyra.shuffleEnabled"
        static let repeatMode = "lyra.repeatMode"
        static let autoRescanEnabled = "lyra.autoRescanEnabled"
        static let autoRescanInterval = "lyra.autoRescanInterval"
        static let lyricsSmartMatchingEnabled = "lyra.lyricsSmartMatchingEnabled"
        static let diagnosticsLoggingEnabled = "lyra.diagnosticsLoggingEnabled"
        static let updatesRepoSlug = "lyra.updatesRepoSlug"
        static let autoCheckUpdatesOnLaunch = "lyra.autoCheckUpdatesOnLaunch"
        static let sidebarVisible = "lyra.sidebarVisible"
        static let compactMode = "lyra.isCompactMode"
        static let volume = "lyra.volume"
        static let musicFolderPath = "lyra.musicFolderPath" // legacy single-folder key
        static let libraryFolderPaths = "lyra.libraryFolderPaths"
        static let playlists = "lyra.playlists"
        static let likedTracks = "lyra.likedTracks"
        static let recentlyPlayed = "lyra.recentlyPlayed"
    }

    // MARK: - Public state

    var tracks: [Track] = []
    var filteredTracks: [Track] = []
    var libraryFolders: [LibraryFolder] = [] {
        didSet { persistLibraryFolders() }
    }
    var playlists: [Playlist] = [] {
        didSet {
            persistPlaylists()
            applySearch()
        }
    }
    /// Normalized paths of liked tracks, most-recently-liked first.
    var likedTrackPaths: [String] = [] {
        didSet { UserDefaults.standard.set(likedTrackPaths, forKey: Self.defaults.likedTracks) }
    }
    /// Normalized paths of recently played tracks, most-recent first.
    var recentlyPlayedPaths: [String] = [] {
        didSet { UserDefaults.standard.set(recentlyPlayedPaths, forKey: Self.defaults.recentlyPlayed) }
    }
    var selectedSource: LibrarySource = .allTracks {
        didSet { applySearch() }
    }
    var mainView: MainViewMode = .browse {
        didSet {
            if mainView == .visualizer { startVisualizerUpdates() }
            else { stopVisualizerUpdates() }
        }
    }
    var visualizerLevels: [Float] = Array(repeating: 0, count: AudioVisualizer.bandCount)
    var isShowingLyricsEditor: Bool = false
    var isShowingManualSearch: Bool = false
    var browsePage: BrowsePage = .home {
        didSet {
            syncSelectedSource()
            mainView = .browse
        }
    }
    var searchText: String = "" {
        didSet {
            applySearch()
            // Results replace the main area, so leave lyrics / visualizer.
            if !searchText.isEmpty, mainView != .browse { mainView = .browse }
        }
    }

    var currentTrack: Track?
    var isPlaying: Bool = false
    var currentTime: Double = 0
    var duration: Double = 0
    var volume: Float = 0.7
    var playbackQueue: [Track] = []
    var queueIndex: Int = -1
    var isShuffleEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isShuffleEnabled, forKey: Self.defaults.shuffleEnabled)
            rebuildQueueKeepingCurrent()
        }
    }
    var repeatMode: RepeatMode = .off {
        didSet { UserDefaults.standard.set(repeatMode.rawValue, forKey: Self.defaults.repeatMode) }
    }

    var lyricsState: LyricsState = .idle
    var currentLyricIndex: Int = -1
    var manualLyricsResults: [LyricsSearchResult] = []
    var isManualLyricsSearchLoading: Bool = false
    var manualLyricsSearchError: String? = nil

    // Debug info populated during scan and lyrics fetch
    var debugArtworkKeys: [String] = []       // raw Vorbis keys found during scan
    var debugLyricsHTTPStatus: Int? = nil     // last HTTP status from lrclib
    var debugLyricsRawJSON: String? = nil     // raw JSON response (truncated)

    var isSidebarVisible: Bool = true {
        didSet { UserDefaults.standard.set(isSidebarVisible, forKey: Self.defaults.sidebarVisible) }
    }
    var isCompactMode: Bool = false {
        didSet {
            UserDefaults.standard.set(isCompactMode, forKey: Self.defaults.compactMode)
            applyWindowPin()
        }
    }
    var isPinned: Bool = false {
        didSet { applyWindowPin() }
    }
    var isScanning: Bool = false
    var autoRescanEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(autoRescanEnabled, forKey: Self.defaults.autoRescanEnabled)
            restartLibraryWatcher()
        }
    }
    var autoRescanInterval: Double = 20 {
        didSet {
            autoRescanInterval = max(5, min(autoRescanInterval, 180))
            UserDefaults.standard.set(autoRescanInterval, forKey: Self.defaults.autoRescanInterval)
            restartLibraryWatcher()
        }
    }
    var lyricsSmartMatchingEnabled: Bool = true {
        didSet { UserDefaults.standard.set(lyricsSmartMatchingEnabled, forKey: Self.defaults.lyricsSmartMatchingEnabled) }
    }
    var diagnosticsLoggingEnabled: Bool = true {
        didSet {
            DiagnosticsLogger.setEnabled(diagnosticsLoggingEnabled)
            UserDefaults.standard.set(diagnosticsLoggingEnabled, forKey: Self.defaults.diagnosticsLoggingEnabled)
        }
    }
    var updatesRepoSlug: String = "" {
        didSet { UserDefaults.standard.set(updatesRepoSlug, forKey: Self.defaults.updatesRepoSlug) }
    }
    var autoCheckUpdatesOnLaunch: Bool = false {
        didSet { UserDefaults.standard.set(autoCheckUpdatesOnLaunch, forKey: Self.defaults.autoCheckUpdatesOnLaunch) }
    }
    var updateMessage: String? = nil
    var updateURL: URL? = nil
    var isCheckingUpdates: Bool = false

    // MARK: - Init

    init() {
        let d = UserDefaults.standard
        isCompactMode = d.bool(forKey: Self.defaults.compactMode)

        if d.object(forKey: Self.defaults.shuffleEnabled) != nil {
            isShuffleEnabled = d.bool(forKey: Self.defaults.shuffleEnabled)
        }
        if let raw = d.object(forKey: Self.defaults.repeatMode) as? Int,
           let mode = RepeatMode(rawValue: raw) {
            repeatMode = mode
        }
        if d.object(forKey: Self.defaults.autoRescanEnabled) != nil {
            autoRescanEnabled = d.bool(forKey: Self.defaults.autoRescanEnabled)
        }
        if d.object(forKey: Self.defaults.autoRescanInterval) != nil {
            autoRescanInterval = d.double(forKey: Self.defaults.autoRescanInterval)
        }
        if d.object(forKey: Self.defaults.lyricsSmartMatchingEnabled) != nil {
            lyricsSmartMatchingEnabled = d.bool(forKey: Self.defaults.lyricsSmartMatchingEnabled)
        }
        if d.object(forKey: Self.defaults.diagnosticsLoggingEnabled) != nil {
            diagnosticsLoggingEnabled = d.bool(forKey: Self.defaults.diagnosticsLoggingEnabled)
        }
        updatesRepoSlug = d.string(forKey: Self.defaults.updatesRepoSlug) ?? "constPaolo/Lyra"
        if d.object(forKey: Self.defaults.autoCheckUpdatesOnLaunch) != nil {
            autoCheckUpdatesOnLaunch = d.bool(forKey: Self.defaults.autoCheckUpdatesOnLaunch)
        }
        if d.object(forKey: Self.defaults.sidebarVisible) != nil {
            isSidebarVisible = d.bool(forKey: Self.defaults.sidebarVisible)
        }
        if d.object(forKey: Self.defaults.volume) != nil {
            volume = max(0, min(Float(d.double(forKey: Self.defaults.volume)), 1))
        }

        if let paths = d.array(forKey: Self.defaults.libraryFolderPaths) as? [String] {
            libraryFolders = deduplicatedFolders(paths: paths)
        }
        if let data = d.data(forKey: Self.defaults.playlists),
           let decoded = try? JSONDecoder().decode([Playlist].self, from: data) {
            playlists = decoded
        }
        if let liked = d.array(forKey: Self.defaults.likedTracks) as? [String] {
            likedTrackPaths = liked
        }
        if let recent = d.array(forKey: Self.defaults.recentlyPlayed) as? [String] {
            recentlyPlayedPaths = recent
        }

        DiagnosticsLogger.setEnabled(diagnosticsLoggingEnabled)
    }

    // MARK: - Private

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var lyricsTask: Task<Void, Never>?
    private var libraryWatcherTask: Task<Void, Never>?
    private let scanner  = MusicScanner()
    private let lyricsService = LyricsService()
    private let updateService = UpdateService()
    private let visualizer = AudioVisualizer()
    private var visualizerTimer: Timer?

    // MARK: - Window pin

    /// The window floats when pinned or in compact mode. Only the main window
    /// is touched; panels and sheets keep their own level.
    func applyWindowPin() {
        let level: NSWindow.Level = (isPinned || isCompactMode) ? .floating : .normal
        for window in NSApp.windows
        where !(window is NSPanel) && window.sheetParent == nil && window.canBecomeMain {
            window.level = level
        }
    }

    // MARK: - Remote commands (media keys + Control Center)

    func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.togglePlayPause() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.togglePlayPause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.playNext() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.playPrevious() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  let e = event as? MPChangePlaybackPositionCommandEvent
            else { return .commandFailed }
            let t = e.positionTime
            Task { @MainActor in self.seek(to: t) }
            return .success
        }
    }

    func updateNowPlaying() {
        var info: [String: Any] = [:]

        if let track = currentTrack {
            info[MPMediaItemPropertyTitle]  = track.title
            info[MPMediaItemPropertyArtist] = track.artist
            info[MPMediaItemPropertyAlbumTitle] = track.album
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
            info[MPMediaItemPropertyPlaybackDuration] = duration
            info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

            // No MPMediaItemArtwork: on macOS 26 it asserts main-actor isolation
            // from MediaPlayer's background queue and crashes.
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info.isEmpty ? nil : info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    // MARK: - Folder management

    func loadFolder(_ url: URL) async {
        let path = normalizedPath(for: url)
        if !libraryFolders.contains(where: { $0.path == path }) {
            libraryFolders.append(LibraryFolder(path: path))
        }
        selectedSource = .folder(path: path)
        restartLibraryWatcher()
        await scanLibraries(triggeredByWatcher: false)
    }

    func rescanLibraryNow() async {
        await scanLibraries(triggeredByWatcher: false)
    }

    func restoreLastFolder() async {
        if libraryFolders.isEmpty,
           let legacyPath = UserDefaults.standard.string(forKey: Self.defaults.musicFolderPath) {
            libraryFolders = deduplicatedFolders(paths: [legacyPath])
        }
        restartLibraryWatcher()
        await scanLibraries(triggeredByWatcher: false)
    }

    func removeFolder(_ folder: LibraryFolder) async {
        libraryFolders.removeAll { $0.path == folder.path }
        if case .folder(let selectedPath) = selectedSource {
            let prefix = folder.path + "/"
            if selectedPath == folder.path || selectedPath.hasPrefix(prefix) {
                selectedSource = .allTracks
            }
        }
        restartLibraryWatcher()
        await scanLibraries(triggeredByWatcher: false)
    }

    func trackCount(in folder: LibraryFolder) -> Int {
        trackCount(inFolderPath: folder.path)
    }

    func trackCount(inFolderPath path: String) -> Int {
        tracks.filter { trackBelongsToFolder($0, folderPath: path) }.count
    }

    var browsableFolders: [FolderBrowseItem] {
        guard !libraryFolders.isEmpty else { return [] }
        var rows: [FolderBrowseItem] = []

        for root in libraryFolders {
            rows.append(
                FolderBrowseItem(
                    path: root.path,
                    displayName: root.displayName,
                    depth: 0,
                    isRoot: true
                )
            )

            for descendantPath in descendantFolderPaths(forRootPath: root.path) {
                let depth = folderDepth(relativeTo: root.path, path: descendantPath)
                rows.append(
                    FolderBrowseItem(
                        path: descendantPath,
                        displayName: URL(fileURLWithPath: descendantPath).lastPathComponent,
                        depth: depth,
                        isRoot: false
                    )
                )
            }
        }
        return rows
    }

    // MARK: - Artists

    private func artistKey(for track: Track) -> String {
        let name = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Unknown Artist" : name
    }

    var artists: [ArtistGroup] {
        var counts: [String: Int] = [:]
        for track in tracks {
            counts[artistKey(for: track), default: 0] += 1
        }
        return counts
            .map { ArtistGroup(name: $0.key, trackCount: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Albums

    private func albumKey(for track: Track) -> String {
        let name = track.album.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Unknown Album" : name
    }

    var albums: [AlbumGroup] {
        var groups: [String: (artists: Set<String>, count: Int)] = [:]
        for track in tracks {
            let key = albumKey(for: track)
            var entry = groups[key] ?? (artists: [], count: 0)
            entry.artists.insert(artistKey(for: track))
            entry.count += 1
            groups[key] = entry
        }
        return groups
            .map { key, entry in
                AlbumGroup(
                    name: key,
                    artist: entry.artists.count == 1 ? entry.artists.first! : "Various Artists",
                    trackCount: entry.count
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Artwork from the artist's first track that has some.
    func artistArtwork(_ name: String) -> NSImage? {
        tracks.first(where: { artistKey(for: $0) == name && $0.artworkData != nil })?.thumbnail
    }

    /// Cover art for an album — the first track in the album that has artwork.
    func albumArtwork(_ name: String) -> NSImage? {
        tracks.first(where: { albumKey(for: $0) == name && $0.artworkData != nil })?.thumbnail
    }

    // MARK: - Browse page descriptors

    var selectedSourceTitle: String {
        switch selectedSource {
        case .allTracks:        return "All Tracks"
        case .liked:            return "Liked Songs"
        case .folder(let path): return URL(fileURLWithPath: path).lastPathComponent
        case .artist(let name): return name
        case .album(let name):  return name
        case .playlist(let id): return playlistName(for: id) ?? "Playlist"
        }
    }

    var selectedSourceSubtitle: String {
        switch selectedSource {
        case .allTracks: return "Library"
        case .liked:     return "Your favorites"
        case .folder:    return "Folder"
        case .artist:    return "Artist"
        case .album(let name):
            let group = albums.first(where: { $0.name == name })
            return group.map { "Album · \($0.artist)" } ?? "Album"
        case .playlist:  return "Playlist"
        }
    }

    var selectedSourceIcon: String {
        switch selectedSource {
        case .allTracks: return "music.note.list"
        case .liked:     return "heart.fill"
        case .folder:    return "folder.fill"
        case .artist:    return "music.mic"
        case .album:     return "square.stack"
        case .playlist:  return "music.note"
        }
    }

    func playAllInCurrentSource() {
        guard let first = filteredTracks.first else { return }
        play(track: first)
    }

    func shuffleCurrentSource() {
        guard let random = filteredTracks.randomElement() else { return }
        if !isShuffleEnabled { isShuffleEnabled = true }
        play(track: random, queue: filteredTracks)
    }

    /// Home quick action: resume the paused track, or restart the most recent one.
    func resumePlayback() {
        if currentTrack != nil {
            if !isPlaying { togglePlayPause() }
        } else if let track = recentlyPlayed.first ?? tracks.first {
            play(track: track)
        }
    }

    /// Home quick action: shuffle the entire library and start somewhere random.
    func shuffleAllAndPlay() {
        guard let random = tracks.randomElement() else { return }
        if !isShuffleEnabled { isShuffleEnabled = true }
        play(track: random, queue: tracks)
    }

    // MARK: - Search

    /// Library-wide results for `searchText`, best matches first.
    var searchResults: SearchResults {
        let query = SearchScore.fold(searchText)
        guard !query.isEmpty else { return SearchResults() }

        func ranked<T>(_ items: [T], limit: Int, score: (T) -> Double, name: (T) -> String) -> [(T, Double)] {
            items
                .map { ($0, score($0)) }
                .filter { $0.1 > 0 }
                .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : name($0.0).localizedCaseInsensitiveCompare(name($1.0)) == .orderedAscending }
                .prefix(limit)
                .map { $0 }
        }

        let songs = ranked(tracks, limit: 50, score: { t in
            max(SearchScore.score(t.title, query),
                SearchScore.score(t.artist, query) * 0.8,
                SearchScore.score(t.album, query) * 0.6)
        }, name: \.title)
        let artistHits = ranked(artists, limit: 12, score: { SearchScore.score($0.name, query) }, name: \.name)
        let albumHits = ranked(albums, limit: 12, score: { a in
            max(SearchScore.score(a.name, query), SearchScore.score(a.artist, query) * 0.7)
        }, name: \.name)
        let playlistHits = ranked(playlists, limit: 12, score: { SearchScore.score($0.name, query) }, name: \.name)

        // On ties, prefer the broader match: artist, then album, then song.
        var candidates: [(SearchHit, Double)] = []
        if let a = artistHits.first { candidates.append((.artist(a.0), a.1 + 0.03)) }
        if let a = albumHits.first { candidates.append((.album(a.0), a.1 + 0.02)) }
        if let p = playlistHits.first { candidates.append((.playlist(p.0), p.1 + 0.01)) }
        if let s = songs.first { candidates.append((.track(s.0), s.1)) }

        return SearchResults(
            top: candidates.max { $0.1 < $1.1 }?.0,
            songs: songs.map(\.0),
            artists: artistHits.map(\.0),
            albums: albumHits.map(\.0),
            playlists: playlistHits.map(\.0)
        )
    }

    /// Opens a search hit and clears the search so its page shows.
    func open(_ hit: SearchHit) {
        let page: BrowsePage
        switch hit {
        case .track(let track):
            let queue = searchResults.songs
            searchText = ""
            play(track: track, queue: queue)
            return
        case .artist(let artist):     page = .artist(name: artist.name)
        case .album(let album):       page = .album(name: album.name)
        case .playlist(let playlist): page = .playlist(id: playlist.id)
        }
        searchText = ""
        browsePage = page
    }

    // MARK: - Liked songs

    func isLiked(_ track: Track) -> Bool {
        likedTrackPaths.contains(normalizedPath(for: track.url))
    }

    func toggleLiked(_ track: Track) {
        let path = normalizedPath(for: track.url)
        if let idx = likedTrackPaths.firstIndex(of: path) {
            likedTrackPaths.remove(at: idx)
        } else {
            likedTrackPaths.insert(path, at: 0)
        }
        // Refresh so an unlike removes the row right away.
        if selectedSource == .liked { applySearch() }
    }

    var likedTracks: [Track] {
        let byPath = Dictionary(tracks.map { (normalizedPath(for: $0.url), $0) }, uniquingKeysWith: { first, _ in first })
        return likedTrackPaths.compactMap { byPath[$0] }
    }

    // MARK: - Recently played

    /// Resolves the stored recent paths back to tracks still present in the library.
    var recentlyPlayed: [Track] {
        let byPath = Dictionary(tracks.map { (normalizedPath(for: $0.url), $0) }, uniquingKeysWith: { first, _ in first })
        return recentlyPlayedPaths.compactMap { byPath[$0] }
    }

    private static let maxRecentlyPlayed = 30

    private func recordRecentlyPlayed(_ track: Track) {
        let path = normalizedPath(for: track.url)
        var paths = recentlyPlayedPaths
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        if paths.count > Self.maxRecentlyPlayed {
            paths = Array(paths.prefix(Self.maxRecentlyPlayed))
        }
        recentlyPlayedPaths = paths
    }

    // MARK: - Navigation

    func goToArtist(of track: Track) {
        browsePage = .artist(name: artistKey(for: track))
    }

    func goToAlbum(of track: Track) {
        browsePage = .album(name: albumKey(for: track))
    }

    private func syncSelectedSource() {
        switch browsePage {
        case .allTracks:        selectedSource = .allTracks
        case .liked:            selectedSource = .liked
        case .artist(let name): selectedSource = .artist(name: name)
        case .album(let name):  selectedSource = .album(name: name)
        case .folder(let path): selectedSource = .folder(path: path)
        case .playlist(let id): selectedSource = .playlist(id: id)
        case .home, .artistsIndex, .albumsIndex, .foldersIndex, .playlistsIndex, .queue:
            break   // home/index/queue pages don't drive the track list
        }
    }

    // MARK: - Visualizer

    private func startVisualizerUpdates() {
        guard visualizerTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 45.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickVisualizer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        visualizerTimer = timer
    }

    private func stopVisualizerUpdates() {
        visualizerTimer?.invalidate()
        visualizerTimer = nil
        visualizerLevels = Array(repeating: 0, count: AudioVisualizer.bandCount)
    }

    private func tickVisualizer() {
        let target = isPlaying
            ? visualizer.currentLevels()
            : Array(repeating: Float(0), count: AudioVisualizer.bandCount)
        guard target.count == visualizerLevels.count else {
            visualizerLevels = target
            return
        }
        // Fast attack, slow release for a springy VU look.
        var smoothed = visualizerLevels
        for i in 0..<target.count {
            let cur = smoothed[i]
            let coeff: Float = target[i] > cur ? 0.55 : 0.16
            smoothed[i] = cur + (target[i] - cur) * coeff
        }
        visualizerLevels = smoothed
    }

    var activeSidebarTab: SidebarTab {
        switch browsePage {
        case .home:                      return .home
        case .allTracks:                 return .allTracks
        case .liked:                     return .liked
        case .artistsIndex, .artist:     return .artists
        case .albumsIndex, .album:       return .albums
        case .foldersIndex, .folder:     return .folders
        case .playlistsIndex, .playlist: return .playlists
        case .queue:                     return .queue
        }
    }

    func removeRootFolder(path: String) async {
        guard let root = libraryFolders.first(where: { $0.path == path }) else { return }
        await removeFolder(root)
    }

    func trackCount(in playlist: Playlist) -> Int {
        let available = Set(tracks.map { normalizedPath(for: $0.url) })
        return playlist.trackPaths.filter { available.contains($0) }.count
    }

    func createPlaylist(named rawName: String) -> Playlist? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let playlist = Playlist(name: name)
        playlists.append(playlist)
        selectedSource = .playlist(id: playlist.id)
        return playlist
    }

    func renamePlaylist(id: UUID, to rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let idx = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[idx].name = name
    }

    func deletePlaylist(id: UUID) {
        playlists.removeAll { $0.id == id }
        if case .playlist(let selectedID) = selectedSource, selectedID == id {
            selectedSource = .allTracks
        }
    }

    func addTrack(_ track: Track, toPlaylist id: UUID) {
        guard let idx = playlists.firstIndex(where: { $0.id == id }) else { return }
        let path = normalizedPath(for: track.url)
        if !playlists[idx].trackPaths.contains(path) {
            playlists[idx].trackPaths.append(path)
        }
    }

    func removeTrack(_ track: Track, fromPlaylist id: UUID) {
        guard let idx = playlists.firstIndex(where: { $0.id == id }) else { return }
        let path = normalizedPath(for: track.url)
        playlists[idx].trackPaths.removeAll { $0 == path }
    }

    func playlistName(for id: UUID) -> String? {
        playlists.first(where: { $0.id == id })?.name
    }

    private func scanLibraries(triggeredByWatcher: Bool) async {
        if isScanning { return }

        guard !libraryFolders.isEmpty else {
            tracks = []
            filteredTracks = []
            playbackQueue = []
            queueIndex = -1
            if currentTrack != nil {
                removeObservers()
                player?.pause()
                currentTrack = nil
                isPlaying = false
            }
            return
        }

        isScanning = true
        defer { isScanning = false }

        let folderURLs = libraryFolders.map(\.url)
        if let first = folderURLs.first {
            UserDefaults.standard.set(normalizedPath(for: first), forKey: Self.defaults.musicFolderPath)
        }

        do {
            let loaded = try await scanner.scan(folders: folderURLs)
            let deduped = deduplicateTracksByPath(loaded)
            let previousCurrentURL = currentTrack?.url
            tracks = deduped
            applySearch()
            syncQueueWithCurrentLibrary()

            if let previousCurrentURL,
               let refreshed = tracks.first(where: { $0.url == previousCurrentURL }) {
                currentTrack = refreshed
            }
            // If the currently playing track is no longer in the new library, stop playback
            if let playing = currentTrack, !tracks.contains(playing) {
                removeObservers()
                player?.pause()
                currentTrack = nil
                isPlaying = false
            }
            if !triggeredByWatcher {
                DiagnosticsLogger.log("Library scanned: \(tracks.count) tracks (\(libraryFolders.count) folders)", category: "library")
            }
        } catch is CancellationError {
            DiagnosticsLogger.log("Library scan cancelled", category: "library")
        } catch {
            DiagnosticsLogger.log("Library scan error: \(error.localizedDescription)", category: "library")
        }
    }

    // MARK: - Playback

    func play(track: Track, queue: [Track]? = nil) {
        lyricsTask?.cancel()
        removeObservers()
        prepareQueueForPlayback(startingWith: track, base: queue)

        currentTrack = track
        duration = max(track.duration, 0.001)
        isPlaying = false
        currentTime = 0
        currentLyricIndex = -1
        lyricsState = .idle
        recordRecentlyPlayed(track)

        let item = AVPlayerItem(url: track.url)
        if player == nil { player = AVPlayer() }
        let activePlayer = player!
        activePlayer.volume = volume
        isPlaying = true

        // The analyzer tap must be on the item before it becomes current:
        // added later, a fresh player never inserts it into the pipeline.
        Task { @MainActor [weak self] in
            guard let self else { return }
            let mix = await self.visualizer.makeAudioMix(for: item)
            guard self.currentTrack?.id == track.id else { return }
            if let mix { item.audioMix = mix }
            activePlayer.replaceCurrentItem(with: item)
            activePlayer.play()
        }

        // The player item reports a more accurate duration once loaded.
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard self.currentTrack?.id == track.id else { return }
            if let d = self.player?.currentItem?.duration.seconds, d.isFinite, d > 0 {
                self.duration = d
            }
        }

        // Raw metadata keys for the debug panel.
        debugArtworkKeys = []
        Task { @MainActor [weak self] in
            guard let self else { return }
            let keys = await MusicScanner.rawMetadataKeys(for: track.url)
            self.debugArtworkKeys = keys
        }

        setupTimeObserver()
        setupEndObserver(for: item)
        fetchLyrics(for: track)

        updateNowPlaying()
    }

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
        updateNowPlaying()
    }

    func seek(to time: Double) {
        let clamped = max(0, min(time, duration))
        let cmTime = CMTime(seconds: clamped, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
        updateCurrentLyric()
        updateNowPlaying()
    }

    func setVolume(_ v: Float) {
        volume = max(0, min(v, 1))
        player?.volume = volume
        UserDefaults.standard.set(volume, forKey: Self.defaults.volume)
    }

    #if DEBUG
    /// Demo mode: silence the output without touching the volume setting.
    /// (Not `isMuted`: that also silences the visualizer's tap.)
    func muteOutputForDemo() {
        player?.volume = 0
    }
    #endif

    func toggleShuffle() {
        isShuffleEnabled.toggle()
    }

    func cycleRepeatMode() {
        repeatMode = repeatMode.next()
    }

    func enqueueNext(_ track: Track) {
        guard !playbackQueue.isEmpty else {
            playbackQueue = [track]
            queueIndex = 0
            return
        }
        if let existing = playbackQueue.firstIndex(of: track) {
            playbackQueue.remove(at: existing)
            if existing <= queueIndex {
                queueIndex = max(queueIndex - 1, 0)
            }
        }
        let insertion = min(queueIndex + 1, playbackQueue.count)
        playbackQueue.insert(track, at: insertion)
    }

    func enqueueLast(_ track: Track) {
        if playbackQueue.contains(track) { return }
        playbackQueue.append(track)
    }

    func removeFromQueue(_ track: Track) {
        guard let idx = playbackQueue.firstIndex(of: track) else { return }
        playbackQueue.remove(at: idx)
        if idx < queueIndex {
            queueIndex -= 1
        } else if idx == queueIndex {
            queueIndex = min(queueIndex, max(playbackQueue.count - 1, 0))
        }
    }

    func reloadLyrics() {
        guard let track = currentTrack else { return }
        fetchLyrics(for: track)
    }

    func searchLyricsManually(trackName: String, artistName: String) async {
        let trimmedTrack = trackName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedArtist = artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTrack.isEmpty else {
            manualLyricsResults = []
            manualLyricsSearchError = "Enter a track name."
            return
        }

        isManualLyricsSearchLoading = true
        manualLyricsSearchError = nil
        defer { isManualLyricsSearchLoading = false }

        do {
            let results = try await lyricsService.searchLyrics(
                trackName: trimmedTrack,
                artistName: trimmedArtist
            )
            guard !Task.isCancelled else { return }
            manualLyricsResults = results
            if results.isEmpty {
                manualLyricsSearchError = "No results found for this query."
            }
        } catch {
            guard !Task.isCancelled else { return }
            manualLyricsResults = []
            manualLyricsSearchError = error.localizedDescription
        }
    }

    func applyManualLyricsResult(_ result: LyricsSearchResult) {
        if let synced = result.syncedLyrics?.trimmingCharacters(in: .whitespacesAndNewlines),
           !synced.isEmpty {
            let lines = LRCParser.parse(synced)
            if !lines.isEmpty {
                lyricsState = .loaded(lines)
                currentLyricIndex = -1
                if let track = currentTrack {
                    let lrcURL = track.url.deletingPathExtension().appendingPathExtension("lrc")
                    try? synced.write(to: lrcURL, atomically: true, encoding: .utf8)
                }
                return
            }
        }

        if let plain = result.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines),
           !plain.isEmpty {
            lyricsState = .plain(plain)
            currentLyricIndex = -1
            return
        }

        lyricsState = .notFound
    }

    func playNext() {
        advanceToNextTrack(triggeredByEnd: false)
    }

    func playPrevious() {
        if currentTime > 3 {
            seek(to: 0)
            return
        }

        guard !playbackQueue.isEmpty else { return }
        guard queueIndex >= 0 else { return }

        let previousIndex: Int?
        if queueIndex > 0 {
            previousIndex = queueIndex - 1
        } else if repeatMode == .all {
            previousIndex = playbackQueue.count - 1
        } else {
            previousIndex = nil
        }

        guard let idx = previousIndex, idx >= 0, idx < playbackQueue.count else { return }
        queueIndex = idx
        play(track: playbackQueue[idx])
    }

    var upNextTracks: [Track] {
        guard !playbackQueue.isEmpty else { return [] }
        guard queueIndex >= 0 else { return playbackQueue }
        let start = min(queueIndex + 1, playbackQueue.count)
        return Array(playbackQueue.dropFirst(start))
    }

    var queueSummaryText: String {
        guard !playbackQueue.isEmpty else { return "Queue empty" }
        guard queueIndex >= 0 else { return "\(playbackQueue.count) tracks in queue" }
        let nextCount = max(playbackQueue.count - queueIndex - 1, 0)
        return "\(nextCount) up next"
    }

    func saveManualLyricsText(_ text: String) {
        guard let track = currentTrack else { return }
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lrcURL = track.url.deletingPathExtension().appendingPathExtension("lrc")

        if normalized.isEmpty {
            try? FileManager.default.removeItem(at: lrcURL)
            lyricsState = .notFound
            currentLyricIndex = -1
            return
        }

        try? normalized.write(to: lrcURL, atomically: true, encoding: .utf8)
        let parsed = LRCParser.parse(normalized)
        if !parsed.isEmpty {
            lyricsState = .loaded(parsed)
        } else {
            lyricsState = .plain(normalized)
        }
        currentLyricIndex = -1
    }

    func editableLyricsText() -> String {
        if let track = currentTrack {
            let lrcURL = track.url.deletingPathExtension().appendingPathExtension("lrc")
            if let local = try? String(contentsOf: lrcURL, encoding: .utf8) {
                return local
            }
        }
        switch lyricsState {
        case .loaded(let lines):
            return lines.map { line in
                let total = max(0, line.timestamp)
                let minutes = Int(total / 60)
                let seconds = total - Double(minutes * 60)
                return String(format: "[%02d:%05.2f]%@", minutes, seconds, line.text)
            }.joined(separator: "\n")
        case .plain(let text):
            return text
        default:
            return ""
        }
    }

    func currentTrackLyricsFilePath() -> String? {
        guard let track = currentTrack else { return nil }
        return track.url.deletingPathExtension().appendingPathExtension("lrc").path
    }

    func checkForUpdatesNow() async {
        let slug = updatesRepoSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slug.isEmpty else {
            updateMessage = "Set GitHub repo slug in Settings (owner/repo)."
            updateURL = nil
            return
        }

        isCheckingUpdates = true
        defer { isCheckingUpdates = false }

        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        do {
            let result = try await updateService.checkLatestRelease(repoSlug: slug, currentVersion: currentVersion)
            updateURL = result.releaseURL
            if result.isNewerThanCurrent {
                updateMessage = "Update available: \(result.latestVersion)"
            } else {
                updateMessage = "You are up to date (\(currentVersion))."
            }
        } catch {
            updateMessage = "Update check failed: \(error.localizedDescription)"
            updateURL = nil
            DiagnosticsLogger.log("Update check failed: \(error.localizedDescription)", category: "updates")
        }
    }

    func runPostLaunchTasks() async {
        if autoCheckUpdatesOnLaunch {
            await checkForUpdatesNow()
        }
    }

    // MARK: - Formatted times

    var formattedCurrentTime: String { formatTime(currentTime) }
    var formattedDuration: String    { formatTime(duration)    }

    func formatTime(_ s: Double) -> String {
        guard s.isFinite else { return "0:00" }
        let t = max(0, Int(s))
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    // MARK: - Private helpers

    private func applySearch() {
        let sourceTracks = tracksForSelectedSource()
        if searchText.isEmpty {
            filteredTracks = sourceTracks
        } else {
            filteredTracks = sourceTracks.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)  ||
                $0.artist.localizedCaseInsensitiveContains(searchText) ||
                $0.album.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    private func tracksForSelectedSource() -> [Track] {
        switch selectedSource {
        case .allTracks:
            return tracks
        case .liked:
            return likedTracks
        case .folder(let path):
            return tracks.filter { trackBelongsToFolder($0, folderPath: path) }
        case .artist(let name):
            return tracks.filter { artistKey(for: $0) == name }
        case .album(let name):
            return tracks
                .filter { albumKey(for: $0) == name }
                .sorted(by: Track.albumOrder)
        case .playlist(let id):
            guard let playlist = playlists.first(where: { $0.id == id }) else { return [] }
            let byPath = Dictionary(uniqueKeysWithValues: tracks.map { (normalizedPath(for: $0.url), $0) })
            return playlist.trackPaths.compactMap { byPath[$0] }
        }
    }

    private func trackBelongsToFolder(_ track: Track, folderPath: String) -> Bool {
        let normalizedFolder = normalizedPath(for: URL(fileURLWithPath: folderPath))
        let normalizedTrack = normalizedPath(for: track.url)
        if normalizedTrack == normalizedFolder { return true }
        return normalizedTrack.hasPrefix(normalizedFolder + "/")
    }

    private func deduplicatedFolders(paths: [String]) -> [LibraryFolder] {
        var seen = Set<String>()
        var result: [LibraryFolder] = []
        for path in paths {
            let normalized = normalizedPath(for: URL(fileURLWithPath: path))
            guard seen.insert(normalized).inserted else { continue }
            result.append(LibraryFolder(path: normalized))
        }
        return result
    }

    private func deduplicateTracksByPath(_ input: [Track]) -> [Track] {
        var seen = Set<String>()
        var result: [Track] = []
        for track in input {
            let path = normalizedPath(for: track.url)
            guard seen.insert(path).inserted else { continue }
            result.append(track)
        }
        return result
    }

    private func descendantFolderPaths(forRootPath rootPath: String) -> [String] {
        let prefix = rootPath + "/"
        var paths = Set<String>()

        for track in tracks {
            let trackFolder = normalizedPath(for: track.url.deletingLastPathComponent())
            guard trackFolder != rootPath, trackFolder.hasPrefix(prefix) else { continue }

            var current = trackFolder
            while current.hasPrefix(prefix) && current != rootPath {
                paths.insert(current)
                let parent = normalizedPath(for: URL(fileURLWithPath: current).deletingLastPathComponent())
                if parent == current || parent == rootPath { break }
                current = parent
            }
        }

        return paths.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func folderDepth(relativeTo rootPath: String, path: String) -> Int {
        let rootCount = URL(fileURLWithPath: rootPath).pathComponents.count
        let pathCount = URL(fileURLWithPath: path).pathComponents.count
        return max(pathCount - rootCount, 0)
    }

    /// Resolving symlinks hits the file system; rows ask for this on every
    /// redraw (via `isLiked`), so remember the answer per URL.
    @ObservationIgnored private var normalizedPaths: [URL: String] = [:]

    private func normalizedPath(for url: URL) -> String {
        if let cached = normalizedPaths[url] { return cached }
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        normalizedPaths[url] = path
        return path
    }

    private func persistLibraryFolders() {
        let paths = libraryFolders.map(\.path)
        UserDefaults.standard.set(paths, forKey: Self.defaults.libraryFolderPaths)
    }

    private func persistPlaylists() {
        if let data = try? JSONEncoder().encode(playlists) {
            UserDefaults.standard.set(data, forKey: Self.defaults.playlists)
        }
    }

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: interval, queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                self.currentTime = time.seconds
                self.updateCurrentLyric()
                // Now Playing only needs the position about once a second.
                if Int(time.seconds * 10) % 10 == 0 {
                    self.updateNowPlaying()
                }
            }
        }
    }

    private func setupEndObserver(for item: AVPlayerItem) {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.advanceToNextTrack(triggeredByEnd: true) }
        }
    }

    private func removeObservers() {
        if let obs = timeObserver {
            player?.removeTimeObserver(obs)
            timeObserver = nil
        }
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
    }

    private func updateCurrentLyric() {
        guard case .loaded(let lines) = lyricsState, !lines.isEmpty else { return }
        var idx = -1
        for (i, line) in lines.enumerated() {
            if line.timestamp <= currentTime { idx = i } else { break }
        }
        if idx != currentLyricIndex { currentLyricIndex = idx }
    }

    private func fetchLyrics(for track: Track) {
        lyricsTask?.cancel()
        currentLyricIndex = -1
        lyricsState = .loading
        manualLyricsResults = []
        manualLyricsSearchError = nil
        debugLyricsHTTPStatus = nil
        debugLyricsRawJSON = nil

        lyricsTask = Task { [weak self] in
            guard let self else { return }
            let (state, httpStatus, rawJSON) = await self.lyricsService.fetchLyrics(
                for: track,
                enableSmartMatching: self.lyricsSmartMatchingEnabled
            )
            guard !Task.isCancelled, self.currentTrack?.id == track.id else { return }
            self.lyricsState = state
            self.debugLyricsHTTPStatus = httpStatus
            self.debugLyricsRawJSON = rawJSON
            // Lyrics can arrive mid-song: highlight the right line now.
            self.updateCurrentLyric()
        }
    }

    private func prepareQueueForPlayback(startingWith track: Track, base inputBase: [Track]? = nil) {
        let source = inputBase ?? (filteredTracks.isEmpty ? tracks : filteredTracks)
        let base = source.isEmpty ? [track] : source

        if isShuffleEnabled {
            var remaining = base.filter { $0 != track }
            remaining.shuffle()
            playbackQueue = [track] + remaining
            queueIndex = 0
            return
        }

        playbackQueue = base
        queueIndex = playbackQueue.firstIndex(of: track) ?? 0
    }

    private func rebuildQueueKeepingCurrent() {
        guard let currentTrack else { return }
        prepareQueueForPlayback(startingWith: currentTrack)
    }

    private func advanceToNextTrack(triggeredByEnd: Bool) {
        guard !playbackQueue.isEmpty else { return }
        guard queueIndex >= 0 && queueIndex < playbackQueue.count else { return }

        if triggeredByEnd && repeatMode == .one {
            seek(to: 0)
            player?.play()
            isPlaying = true
            updateNowPlaying()
            return
        }

        let nextIndex: Int?
        if queueIndex + 1 < playbackQueue.count {
            nextIndex = queueIndex + 1
        } else if repeatMode == .all {
            nextIndex = 0
        } else {
            nextIndex = nil
        }

        guard let idx = nextIndex else {
            if triggeredByEnd {
                isPlaying = false
                updateNowPlaying()
            }
            return
        }

        queueIndex = idx
        play(track: playbackQueue[idx])
    }

    private func syncQueueWithCurrentLibrary() {
        guard !tracks.isEmpty else {
            playbackQueue = []
            queueIndex = -1
            return
        }

        let byURL = Dictionary(uniqueKeysWithValues: tracks.map { ($0.url, $0) })
        playbackQueue = playbackQueue.compactMap { byURL[$0.url] }

        if let current = currentTrack {
            if let idx = playbackQueue.firstIndex(where: { $0.url == current.url }) {
                queueIndex = idx
            } else {
                prepareQueueForPlayback(startingWith: current)
            }
        } else {
            queueIndex = playbackQueue.isEmpty ? -1 : 0
        }
    }

    private func restartLibraryWatcher() {
        libraryWatcherTask?.cancel()
        libraryWatcherTask = nil

        guard autoRescanEnabled, !libraryFolders.isEmpty else { return }

        libraryWatcherTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let nanos = UInt64(max(5, self.autoRescanInterval) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                guard !Task.isCancelled else { return }
                await self.scanLibraries(triggeredByWatcher: true)
            }
        }
    }
}
