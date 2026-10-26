import SwiftUI

/// Main area. Renders the home page, an index (artists / albums / folders /
/// playlists / queue) or a track collection, driven by `vm.browsePage`.
struct BrowseView: View {
    @Environment(PlayerViewModel.self) private var vm

    private let tileColumns = [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !vm.searchText.isEmpty {
                SearchResultsView(tileColumns: tileColumns)
            } else {
                page
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var page: some View {
        Group {
            switch vm.browsePage {
            case .home:            homePage
            case .allTracks:       trackPage(backTo: nil)
            case .liked:           trackPage(backTo: nil)
            case .artist:          trackPage(backTo: .artistsIndex)
            case .album:           trackPage(backTo: .albumsIndex)
            case .folder:          trackPage(backTo: .foldersIndex)
            case .playlist:        trackPage(backTo: .playlistsIndex)
            case .artistsIndex:    artistsIndex
            case .albumsIndex:     albumsIndex
            case .foldersIndex:    foldersIndex
            case .playlistsIndex:  playlistsIndex
            case .queue:           queuePage
            }
        }
    }

    private func matches(_ text: String) -> Bool {
        vm.searchText.isEmpty || text.localizedCaseInsensitiveContains(vm.searchText)
    }

    // MARK: - Home

    private var homePage: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 44) {
                hero
                    .padding(.top, 36)

                // The sidebar already lists these; show them only when it's hidden.
                if !vm.isSidebarVisible {
                    quickChips
                }

                if !vm.recentlyPlayed.isEmpty {
                    tileSection(title: "Recently played", seeAll: nil) {
                        ForEach(Array(vm.recentlyPlayed.prefix(8))) { track in
                            TrackTile(track: track) { vm.play(track: track) }
                        }
                    }
                }

                if !vm.likedTracks.isEmpty {
                    tileSection(title: "Liked", seeAll: { vm.browsePage = .liked }) {
                        ForEach(Array(vm.likedTracks.prefix(12))) { track in
                            TrackTile(track: track) { vm.play(track: track, queue: vm.likedTracks) }
                        }
                    }
                }

                if !vm.albums.isEmpty {
                    tileSection(title: "Albums", seeAll: { vm.browsePage = .albumsIndex }) {
                        ForEach(Array(vm.albums.prefix(12))) { album in
                            AlbumTile(album: album, artwork: vm.albumArtwork(album.name)) {
                                vm.browsePage = .album(name: album.name)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 150)
            .frame(maxWidth: .infinity)
        }
    }

    private var hero: some View {
        VStack(spacing: 16) {
            Kicker(text: librarySummary)
            Text(greeting)
                .font(Theme.display(40))
                .tracking(Theme.displayTracking(40))
                .multilineTextAlignment(.center)
            Text(heroSubtitle)
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            HStack(spacing: 8) {
                if !(vm.isPlaying && vm.currentTrack != nil) {
                    Button { vm.resumePlayback() } label: {
                        Label(vm.currentTrack == nil && vm.recentlyPlayed.isEmpty ? "Play" : "Resume",
                              systemImage: "play.fill")
                    }
                    .buttonStyle(PillButtonStyle())
                }
                Button { vm.shuffleAllAndPlay() } label: {
                    Label("Shuffle all", systemImage: "shuffle")
                }
                .buttonStyle(PillButtonStyle(kind: vm.isPlaying ? .primary : .secondary))
            }
            .padding(.top, 6)
            .disabled(vm.tracks.isEmpty)
        }
        .frame(maxWidth: 560)
    }

    private var heroSubtitle: String {
        if let track = vm.currentTrack {
            let artist = track.artist == "Unknown Artist" ? "" : " by \(track.artist)"
            return (vm.isPlaying ? "Now playing " : "Paused on ") + "\(track.title)\(artist)"
        }
        if let last = vm.recentlyPlayed.first {
            return "Pick up where you left off with \(last.title)"
        }
        return "Everything in your folders, with synced lyrics."
    }

    private var quickChips: some View {
        FlowLayout(spacing: 6) {
            Chip(title: "All Tracks", count: vm.tracks.count) { vm.browsePage = .allTracks }
            Chip(title: "Liked", count: vm.likedTracks.count) { vm.browsePage = .liked }
            Chip(title: "Albums", count: vm.albums.count) { vm.browsePage = .albumsIndex }
            Chip(title: "Artists", count: vm.artists.count) { vm.browsePage = .artistsIndex }
            Chip(title: "Playlists", count: vm.playlists.count) { vm.browsePage = .playlistsIndex }
            Chip(title: "Folders", count: vm.browsableFolders.count) { vm.browsePage = .foldersIndex }
            Chip(title: "Queue", count: vm.upNextTracks.count) { vm.browsePage = .queue }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tileSection<Content: View>(
        title: String,
        seeAll: (() -> Void)?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 20, weight: .medium))
                    .tracking(-0.2)
                Spacer()
                if let seeAll {
                    Button("See all", action: seeAll)
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                }
            }
            // One horizontal shelf per section, like a music store row.
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    Group { content() }
                        .frame(width: 196)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, 28, for: .scrollContent)
            .padding(.horizontal, -28)
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return "Good morning"
        case 12..<18: return "Good afternoon"
        case 18..<23: return "Good evening"
        default:      return "Late night listening"
        }
    }

