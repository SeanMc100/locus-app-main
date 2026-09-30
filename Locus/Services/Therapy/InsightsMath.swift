import Foundation

// Foundation-only (compiled into the Mac harness too). All insights are
// computed locally from the user's own records.

/// One prediction with a known outcome: a behavioral experiment, or a
/// Check the Facts threat the user later marked.
struct CalibrationPoint: Hashable, Sendable {
    /// 0–100: how sure they were it would happen.
    var confidence: Double
    /// 1 came true, 0.5 partly, 0 didn't.
    var outcome: Double
    var severityExpected: Double?
    var severityActual: Double?
}

struct CalibrationSummary: Sendable {
    struct Bucket: Hashable, Sendable, Identifiable {
        var id: Int { lower }
        let lower: Int
        let upper: Int
        let count: Int
        /// Average stated confidence in the bucket, 0–100.
        let predicted: Double
        /// Share that came true, 0–100.
        let actual: Double
    }

    let count: Int
    /// 0–100.
    let cameTrueRate: Double
    /// 0–100.
    let averageEstimate: Double
    /// Among those that came true (fully or partly): actual severity as a
    /// percentage of expected. Nil if none came true or no ratings.
    let severityRatio: Double?
    let buckets: [Bucket]
}

enum Trend: String, Sendable {
    case weaker, stronger, steady, unknown
}

/// Placeholder for later: sleep or activity data (e.g. HealthKit) to
/// correlate with mood and intensity. Nothing provides it yet.
protocol ContextSignalProvider {
    func hoursSlept(on day: Date) async -> Double?
    func activeMinutes(on day: Date) async -> Double?
}

enum InsightsMath {
    /// Completed predictions needed before the calibration headline shows.
    static let calibrationMinimum = 5

    static func calibration(_ points: [CalibrationPoint]) -> CalibrationSummary {
        let n = points.count
        guard n > 0 else {
            return CalibrationSummary(count: 0, cameTrueRate: 0, averageEstimate: 0, severityRatio: nil, buckets: [])
        }
        let cameTrue = points.map(\.outcome).reduce(0, +) / Double(n) * 100
        let estimate = points.map(\.confidence).reduce(0, +) / Double(n)

        let bad = points.filter { $0.outcome > 0 }
        let ratios = bad.compactMap { p -> Double? in
            guard let e = p.severityExpected, let a = p.severityActual, e > 0 else { return nil }
            return a / e * 100
        }
        let severity = ratios.isEmpty ? nil : ratios.reduce(0, +) / Double(ratios.count)

        var buckets: [CalibrationSummary.Bucket] = []
        for lower in stride(from: 0, to: 100, by: 20) {
            let upper = lower + 20
            let inBucket = points.filter {
                $0.confidence >= Double(lower) && ($0.confidence < Double(upper) || (upper == 100 && $0.confidence <= 100))
            }
            guard !inBucket.isEmpty else { continue }
            buckets.append(.init(lower: lower, upper: upper, count: inBucket.count,
                                 predicted: inBucket.map(\.confidence).reduce(0, +) / Double(inBucket.count),
                                 actual: inBucket.map(\.outcome).reduce(0, +) / Double(inBucket.count) * 100))
        }
        return CalibrationSummary(count: n, cameTrueRate: cameTrue, averageEstimate: estimate,
                                  severityRatio: severity, buckets: buckets)
    }

    /// Direction of a belief across its ratings: the first rating against
    /// the latest, ignoring changes under 10 points.
    static func trend(_ ratings: [BeliefRatingPoint]) -> Trend {
        let sorted = ratings.sorted { $0.date < $1.date }
        guard let first = sorted.first, let last = sorted.last, sorted.count >= 2 else { return .unknown }
        let delta = last.value - first.value
        if delta <= -10 { return .weaker }
        if delta >= 10 { return .stronger }
        return .steady
    }

    /// Most frequent items, case-insensitive, most common first.
    static func topCounts(_ items: [String], limit: Int = 5) -> [(String, Int)] {
        var counts: [String: (display: String, n: Int)] = [:]
        for raw in items {
            let item = raw.trimmed
            guard !item.isEmpty else { continue }
            let key = item.lowercased()
            counts[key] = (counts[key]?.display ?? item, (counts[key]?.n ?? 0) + 1)
        }
        return counts.values.sorted { $0.n != $1.n ? $0.n > $1.n : $0.display < $1.display }
            .prefix(limit).map { ($0.display, $0.n) }
    }

    /// Time-of-day blocks for the heatmap.
    static let dayParts = ["Night", "Morning", "Afternoon", "Evening"]

    /// [weekday 0 = Monday … 6][day part] counts of high-intensity moments.
    static func heatmap(_ moments: [Date], calendar: Calendar = .current) -> [[Int]] {
        var grid = Array(repeating: Array(repeating: 0, count: dayParts.count), count: 7)
        for date in moments {
            let weekday = (calendar.component(.weekday, from: date) + 5) % 7   // Monday = 0
            let hour = calendar.component(.hour, from: date)
            grid[weekday][min(hour / 6, 3)] += 1
        }
        return grid
    }

    struct Effect: Hashable, Sendable {
        let name: String
        let before: Double
        let after: Double
        let count: Int
        var change: Double { after - before }
    }

    /// Average before → after per group (skills, activities).
    static func effects(_ samples: [(name: String, before: Double, after: Double)]) -> [Effect] {
        Dictionary(grouping: samples, by: \.name).map { name, group in
            Effect(name: name,
                   before: group.map(\.before).reduce(0, +) / Double(group.count),
                   after: group.map(\.after).reduce(0, +) / Double(group.count),
                   count: group.count)
        }
    }

    /// Vulnerability factors across chains: "Poor sleep appeared in 4 of 5
    /// chains".
    static func chainFactors(_ chains: [ChainData]) -> [(factor: String, count: Int, of: Int)] {
        let all = chains.flatMap { chain in
            Set(chain.vulnerabilities + (chain.vulnerabilityOther.trimmed.isEmpty ? [] : [chain.vulnerabilityOther.trimmed]))
        }
        return topCounts(all, limit: 6).map { ($0.0, $0.1, chains.count) }
    }

    /// Links that recur across chains (same type and wording).
    static func recurringLinks(_ chains: [ChainData]) -> [(String, Int)] {
        let all = chains.flatMap { chain in
            Set(chain.links.map { "\($0.kind.label): \($0.text.trimmed)" })
        }
        return topCounts(all, limit: 5).filter { $0.1 >= 2 }
    }
}

/// Simplified Leitner spaced repetition for the reframe deck.
enum SpacedRepetition {
    /// Days until the next review, by box.
    static let intervals = [1, 2, 4, 8, 16, 32]

    static func schedule(box: Int, rating: PracticeRating, from date: Date = .now,
                         calendar: Calendar = .current) -> (box: Int, due: Date) {
        let newBox: Int
        switch rating {
        case .stillBelieve: newBox = 1
        case .gettingThere: newBox = max(1, box)
        case .strong: newBox = min(box + 1, intervals.count)
        }
        let days = intervals[newBox - 1]
        let due = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: date)) ?? date
        return (newBox, due)
    }
}
