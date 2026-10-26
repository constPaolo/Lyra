import XCTest
@testable import Lyra

final class ListeningRecapTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = ISO8601DateFormatter().date(from: "2026-10-26T20:00:00Z")!

    private func listen(_ title: String, artist: String, daysAgo: Int, seconds: Double = 200,
                        duration: Double = 200) -> Listen {
        Listen(path: "/music/\(title).flac", title: title, artist: artist, album: "A",
               start: calendar.date(byAdding: .day, value: -daysAgo, to: now)!,
               seconds: seconds, duration: duration)
    }

    func testShortListensDontCountAsPlays() {
        let skip = listen("Skip", artist: "X", daysAgo: 0, seconds: 12)
        XCTAssertFalse(skip.countsAsPlay)
        // Half of a short song is enough.
        XCTAssertTrue(listen("Short", artist: "X", daysAgo: 0, seconds: 25, duration: 40).countsAsPlay)

        let recap = ListeningRecap(listens: [skip], period: .allTime, now: now, calendar: calendar)
        XCTAssertEqual(recap.plays, 0)
        XCTAssertTrue(recap.isEmpty)
    }

    func testRanksByPlaysAndCreditsTheFirstArtist() {
        let listens = [
            listen("A", artist: "MadMan, Nitro", daysAgo: 0),
            listen("B", artist: "MadMan", daysAgo: 1),
            listen("C", artist: "Caparezza", daysAgo: 1),
        ]
        let recap = ListeningRecap(listens: listens, period: .week, now: now, calendar: calendar)
        XCTAssertEqual(recap.topArtists.first?.name, "MadMan")
        XCTAssertEqual(recap.topArtists.first?.plays, 2)
        XCTAssertEqual(recap.artistCount, 2)
    }

    func testPeriodsAreRollingWindows() {
        let listens = [listen("Old", artist: "X", daysAgo: 20), listen("New", artist: "X", daysAgo: 2)]
        XCTAssertEqual(ListeningRecap(listens: listens, period: .week, now: now, calendar: calendar).plays, 1)
        XCTAssertEqual(ListeningRecap(listens: listens, period: .month, now: now, calendar: calendar).plays, 2)
    }

    func testStreaks() {
        // Yesterday and the two days before, then a gap, then four days in a row.
        let days = [1, 2, 3, 6, 7, 8, 9]
        let listens = days.map { listen("S\($0)", artist: "X", daysAgo: $0) }
        let recap = ListeningRecap(listens: listens, period: .allTime, now: now, calendar: calendar)
        XCTAssertEqual(recap.currentStreak, 3)
        XCTAssertEqual(recap.longestStreak, 4)
    }
}