    private var librarySummary: String {
        let t = vm.tracks.count
        let a = vm.artists.count
        guard t > 0 else { return "Empty library" }
        return "\(t) \(t == 1 ? "track" : "tracks") · \(a) \(a == 1 ? "artist" : "artists")"
    }

    // MARK: - Track collection

    private func trackPage(backTo: BrowsePage?) -> some View {
        let isAlbumPage: Bool = { if case .album = vm.selectedSource { return true }; return false }()
        let albumArt: NSImage? = {
            if case .album(let name) = vm.selectedSource { return vm.albumArtwork(name) }
            return nil
        }()

        return VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                kicker: vm.selectedSourceSubtitle,
                title: vm.selectedSourceTitle,
                subtitle: "\(vm.filteredTracks.count) \(vm.filteredTracks.count == 1 ? "track" : "tracks")",
                artwork: isAlbumPage ? .some(albumArt) : nil,
                onBack: backTo.map { page in { vm.browsePage = page } }
            ) {
                HStack(spacing: 8) {
                    Button { vm.playAllInCurrentSource() } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(PillButtonStyle())
                    Button { vm.shuffleCurrentSource() } label: {
                        Label("Shuffle", systemImage: "shuffle")
                    }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                }
                .disabled(vm.filteredTracks.isEmpty)
            }

