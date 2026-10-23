import XCTest
@testable import Lyra

final class LRCParserTests: XCTestCase {
    func testParsesMultipleTimestamps() {
        let input = """
        [00:01.00][00:02.50]Hello
        [01:03.20]World
        """

        let lines = LRCParser.parse(input)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].text, "Hello")
        XCTAssertEqual(lines[1].text, "Hello")
        XCTAssertEqual(lines[2].text, "World")
        XCTAssertEqual(lines[0].timestamp, 1.0, accuracy: 0.001)
        XCTAssertEqual(lines[1].timestamp, 2.5, accuracy: 0.001)
        XCTAssertEqual(lines[2].timestamp, 63.2, accuracy: 0.001)
    }

    func testIgnoresLinesWithoutText() {
        let input = """
        [00:10.00]
        [00:12.00]   test
        """
        let lines = LRCParser.parse(input)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.text, "test")
    }
}
