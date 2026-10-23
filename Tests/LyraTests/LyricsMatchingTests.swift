import XCTest
@testable import Lyra

final class LyricsMatchingTests: XCTestCase {
    func testQueryVariantsIncludeSanitizedTitle() {
        let variants = LyricsMatcher.queryVariants(
            trackName: "Song Title (Live) feat. Artist",
            artistName: "Main Artist"
        )

        XCTAssertTrue(variants.contains { $0.trackName == "Song Title" && $0.artistName == "Main Artist" })
        XCTAssertTrue(variants.contains { $0.trackName == "Song Title" && $0.artistName.isEmpty })
    }

    func testScoringPrefersSyncedAndCloseDuration() {
        let candidate = LyricsQueryCandidate(trackName: "Il Dito Medio Di Galileo", artistName: "Caparezza")
        let synced = LyricsSearchResult(
            id: "1",
            trackName: "Il Dito Medio Di Galileo",
            artistName: "Caparezza",
            albumName: "Il Sogno Eretico",
            duration: 362,
            syncedLyrics: "[00:01.00]x",
            plainLyrics: nil
        )
        let plain = LyricsSearchResult(
            id: "2",
            trackName: "Il Dito Medio Di Galileo",
            artistName: "Caparezza",
            albumName: "Il Sogno Eretico",
            duration: 400,
            syncedLyrics: nil,
            plainLyrics: "text"
        )

        let syncedScore = LyricsMatcher.score(
            result: synced,
            candidate: candidate,
            expectedDuration: 362.1,
            expectedAlbum: "Il Sogno Eretico"
        )
        let plainScore = LyricsMatcher.score(
            result: plain,
            candidate: candidate,
            expectedDuration: 362.1,
            expectedAlbum: "Il Sogno Eretico"
        )

        XCTAssertGreaterThan(syncedScore, plainScore)
    }
}