            if vm.filteredTracks.isEmpty {
                EmptyStateView(icon: "music.note", text: vm.isScanning ? "Scanning library…" : "No tracks here")
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(vm.filteredTracks.enumerated()), id: \.element.id) { index, track in
                            TrackRow(
                                track: track,
                                leadingNumber: isAlbumPage ? (track.trackNumber ?? index + 1) : nil
                            )
                            .onTapGesture { vm.play(track: track) }
                            .contextMenu { trackMenu(track) }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 150)
                }
            }
        }
    }

    @ViewBuilder
    private func trackMenu(_ track: Track) -> some View {
        Button("Play") { vm.play(track: track) }
        Button("Play Next") { vm.enqueueNext(track) }
        Button("Add to Queue") { vm.enqueueLast(track) }
        Button(vm.isLiked(track) ? "Unlike" : "Like") { vm.toggleLiked(track) }
        Divider()
        Button("Go to Artist") { vm.goToArtist(of: track) }
        Button("Go to Album") { vm.goToAlbum(of: track) }
        Divider()
        if !vm.playlists.isEmpty {
            Menu("Add to Playlist") {
                ForEach(vm.playlists) { playlist in
                    Button(playlist.name) { vm.addTrack(track, toPlaylist: playlist.id) }
                }
            }
        }
        if case .playlist(let playlistID) = vm.selectedSource {
            Button("Remove from This Playlist", role: .destructive) {
                vm.removeTrack(track, fromPlaylist: playlistID)
            }
        }
    }

    // MARK: - Indexes

    private var artistsIndex: some View {
        let items = vm.artists.filter { matches($0.name) }
        return VStack(alignment: .leading, spacing: 0) {
            PageHeader(kicker: "Library", title: "Artists", subtitle: "\(vm.artists.count) artists")
            if items.isEmpty {
                EmptyStateView(icon: "music.mic", text: "No artists")
            } else {
                indexScroll {
                    ForEach(items) { artist in
                        IndexRow(icon: "music.mic", title: artist.name, count: artist.trackCount) {
                            vm.browsePage = .artist(name: artist.name)
                        }
                    }
                }
            }
        }
    }

    private var albumsIndex: some View {
        let items = vm.albums.filter { matches($0.name) || matches($0.artist) }
        return VStack(alignment: .leading, spacing: 0) {
            PageHeader(kicker: "Library", title: "Albums", subtitle: "\(vm.albums.count) albums")
            if items.isEmpty {
                EmptyStateView(icon: "square.stack", text: "No albums")
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(columns: tileColumns, alignment: .leading, spacing: 12) {
                        ForEach(items) { album in
                            AlbumTile(album: album, artwork: vm.albumArtwork(album.name)) {
                                vm.browsePage = .album(name: album.name)
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 150)
                }
            }
        }
    }

    private var foldersIndex: some View {
        let items = vm.browsableFolders.filter { matches($0.displayName) }
        return VStack(alignment: .leading, spacing: 0) {
            PageHeader(kicker: "Library", title: "Folders", subtitle: "\(vm.browsableFolders.count) folders") {
                Button(action: addFolder) { Label("Add folder", systemImage: "plus") }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
            }
            if items.isEmpty {
                EmptyStateView(icon: "folder", text: "No folders added")
            } else {
                indexScroll {
                    ForEach(items) { folder in
                        IndexRow(
                            icon: folder.isRoot ? "externaldrive" : "folder",
                            title: folder.displayName,
                            count: vm.trackCount(inFolderPath: folder.path),
                            depth: folder.depth
                        ) {
                            vm.browsePage = .folder(path: folder.path)
                        }
                        .contextMenu {
                            if folder.isRoot {
                                Button("Remove Folder", role: .destructive) {
                                    Task { await vm.removeRootFolder(path: folder.path) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var playlistsIndex: some View {
        let items = vm.playlists.filter { matches($0.name) }
        return VStack(alignment: .leading, spacing: 0) {
            PageHeader(kicker: "Library", title: "Playlists", subtitle: "\(vm.playlists.count) playlists") {
                Button(action: createPlaylist) { Label("New playlist", systemImage: "plus") }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
            }
            if items.isEmpty {
                EmptyStateView(icon: "music.note.list", text: "No playlists yet")
            } else {
                indexScroll {
                    ForEach(items) { playlist in
                        IndexRow(icon: "music.note.list", title: playlist.name, count: vm.trackCount(in: playlist)) {
                            vm.browsePage = .playlist(id: playlist.id)
                        }
                        .contextMenu {
                            Button("Rename Playlist") { renamePlaylist(playlist) }
                            Button("Delete Playlist", role: .destructive) { vm.deletePlaylist(id: playlist.id) }
                        }
                    }
                }
            }
        }
    }

    private var queuePage: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(kicker: "Now playing", title: "Queue", subtitle: vm.queueSummaryText)
            if vm.upNextTracks.isEmpty {
                EmptyStateView(icon: "list.bullet", text: "Nothing queued")
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 2) {
                        ForEach(vm.upNextTracks) { track in
                            HStack(spacing: 6) {
                                TrackRow(track: track)
                                    .onTapGesture { vm.play(track: track) }
                                Button { vm.removeFromQueue(track) } label: {
                                    Image(systemName: "xmark")
                                }
                                .buttonStyle(CircleIconButtonStyle(size: 28))
                                .help("Remove from queue")
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 150)
                }
            }
        }
    }

    private func indexScroll<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 2) {
                content()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 150)
        }
    }

    // MARK: - Actions

    private func createPlaylist() {
        guard let name = AppKitPrompts.promptForName(title: "New Playlist", defaultValue: "") else { return }
        if let created = vm.createPlaylist(named: name) {
            vm.browsePage = .playlist(id: created.id)
        }
    }

    private func renamePlaylist(_ playlist: Playlist) {
        guard let name = AppKitPrompts.promptForName(title: "Rename Playlist", defaultValue: playlist.name) else { return }
        vm.renamePlaylist(id: playlist.id, to: name)
    }

    private func addFolder() {
        guard let url = AppKitPrompts.chooseMusicFolder() else { return }
        Task { await vm.loadFolder(url) }
    }
}

// MARK: - Search results

private struct SearchResultsView: View {
    let tileColumns: [GridItem]
    @Environment(PlayerViewModel.self) private var vm

    var body: some View {
        let results = vm.searchResults
        if results.isEmpty {
            EmptyStateView(icon: "magnifyingglass", text: "No results for “\(vm.searchText)”")
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 36) {
                    HStack(alignment: .top, spacing: 12) {
                        if let top = results.top {
                            VStack(alignment: .leading, spacing: 14) {
                                sectionTitle("Top result")
                                TopResultTile(hit: top)
                            }
                            .frame(width: 300)
                        }
                        if !results.songs.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                sectionTitle("Songs")
                                VStack(spacing: 2) {
                                    ForEach(results.songs.prefix(4)) { songRow($0) }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }

                    if !results.artists.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            sectionTitle("Artists")
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 12)],
                                      alignment: .leading, spacing: 12) {
                                ForEach(results.artists) { artist in
                                    ArtistTile(artist: artist, artwork: vm.artistArtwork(artist.name)) {
                                        vm.open(.artist(artist))
                                    }
                                }
                            }
                        }
                    }

                    if !results.albums.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            sectionTitle("Albums")
                            LazyVGrid(columns: tileColumns, alignment: .leading, spacing: 12) {
                                ForEach(results.albums) { album in
                                    AlbumTile(album: album, artwork: vm.albumArtwork(album.name)) {
                                        vm.open(.album(album))
                                    }
                                }
                            }
                        }
                    }

                    if !results.playlists.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            sectionTitle("Playlists")
                            VStack(spacing: 2) {
                                ForEach(results.playlists) { playlist in
                                    IndexRow(icon: "music.note.list", title: playlist.name,
                                             count: vm.trackCount(in: playlist)) {
                                        vm.open(.playlist(playlist))
                                    }
                                }
                            }
                        }
                    }

                    if results.songs.count > 4 {
                        VStack(alignment: .leading, spacing: 14) {
                            sectionTitle("More songs")
                            LazyVStack(spacing: 2) {
                                ForEach(results.songs.dropFirst(4)) { songRow($0) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 12)
                .padding(.bottom, 150)
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 20, weight: .medium))
            .tracking(-0.2)
    }

    private func songRow(_ track: Track) -> some View {
        TrackRow(track: track)
            .onTapGesture { vm.open(.track(track)) }
            .contextMenu {
                Button("Play Next") { vm.enqueueNext(track) }
                Button("Add to Queue") { vm.enqueueLast(track) }
                Button("Go to Artist") { vm.searchText = ""; vm.goToArtist(of: track) }
                Button("Go to Album") { vm.searchText = ""; vm.goToAlbum(of: track) }
            }
    }
}

