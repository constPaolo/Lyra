import SwiftUI

/// The context menu of a song, the same wherever a song appears: track
/// lists, search, home tiles, the queue, the compact library.
struct TrackMenuItems: View {
    let track: Track
    /// Queue for "Play" (nil: the page on screen). Hidden when `showsPlay` is
    /// false, where a click already plays with the right queue.
    var queue: [Track]? = nil
    var showsPlay = true
    @Environment(PlayerViewModel.self) private var vm

    var body: some View {
        if showsPlay {
            Button("Play") { vm.play(track: track, queue: queue) }
        }
        Button("Play Next") { vm.enqueueNext(track) }
        Button("Add to Queue") { vm.enqueueLast(track) }
        Button(vm.isLiked(track) ? "Unlike" : "Like") { vm.toggleLiked(track) }
        Divider()
        AddToPlaylistMenu(track: track)
        if case .playlist(let id) = vm.selectedSource, vm.isTrack(track, inPlaylist: id) {
            Button("Remove from This Playlist", role: .destructive) {
                vm.removeTrack(track, fromPlaylist: id)
            }
        }
        Divider()
        Button("Go to Artist") { vm.searchText = ""; vm.goToArtist(of: track) }
        Button("Go to Album") { vm.searchText = ""; vm.goToAlbum(of: track) }
    }
}

/// "Add to Playlist": always there, even with no playlists yet. A check marks
/// the playlists that already hold the song; choosing one again removes it.
struct AddToPlaylistMenu: View {
    let track: Track

    var body: some View {
        Menu("Add to Playlist") { AddToPlaylistItems(track: track) }
    }
}

/// The items of "Add to Playlist", also used by the player bar's + button.
struct AddToPlaylistItems: View {
    let track: Track
    @Environment(PlayerViewModel.self) private var vm

    var body: some View {
        Button("New Playlist") { vm.addToNewPlaylist(track) }
        if !vm.playlists.isEmpty {
            Divider()
            ForEach(vm.playlists) { playlist in
                Toggle(playlist.name, isOn: Binding(
                    get: { vm.isTrack(track, inPlaylist: playlist.id) },
                    set: { _ in vm.toggleTrack(track, inPlaylist: playlist.id) }
                ))
            }
        }
    }
}

extension View {
    /// Lets a song be dragged onto a playlist in the sidebar.
    func trackDraggable(_ track: Track, vm: PlayerViewModel) -> some View {
        draggable(vm.dragPayload(for: track)) {
            HStack(spacing: 8) {
                ArtworkView(image: track.thumbnail)
                    .frame(width: 28, height: 28)
                Text(track.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            .padding(6)
            .padding(.trailing, 6)
            .background(Capsule().fill(Theme.raised))
        }
    }
}
