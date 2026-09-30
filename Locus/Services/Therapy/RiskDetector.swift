import Foundation

// Foundation-only (compiled into the Mac harness too).

enum RiskCategory: String, Codable, CaseIterable, Sendable {
    case suicidalIdeation, selfHarm, harmToOthers, hopelessnessWithIntent
}

struct RiskAssessment: Equatable, Sendable {
    enum Source: String, Sendable { case none, deterministic, ai }

    var categories: Set<RiskCategory> = []
    /// The matched text, used so the same words don't re-trigger the
    /// screen once the user has seen it and chosen to carry on.
    var matches: Set<String> = []
    var source: Source = .none

    var isRisk: Bool { !categories.isEmpty || source == .ai }

    static let clear = RiskAssessment()
}

/// The offline risk check. Runs on journal entries and on free-text step
/// input before and during every flow. It never depends on AI; AI can only
/// add to what it finds (`escalate`), never clear it.
enum RiskDetector {

    static func assess(_ text: String) -> RiskAssessment {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return .clear }
        var result = RiskAssessment()

        func scan(_ patterns: [String], as category: RiskCategory) {
            for pattern in patterns {
                if let match = firstMatch(pattern, in: normalized) {
                    result.categories.insert(category)
                    result.matches.insert(match)
                }
            }
        }
        scan(SafetyPhrases.suicidalIdeation, as: .suicidalIdeation)
        scan(SafetyPhrases.selfHarm, as: .selfHarm)
        scan(SafetyPhrases.harmToOthers, as: .harmToOthers)

        let hopeless = SafetyPhrases.hopelessness.compactMap { firstMatch($0, in: normalized) }
        let intent = SafetyPhrases.intent.compactMap { firstMatch($0, in: normalized) }
        if !hopeless.isEmpty && !intent.isEmpty {
            result.categories.insert(.hopelessnessWithIntent)
            result.matches.formUnion(hopeless + intent)
        }

        if !result.categories.isEmpty { result.source = .deterministic }
        return result
    }

    /// AI classification layered on top: it can only raise the level.
    /// If the offline check found risk, that result stands whatever the AI
    /// said.
    static func escalate(_ deterministic: RiskAssessment, aiFlagged: Bool) -> RiskAssessment {
        if deterministic.isRisk || !aiFlagged { return deterministic }
        var escalated = deterministic
        escalated.source = .ai
        return escalated
    }

    /// Lowercase, straight apostrophes, anything that isn't a letter, digit
    /// or apostrophe turned into a space, runs of spaces collapsed.
    static func normalize(_ text: String) -> String {
        let lowered = text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "`", with: "'")
        var out = ""
        out.reserveCapacity(lowered.count)
        var lastWasSpace = true
        for ch in lowered {
            if ch.isLetter || ch.isNumber || ch == "'" {
                out.append(ch)
                lastWasSpace = false
            } else if !lastWasSpace {
                out.append(" ")
                lastWasSpace = true
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    private static func firstMatch(_ pattern: String, in normalized: String) -> String? {
        let bounded = "(?<![a-z0-9'])(?:\(pattern))(?![a-z0-9])"
        guard let range = normalized.range(of: bounded, options: .regularExpression) else { return nil }
        return String(normalized[range])
    }
}

/// Collects every string inside a Codable value, so a flow's whole draft
/// can be risk-checked without each step listing its fields.
enum SafetyText {
    static func strings<T: Encodable>(in value: T) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { return "" }
        var out: [String] = []
        collect(object, into: &out)
        return out.joined(separator: "\n")
    }

    private static func collect(_ object: Any, into out: inout [String]) {
        switch object {
        case let s as String: out.append(s)
        case let array as [Any]: array.forEach { collect($0, into: &out) }
        case let dict as [String: Any]: dict.values.forEach { collect($0, into: &out) }
        default: break
        }
    }
}