/// Large tile for the best match, with its kind as a label.
private struct TopResultTile: View {
    let hit: SearchHit
    @Environment(PlayerViewModel.self) private var vm
    @State private var isHovered = false

    var body: some View {
        Button { vm.open(hit) } label: {
            VStack(alignment: .leading, spacing: 16) {
                artwork
                    .frame(width: 96, height: 96)
                    .raisedShadow()
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(Theme.display(26))
                        .tracking(Theme.displayTracking(26))
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Text(kind)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(Capsule().fill(Theme.raised))
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, minHeight: 236, alignment: .bottomLeading)
            .tileBackground()
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: isTrack ? "play.fill" : "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.canvas)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.ink))
                    .padding(18)
                    .opacity(isHovered ? 1 : 0)
                    .offset(y: isHovered ? 0 : 6)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isHovered)
    }

    private var isTrack: Bool {
        if case .track = hit { return true }
        return false
    }

    @ViewBuilder
    private var artwork: some View {
        switch hit {
        case .artist(let a):
            ArtworkView(image: vm.artistArtwork(a.name), radius: 48, glyph: "music.mic")
        case .album(let a):
            ArtworkView(image: vm.albumArtwork(a.name), radius: 14, glyph: "square.stack")
        case .track(let t):
            ArtworkView(image: t.artwork, radius: 14)
        case .playlist:
            ArtworkView(image: nil, radius: 14, glyph: "music.note.list")
        }
    }

