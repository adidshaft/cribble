import Foundation

enum FuzzyMatch {
    struct Result: Equatable, Sendable {
        let score: Int
        let matchedOffsets: [Int]
    }

    static func score(query: String, candidate: String, recencyRank: Int? = nil) -> Result? {
        let query = normalize(query)
        let candidate = normalize(candidate)
        guard !query.isEmpty else {
            return Result(score: recencyBonus(for: recencyRank), matchedOffsets: [])
        }
        guard candidate.count >= query.count else { return nil }

        let offsets = subsequenceOffsets(query: query, candidate: candidate)
        guard !offsets.isEmpty else { return nil }

        var score = 1_000
        if candidate == query {
            score += 9_000
        } else if candidate.hasPrefix(query) {
            score += 7_000
        } else if acronym(for: candidate).hasPrefix(query) {
            score += 6_000
        }

        score += longestContiguousRun(in: offsets) * 120
        score += boundaryMatchCount(offsets: offsets, candidate: candidate) * 80
        score -= max(0, candidate.count - query.count) * 2
        score += recencyBonus(for: recencyRank)

        return Result(score: score, matchedOffsets: offsets)
    }

    static func ranked<Candidate>(
        query: String,
        candidates: [Candidate],
        recencyRank: (Candidate) -> Int? = { _ in nil },
        text: (Candidate) -> [String]
    ) -> [Candidate] {
        candidates.compactMap { candidate -> (Candidate, Int)? in
            let bestScore = text(candidate).compactMap {
                score(query: query, candidate: $0, recencyRank: recencyRank(candidate))?.score
            }.max()
            return bestScore.map { (candidate, $0) }
        }
        .sorted { lhs, rhs in lhs.1 > rhs.1 }
        .map(\.0)
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "\\", with: "/")
            .replacingOccurrences(of: ".md", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func subsequenceOffsets(query: String, candidate: String) -> [Int] {
        let candidateCharacters = Array(candidate)
        var offsets: [Int] = []
        var cursor = 0

        for character in query {
            guard let found = candidateCharacters[cursor...].firstIndex(of: character) else {
                return []
            }
            offsets.append(found)
            cursor = found + 1
        }
        return offsets
    }

    private static func acronym(for candidate: String) -> String {
        var result = ""
        var previousWasBoundary = true
        for character in candidate {
            if character.isLetter || character.isNumber {
                if previousWasBoundary {
                    result.append(character)
                }
                previousWasBoundary = false
            } else {
                previousWasBoundary = true
            }
        }
        return result
    }

    private static func longestContiguousRun(in offsets: [Int]) -> Int {
        guard !offsets.isEmpty else { return 0 }
        var best = 1
        var current = 1
        for index in offsets.indices.dropFirst() {
            if offsets[index] == offsets[offsets.index(before: index)] + 1 {
                current += 1
            } else {
                current = 1
            }
            best = max(best, current)
        }
        return best
    }

    private static func boundaryMatchCount(offsets: [Int], candidate: String) -> Int {
        let characters = Array(candidate)
        return offsets.filter { offset in
            offset == 0 || !(characters[offset - 1].isLetter || characters[offset - 1].isNumber)
        }.count
    }

    private static func recencyBonus(for rank: Int?) -> Int {
        guard let rank else { return 0 }
        return max(0, 250 - (rank * 25))
    }
}
