import Foundation

/// Stats over the listening history for one period: totals, top artists and
/// songs, when you listen, streaks, badges and a few plain-language
/// highlights.
struct ListeningRecap {
    enum Period: String, CaseIterable, Identifiable {
        case week, month, allTime
        var id: Self { self }

        var label: String {
            switch self {
            case .week:    return "7 days"
            case .month:   return "30 days"
            case .allTime: return "All time"
            }
        }

        /// Rolling windows, so a new week or month doesn't start empty.
        var days: Int? {
            switch self {
            case .week:    return 7
            case .month:   return 30
            case .allTime: return nil
            }
        }

        /// Start of the period, or nil for all time.
        func start(now: Date, calendar: Calendar) -> Date? {
            days.flatMap { calendar.date(byAdding: .day, value: -$0, to: now) }
        }
    }

    struct Ranked: Identifiable {
        let name: String
        /// Artist for songs; empty for artists.
        let detail: String
        /// A file of this artist or song, for artwork and playback.
        let path: String
        let plays: Int
        let seconds: Double
        var id: String { name + "\u{1F}" + detail }
    }

    struct Badge: Identifiable {
        let id: String
        let icon: String
        let title: String
        let detail: String
        /// 0...1; 1 means earned.
        let progress: Double
        var isEarned: Bool { progress >= 1 }
    }

    struct Highlight: Identifiable {
        let icon: String
        let text: String
        var id: String { text }
    }

    let period: Period
    let seconds: Double
    let plays: Int
    let artistCount: Int
    let songCount: Int
    let topArtists: [Ranked]
    let topSongs: [Ranked]
    /// Seconds listened per hour of the day, 0...23.
    let byHour: [Double]
    let currentStreak: Int
    let longestStreak: Int
    let badges: [Badge]
    let highlights: [Highlight]

    var isEmpty: Bool { plays == 0 }

    init(listens all: [Listen], period: Period, now: Date = Date(), calendar: Calendar = .current) {
        self.period = period
        let start = period.start(now: now, calendar: calendar)
        let listens = all.filter { start == nil || $0.start >= start! }
        let plays = listens.filter(\.countsAsPlay)

        self.seconds = listens.reduce(0) { $0 + $1.seconds }
        self.plays = plays.count
        self.artistCount = Set(plays.map(\.primaryArtist)).count
        self.songCount = Set(plays.map(\.path)).count

        topArtists = Self.rank(listens, key: { $0.primaryArtist }) { group in
            Ranked(name: group[0].primaryArtist, detail: "", path: group[0].path,
                   plays: group.filter(\.countsAsPlay).count, seconds: group.reduce(0) { $0 + $1.seconds })
        }
        topSongs = Self.rank(listens, key: { $0.path }) { group in
            Ranked(name: group[0].title, detail: group[0].artist, path: group[0].path,
                   plays: group.filter(\.countsAsPlay).count, seconds: group.reduce(0) { $0 + $1.seconds })
        }

        var hours = [Double](repeating: 0, count: 24)
        for listen in listens { hours[calendar.component(.hour, from: listen.start)] += listen.seconds }
        byHour = hours

        // Streaks use the whole history: they're about habits, not the period.
        let days = Set(all.filter(\.countsAsPlay).map { calendar.startOfDay(for: $0.start) })
        (currentStreak, longestStreak) = Self.streaks(days: days, today: calendar.startOfDay(for: now), calendar: calendar)

        badges = Self.badges(all: all, longestStreak: longestStreak, calendar: calendar)
        highlights = Self.highlights(
            listens: listens, all: all, period: period, now: now, calendar: calendar,
            seconds: seconds, topArtists: topArtists, topSongs: topSongs, byHour: byHour,
            currentStreak: currentStreak
        )
    }

    // MARK: - Ranking

    private static func rank(_ listens: [Listen], key: (Listen) -> String,
                             make: ([Listen]) -> Ranked) -> [Ranked] {
        Dictionary(grouping: listens, by: key).values
            .map(make)
            .filter { $0.plays > 0 }
            .sorted { ($0.plays, $0.seconds) > ($1.plays, $1.seconds) }
            .prefix(5)
            .map { $0 }
    }

    // MARK: - Streaks

    /// Current streak counts today, or yesterday if nothing played yet today.
    private static func streaks(days: Set<Date>, today: Date, calendar: Calendar) -> (Int, Int) {
        func previous(_ day: Date) -> Date { calendar.date(byAdding: .day, value: -1, to: day)! }

        var current = 0
        var day = days.contains(today) ? today : previous(today)
        while days.contains(day) { current += 1; day = previous(day) }

        var longest = 0
        for start in days where !days.contains(previous(start)) {
            var length = 0
            var d = start
            while days.contains(d) { length += 1; d = calendar.date(byAdding: .day, value: 1, to: d)! }
            longest = max(longest, length)
        }
        return (current, longest)
    }