    private var title: String {
        switch hit {
        case .artist(let a):   return a.name
        case .album(let a):    return a.name
        case .track(let t):    return t.title
        case .playlist(let p): return p.name
        }
    }

    private var kind: String {
        switch hit {
        case .artist:   return "Artist"
        case .album:    return "Album"
        case .track:    return "Song"
        case .playlist: return "Playlist"
        }
    }

    private var subtitle: String? {
        switch hit {
        case .artist(let a):   return "\(a.trackCount) \(a.trackCount == 1 ? "track" : "tracks")"
        case .album(let a):    return a.artist
        case .track(let t):    return t.artist == "Unknown Artist" ? nil : t.artist
        case .playlist(let p): return "\(p.trackPaths.count) tracks"
        }
    }
}

private struct ArtistTile: View {
    let artist: ArtistGroup
    let artwork: NSImage?
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                ArtworkView(image: artwork, radius: 60, glyph: "music.mic")
                    .aspectRatio(1, contentMode: .fit)
                    .raisedShadow()
                    .scaleEffect(isHovered ? 1.04 : 1)
                VStack(spacing: 2) {
                    Text(artist.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text("Artist")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                }
            }
            .padding(14)
            .tileBackground(radius: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isHovered)
    }
}

// MARK: - Page header

private struct PageHeader<Actions: View>: View {
    let kicker: String
    let title: String
    let subtitle: String
    /// `nil` hides the artwork slot; `.some(nil)` shows a placeholder.
    var artwork: NSImage?? = nil
    var onBack: (() -> Void)? = nil
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(alignment: .bottom, spacing: 22) {
            if let artwork {
                ArtworkView(image: artwork, radius: 20, glyph: "square.stack")
                    .frame(width: 132, height: 132)
                    .raisedShadow()
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    if let onBack {
                        Button(action: onBack) { Image(systemName: "chevron.left") }
                            .buttonStyle(CircleIconButtonStyle(size: 26))
                            .help("Back")
                    }
                    Kicker(text: kicker)
                }
                Text(title)
                    .font(Theme.display(40))
                    .tracking(Theme.displayTracking(40))
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 16) {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                    Spacer(minLength: 12)
                    actions()
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 12)
        .padding(.bottom, 22)
    }
}

extension PageHeader where Actions == EmptyView {
    init(kicker: String, title: String, subtitle: String) {
        self.init(kicker: kicker, title: title, subtitle: subtitle, actions: { EmptyView() })
    }
}

// MARK: - Tiles

