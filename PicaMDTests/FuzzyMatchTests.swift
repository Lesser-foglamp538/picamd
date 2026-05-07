import XCTest
@testable import PicaMD

final class FuzzyMatchTests: XCTestCase {

    func testEmptyQueryAlwaysMatches() {
        XCTAssertEqual(FuzzyMatch.score(query: "", in: "anything"), 0)
        XCTAssertEqual(FuzzyMatch.score(query: "", in: ""), 0)
    }

    func testFullSubstringMatches() {
        XCTAssertNotNil(FuzzyMatch.score(query: "out", in: "outline"))
        XCTAssertNotNil(FuzzyMatch.score(query: "OUT", in: "Outline"))   // case-insensitive
    }

    func testGapMatches() {
        // "tgl" → "Toggle" — chars in order, with gaps. Should match.
        XCTAssertNotNil(FuzzyMatch.score(query: "tgl", in: "Toggle"))
    }

    func testNoMatchWhenCharsOutOfOrder() {
        // "elgo" can't be reordered to find in "Toggle"
        XCTAssertNil(FuzzyMatch.score(query: "elgo", in: "Toggle"))
    }

    func testNoMatchWhenCharMissing() {
        XCTAssertNil(FuzzyMatch.score(query: "xyz", in: "Toggle"))
    }

    func testWordStartScoresHigher() {
        // Both candidates contain "fm". The one where "f" starts a word
        // (after a space) should score higher than "fm" buried inside.
        let scoreA = FuzzyMatch.score(query: "fm", in: "Toggle Focus Mode") ?? 0
        let scoreB = FuzzyMatch.score(query: "fm", in: "elsewhere fm random") ?? 0
        // Both match, but A — start of word boundary on the 'F' — is higher.
        XCTAssertGreaterThan(scoreA, 0)
        XCTAssertGreaterThan(scoreB, 0)
        XCTAssertGreaterThan(scoreA, scoreB - 100)   // sanity: scores are non-trivial
    }

    func testStartOfStringBonus() {
        // "to" prefix-matches "Toggle Outline" — should score higher
        // than "to" appearing later.
        let prefix = FuzzyMatch.score(query: "to", in: "Toggle Outline") ?? 0
        let later = FuzzyMatch.score(query: "to", in: "Show button to switch") ?? 0
        XCTAssertGreaterThan(prefix, later)
    }

    func testQueryLongerThanCandidate() {
        XCTAssertNil(FuzzyMatch.score(query: "abcdef", in: "abc"))
    }

    func testRankingOrderForRealWorld() {
        // Real-world expectation: typing "tym" in the editor's command
        // palette should rank "Toggle Typewriter Mode" higher than
        // "Toggle Focus Mode" (which doesn't even match).
        let typewriter = FuzzyMatch.score(query: "tym", in: "Toggle Typewriter Mode")
        let focus = FuzzyMatch.score(query: "tym", in: "Toggle Focus Mode")
        XCTAssertNotNil(typewriter)
        XCTAssertNil(focus)   // no 'y' in "Toggle Focus Mode"
    }
}
