import SwiftUI

/// Listening stats: totals, highlights, top artists and songs, when you
/// listen, and badges to unlock.
struct RecapView: View {
    @Environment(PlayerViewModel.self) private var vm
    @AppStorage("lyra.recapPeriod") private var period: ListeningRecap.Period = .week

    private let badgeColumns = [GridItem(.adaptive(minimum: 170, maximum: 260), spacing: 12)]

    var body: some View {
        let recap = ListeningRecap(listens: vm.history.listens, period: period)
        let tracksByPath = Dictionary(vm.tracks.map { ($0.url.standardizedFileURL.path, $0) },
                                      uniquingKeysWith: { first, _ in first })

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(kicker: "Your listening", title: "Recap", subtitle: subtitle(recap)) {
                    HStack(spacing: 4) {
                        ForEach(ListeningRecap.Period.allCases) { option in
                            Chip(title: option.label, isSelected: period == option) { period = option }
                        }
                    }
                }
                // PageHeader brings its own padding for full-width pages.
                .padding(.horizontal, -32)
                .padding(.bottom, -22)

                if recap.isEmpty {
                    emptyState
                } else {
                    stats(recap)
                    HStack(alignment: .top, spacing: 12) {
                        ranking("Top artists", items: recap.topArtists, tracks: tracksByPath, round: true) { track in
                            vm.goToArtist(of: track)
                        }
                        ranking("Top songs", items: recap.topSongs, tracks: tracksByPath, round: false) { track in
                            vm.play(track: track)
                        }
                    }
                    HStack(alignment: .top, spacing: 12) {
                        if !recap.highlights.isEmpty { highlights(recap) }
                        clock(recap)
                    }
                }
                badges(recap)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 150)
        }
        .animation(.easeInOut(duration: 0.2), value: period)
    }

    private func subtitle(_ recap: ListeningRecap) -> String {
        let range = recap.period == .allTime ? "All time" : "Last \(recap.period.label)"
        return recap.isEmpty ? range : "\(range) · \(ListeningRecap.duration(recap.seconds)) of music"
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar")
                .font(.system(size: 26))
                .foregroundStyle(Theme.tertiary)
            Text("Nothing here yet")
                .font(.system(size: 15, weight: .medium))
            Text("Play some music: your recap fills up as you listen.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .tileBackground(radius: 22)
    }

    // MARK: - Stats

    private func stats(_ recap: ListeningRecap) -> some View {
        HStack(spacing: 12) {
            stat(icon: "headphones", value: ListeningRecap.duration(recap.seconds), label: "listened")
            stat(icon: "play.fill", value: "\(recap.plays)", label: recap.plays == 1 ? "play" : "plays")
            stat(icon: "music.mic", value: "\(recap.artistCount)", label: recap.artistCount == 1 ? "artist" : "artists")
            stat(icon: "flame", value: "\(recap.currentStreak)",
                 label: recap.currentStreak == 1 ? "day streak" : "day streak")
        }
    }

    private func stat(icon: String, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.raised))
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(Theme.display(30))
                    .tracking(Theme.displayTracking(30))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileBackground(radius: 22)
    }

    // MARK: - Highlights

    private func highlights(_ recap: ListeningRecap) -> some View {
        section("Highlights") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(recap.highlights) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.canvas)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Theme.ink))
                        Text(item.text)
                            .font(.system(size: 14, weight: .medium))
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tileBackground(radius: 22)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: - Rankings

    private func ranking(
        _ title: String,
        items: [ListeningRecap.Ranked],
        tracks: [String: Track],
        round: Bool,
        onTap: @escaping (Track) -> Void
    ) -> some View {
        let maxPlays = Double(items.map(\.plays).max() ?? 1)
        return section(title) {
            VStack(spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    RankRow(
                        rank: index + 1,
                        item: item,
                        track: tracks[item.path],
                        round: round,
                        share: Double(item.plays) / maxPlays,
                        onTap: onTap
                    )
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tileBackground(radius: 22)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: - Clock

    private func clock(_ recap: ListeningRecap) -> some View {
        let peak = recap.byHour.max() ?? 0
        let peakHour = recap.byHour.firstIndex(of: peak) ?? 0
        return section("When you listen") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(0..<24, id: \.self) { hour in
                        let share = peak > 0 ? recap.byHour[hour] / peak : 0
                        Capsule()
                            .fill(Theme.ink.opacity(hour == peakHour ? 1 : 0.2 + 0.45 * share))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(4, 110 * share))
                            .help("\(ListeningRecap.hourLabel(hour)): \(ListeningRecap.duration(recap.byHour[hour]))")
                    }
                }
                .frame(height: 110, alignment: .bottom)
                HStack {
                    ForEach([0, 6, 12, 18], id: \.self) { hour in
                        Text(ListeningRecap.hourLabel(hour))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.tertiary)
            }
            .padding(18)
            .tileBackground(radius: 22)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: - Badges

    private func badges(_ recap: ListeningRecap) -> some View {
        let earned = recap.badges.filter(\.isEarned).count
        return section("Badges", trailing: "\(earned) of \(recap.badges.count)") {
            LazyVGrid(columns: badgeColumns, alignment: .leading, spacing: 12) {
                ForEach(recap.badges) { badge in
                    BadgeTile(badge: badge)
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, trailing: String? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 20, weight: .medium))
                    .tracking(-0.2)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                }
            }
            content()
        }
    }
}

// MARK: - Rows and tiles

private struct RankRow: View {
    let rank: Int
    let item: ListeningRecap.Ranked
    let track: Track?
    let round: Bool
    /// Plays relative to the #1, 0...1.
    let share: Double
    let onTap: (Track) -> Void
    @State private var isHovered = false

    var body: some View {
        Button { if let track { onTap(track) } } label: {
            HStack(spacing: 12) {
                Text("\(rank)")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(rank == 1 ? Theme.ink : Theme.tertiary)
                    .frame(width: 18)
                ArtworkView(image: track?.thumbnail, radius: round ? 20 : Theme.Radius.thumb,
                            glyph: round ? "music.mic" : "music.note")
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.name)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(item.plays) \(item.plays == 1 ? "play" : "plays")")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(Theme.secondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.ink.opacity(0.08))
                            Capsule().fill(Theme.ink.opacity(rank == 1 ? 0.9 : 0.45))
                                .frame(width: max(4, geo.size.width * share))
                        }
                    }
                    .frame(height: 4)
                    if !item.detail.isEmpty {
                        Text(item.detail)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(isHovered ? Theme.ink.opacity(0.04) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(track == nil)
        .onHover { isHovered = $0 }
    }
}

private struct BadgeTile: View {
    let badge: ListeningRecap.Badge

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: badge.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(badge.isEarned ? Theme.canvas : Theme.tertiary)
                .frame(width: 38, height: 38)
                .background(Circle().fill(badge.isEarned ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Theme.raised)))
            VStack(alignment: .leading, spacing: 3) {
                Text(badge.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(badge.isEarned ? Theme.ink : Theme.secondary)
                Text(badge.detail)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.ink.opacity(0.08))
                    Capsule().fill(Theme.ink.opacity(badge.isEarned ? 0.9 : 0.4))
                        .frame(width: max(4, geo.size.width * badge.progress))
                }
            }
            .frame(height: 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tileBackground(radius: 22)
        .opacity(badge.isEarned ? 1 : 0.85)
    }
}