/// Gray tile with the artwork floating in the middle and labels at the bottom.
private struct ArtworkTile: View {
    let artwork: NSImage?
    let glyph: String
    let title: String
    let subtitle: String
    var badge: String? = nil
    let onTap: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                GeometryReader { geo in
                    let side = min(geo.size.width, geo.size.height) * 0.62
                    ArtworkView(image: artwork, radius: 14, glyph: glyph)
                        .frame(width: side, height: side)
                        .raisedShadow()
                        .scaleEffect(isHovered && !reduceMotion ? 1.05 : 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .aspectRatio(1.15, contentMode: .fit)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.canvas)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Theme.ink))
                        .opacity(isHovered ? 1 : 0)
                        .scaleEffect(isHovered ? 1 : 0.6)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            }
            .tileBackground()
            .overlay(alignment: .topLeading) {
                if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(Capsule().fill(Theme.raised))
                        .padding(12)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isHovered)
    }
}

private struct TrackTile: View {
    let track: Track
    let onTap: () -> Void
    @Environment(PlayerViewModel.self) private var vm

    var body: some View {
        ArtworkTile(
            artwork: track.artwork,
            glyph: "music.note",
            title: track.title,
            subtitle: track.artist == "Unknown Artist" ? track.album : track.artist,
            badge: vm.currentTrack?.id == track.id ? (vm.isPlaying ? "Playing" : "Paused") : nil,
            onTap: onTap
        )
    }
}

private struct AlbumTile: View {
    let album: AlbumGroup
    let artwork: NSImage?
    let onTap: () -> Void

    var body: some View {
        ArtworkTile(
            artwork: artwork,
            glyph: "square.stack",
            title: album.name,
            subtitle: "\(album.artist) · \(album.trackCount)",
            onTap: onTap
        )
    }
}

// MARK: - Rows

struct TrackRow: View {
    let track: Track
    /// On album pages the track number replaces the (identical) artwork.
    var leadingNumber: Int? = nil
    @Environment(PlayerViewModel.self) private var vm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var isActive: Bool { vm.currentTrack?.id == track.id }

    var body: some View {
        HStack(spacing: 12) {
            if let leadingNumber {
                ZStack {
                    if isActive && vm.isPlaying {
                        NowPlayingBars()
                    } else {
                        Text("\(leadingNumber)")
                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                            .foregroundStyle(isActive ? Theme.ink : Theme.tertiary)
                    }
                }
                .frame(width: 40, height: 40)
            } else {
                ArtworkView(image: track.artwork)
                    .frame(width: 40, height: 40)
                    .overlay {
                        if isActive && vm.isPlaying {
                            RoundedRectangle(cornerRadius: Theme.Radius.thumb, style: .continuous)
                                .fill(.black.opacity(0.45))
                            NowPlayingBars(color: .white)
                        }
                    }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if !track.artist.isEmpty && track.artist != "Unknown Artist" {
                    Text(track.artist)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if leadingNumber == nil, track.album != "Unknown Album" {
                Text(track.album)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
                    .frame(maxWidth: 220, alignment: .leading)
            }

            Button {
                vm.toggleLiked(track)
            } label: {
                Image(systemName: vm.isLiked(track) ? "heart.fill" : "heart")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(vm.isLiked(track) ? Theme.ink : Theme.tertiary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(vm.isLiked(track) || isHovered ? 1 : 0)
            .help(vm.isLiked(track) ? "Unlike" : "Like")

            Text(vm.formatTime(track.duration))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.tertiary)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(isActive ? Theme.tile : (isHovered ? Theme.ink.opacity(0.03) : .clear))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 0.12), value: isHovered)
        .animation(reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 0.12), value: isActive)
    }
}

private struct IndexRow: View {
    let icon: String
    let title: String
    let count: Int
    var depth: Int = 0
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.tile))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.tertiary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .padding(.leading, CGFloat(depth) * 18)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(isHovered ? Theme.ink.opacity(0.03) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// Three bouncing bars for the playing row.
private struct NowPlayingBars: View {
    var color: Color = Theme.ink
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(color)
                        .frame(width: 3, height: 4 + 9 * abs(sin(t * (5 + Double(i) * 1.7) + Double(i))))
                }
            }
            .frame(height: 14, alignment: .bottom)
        }
    }
}

// MARK: - Flow layout

/// Wraps children onto new lines when they run out of width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
