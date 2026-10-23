import XCTest
@testable import Lyra

final class SearchScoreTests: XCTestCase {
    func testRanksExactThenPrefixThenWordThenSubstring() {
        let q = SearchScore.fold("capa")
        XCTAssertEqual(SearchScore.score("Capa", q), 1)
        XCTAssertEqual(SearchScore.score("Caparezza", q), 0.8)
        XCTAssertEqual(SearchScore.score("Il Dito Medio - Capa Remix", q), 0.6)
        XCTAssertEqual(SearchScore.score("Escapade", q), 0.3)
        XCTAssertEqual(SearchScore.score("Bocelli", q), 0)
    }

    func testIgnoresCaseAndDiacritics() {
        let q = SearchScore.fold("DIVENTERO")
        XCTAssertEqual(SearchScore.score("Io Diventerò Qualcuno", q), 0.6)
    }
}
