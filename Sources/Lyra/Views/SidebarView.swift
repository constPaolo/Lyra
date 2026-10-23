import SwiftUI
import AppKit

struct SidebarView: View {
    @Environment(PlayerViewModel.self) private var vm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onOpenSettings: () -> Void = {}
    @State private var showDebug = false

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                header

                VStack(alignment: .leading, spacing: 2) {
                    navRow(.home, icon: "house", title: "Home", count: nil)
                    navRow(.allTracks, icon: "music.note.list", title: "All Tracks", count: vm.tracks.count)
                    navRow(.liked, icon: "heart", title: "Liked", count: vm.likedTracks.count)
                    navRow(.albums, icon: "square.stack", title: "Albums", count: vm.albums.count)
                    navRow(.artists, icon: "music.mic", title: "Artists", count: vm.artists.count)
                    navRow(.folders, icon: "folder", title: "Folders", count: vm.browsableFolders.count)
                    navRow(.queue, icon: "list.bullet", title: "Queue", count: vm.upNextTracks.count)
                }
                .padding(.horizontal, 12)

                playlistsSection
                    .padding(.top, 22)

                footer
            }
            .frame(maxHeight: .infinity, alignment: .top)

            if showDebug {
                DebugView(onClose: { showDebug = false })
                    .environment(vm)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .background(Theme.canvas)
        .animation(reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.28, dampingFraction: 0.86), value: showDebug)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            LyraMark(size: 26)
            Text("Lyra")
                .font(.system(size: 16, weight: .semibold))
            ZStack {
                if vm.isScanning {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                }
            }
            .frame(width: 16, height: 16)
            Spacer()
        }
        .padding(.leading, 20)
        .padding(.trailing, 14)
        // Lines up with the search bar row.
        .padding(.top, 17)
        .padding(.bottom, 22)
    }

    // MARK: - Navigation

    private func navRow(_ tab: SidebarTab, icon: String, title: String, count: Int?) -> some View {
        SidebarRow(
            icon: icon,
            title: title,
            count: count,
            isSelected: vm.activeSidebarTab == tab
        ) {
            vm.browsePage = page(for: tab)
        }
    }

    private func page(for tab: SidebarTab) -> BrowsePage {
        switch tab {
        case .home:      return .home
        case .allTracks: return .allTracks
        case .liked:     return .liked
        case .artists:   return .artistsIndex
        case .albums:    return .albumsIndex
        case .folders:   return .foldersIndex
        case .playlists: return .playlistsIndex
        case .queue:     return .queue
        }
    }

    // MARK: - Playlists

    private var playlistsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Playlists")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
                Spacer()
                Button(action: createPlaylist) {
                    Image(systemName: "plus")
                }
                .buttonStyle(CircleIconButtonStyle(size: 22))
                .help("New playlist")
            }
            .padding(.leading, 24)
            .padding(.trailing, 16)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if vm.playlists.isEmpty {
                        Text("No playlists yet")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.tertiary)
                            .padding(.horizontal, 24)
                            .padding(.top, 6)
                    } else {
                        ForEach(vm.playlists) { playlist in
                            SidebarRow(
                                icon: nil,
                                title: playlist.name,
                                count: vm.trackCount(in: playlist),
                                isSelected: vm.browsePage == .playlist(id: playlist.id)
                            ) {
                                vm.browsePage = .playlist(id: playlist.id)
                            }
                            .padding(.horizontal, 12)
                            .contextMenu {
                                Button("Rename Playlist") { renamePlaylist(playlist) }
                                Button("Delete Playlist", role: .destructive) { vm.deletePlaylist(id: playlist.id) }
                            }
                        }
                    }
                }
                .padding(.bottom, 12)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: addFolder) { Image(systemName: "folder.badge.plus") }
                .buttonStyle(CircleIconButtonStyle())
                .help("Add music folder")
            Button(action: onOpenSettings) { Image(systemName: "gearshape") }
                .buttonStyle(CircleIconButtonStyle())
                .help("Settings")
            Button { showDebug.toggle() } label: { Image(systemName: "ant") }
                .buttonStyle(CircleIconButtonStyle(isActive: showDebug))
                .help("Debug panel")
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
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

// MARK: - Row

private struct SidebarRow: View {
    let icon: String?
    let title: String
    let count: Int?
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 18)
                        .foregroundStyle(isSelected ? Theme.ink : Theme.secondary)
                }
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.ink : Theme.ink.opacity(0.7))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let count {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.tertiary)
                        .rollingDigits(Double(count))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(
                Capsule().fill(
                    isSelected ? Theme.chip : (isHovered ? Theme.ink.opacity(0.03) : .clear)
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - Logo

/// Ink rounded square with a waveform glyph.
struct LyraMark: View {
    var size: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(Theme.ink)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "waveform")
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(Theme.canvas)
            )
    }
}
