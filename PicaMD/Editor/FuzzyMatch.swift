import Foundation

/// Lean fuzzy-string scorer — used by the Command Palette to rank
/// matches against the user's query. Pure logic, no AppKit, easy to
/// unit-test.
///
/// Algorithm: walk both strings left-to-right; require every char of
/// the query to appear in the candidate in order. If any char is
/// missing, return `nil` (no match). Otherwise score by:
///
///   +10  per matching char
///   +25  bonus when the match is at the start of a word
///        (start of string, or preceded by space / punctuation)
///   +15  bonus when the match is at the very start of the candidate
///   −1   per character of "gap" between the previous match and this one
///
/// Higher scores rank higher. Comparisons are case-insensitive.
enum FuzzyMatch {
    /// Returns `nil` when the candidate doesn't contain every query
    /// character in order. Otherwise the integer score.
    static func score(query: String, in candidate: String) -> Int? {
        let q = Array(query.lowercased())
        let c = Array(candidate.lowercased())
        guard !q.isEmpty else { return 0 }
        guard q.count <= c.count else { return nil }

        var score = 0
        var qi = 0
        var lastMatch = -1

        for ci in 0..<c.count {
            guard qi < q.count else { break }
            if c[ci] == q[qi] {
                score += 10
                if ci == 0 {
                    score += 15
                } else {
                    let prev = c[ci - 1]
                    if prev == " " || prev == "-" || prev == "_" || prev == "/" || prev == "." {
                        score += 25
                    }
                }
                if lastMatch >= 0 {
                    score -= max(0, ci - lastMatch - 1)
                }
                lastMatch = ci
                qi += 1
            }
        }
        guard qi == q.count else { return nil }
        return score
    }
}