    // MARK: - Badges

    private static func badges(all: [Listen], longestStreak: Int, calendar: Calendar) -> [Badge] {
        let plays = all.filter(\.countsAsPlay)
        let hours = all.reduce(0) { $0 + $1.seconds } / 3600
        let artists = Set(plays.map(\.primaryArtist)).count
        let nightPlays = plays.filter { (0..<5).contains(calendar.component(.hour, from: $0.start)) }.count
        let topSongPlays = Dictionary(grouping: plays, by: \.path).values.map(\.count).max() ?? 0
        let topArtistPlays = Dictionary(grouping: plays, by: \.primaryArtist).values.map(\.count).max() ?? 0

        func badge(_ id: String, _ icon: String, _ title: String, _ value: Double, of goal: Double, _ unit: String) -> Badge {
            let shown = Int(min(value, goal))
            return Badge(id: id, icon: icon, title: title,
                         detail: "\(shown)/\(Int(goal)) \(unit)", progress: min(1, value / goal))
        }
        return [
            badge("first", "play.fill", "First play", Double(plays.count), of: 1, "song"),
            badge("century", "100.circle", "Century", Double(plays.count), of: 100, "plays"),
            badge("marathon", "timer", "Marathon", hours, of: 10, "hours"),
            badge("streak", "flame", "On fire", Double(longestStreak), of: 7, "days in a row"),
            badge("explorer", "safari", "Explorer", Double(artists), of: 25, "artists"),
            badge("superfan", "star", "Superfan", Double(topArtistPlays), of: 50, "plays of one artist"),
            badge("onrepeat", "repeat", "On repeat", Double(topSongPlays), of: 10, "plays of one song"),
            badge("nightowl", "moon.stars", "Night owl", Double(nightPlays), of: 20, "plays after midnight"),
        ]
    }

    // MARK: - Highlights

    private static func highlights(
        listens: [Listen], all: [Listen], period: Period, now: Date, calendar: Calendar,
        seconds: Double, topArtists: [Ranked], topSongs: [Ranked], byHour: [Double],
        currentStreak: Int
    ) -> [Highlight] {
        guard seconds > 0 else { return [] }
        var out: [Highlight] = []

        if let artist = topArtists.first {
            let share = Int((artist.seconds / seconds * 100).rounded())
            out.append(Highlight(icon: "crown",
                                 text: "\(artist.name) is your #1: \(artist.plays) plays, \(share)% of your listening."))
        }
        if let song = topSongs.first, song.plays >= 3 {
            out.append(Highlight(icon: "repeat",
                                 text: "You couldn't stop playing \(song.name): \(song.plays) times."))
        }

        // When you listen.
        let night = (byHour[22...].reduce(0, +) + byHour[..<5].reduce(0, +)) / seconds
        let morning = byHour[5..<11].reduce(0, +) / seconds
        if night >= 0.35 {
            out.append(Highlight(icon: "moon.stars",
                                 text: "Night owl: \(Int((night * 100).rounded()))% of your listening happens after 10 PM."))
        } else if morning >= 0.35 {
            out.append(Highlight(icon: "sunrise",
                                 text: "Early bird: \(Int((morning * 100).rounded()))% of your listening happens before 11 AM."))
        } else if let peak = byHour.indices.max(by: { byHour[$0] < byHour[$1] }) {
            out.append(Highlight(icon: "clock", text: "You listen most around \(hourLabel(peak))."))
        }

        // Compared with the previous period.
        if let days = period.days, let start = period.start(now: now, calendar: calendar) {
            if let previousStart = calendar.date(byAdding: .day, value: -days, to: start) {
                let before = all.filter { $0.start >= previousStart && $0.start < start }.reduce(0) { $0 + $1.seconds }
                if before > 600 {
                    let change = Int(((seconds - before) / before * 100).rounded())
                    let what = "the \(days) days before"
                    if change >= 5 {
                        out.append(Highlight(icon: "arrow.up.right", text: "\(change)% more music than \(what)."))
                    } else if change <= -5 {
                        out.append(Highlight(icon: "arrow.down.right", text: "\(-change)% less music than \(what)."))
                    }
                }
            }
        }

        if currentStreak >= 2 {
            out.append(Highlight(icon: "flame", text: "\(currentStreak) days in a row. Keep it going."))
        }

        let distinct = Set(listens.filter(\.countsAsPlay).map(\.primaryArtist)).count
        if distinct >= 8 {
            out.append(Highlight(icon: "safari", text: "\(distinct) different artists. You get around."))
        }
        return out
    }

    static func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(.dateTime.hour())
    }

    /// "12h 30m", "45m".
    static func duration(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}
