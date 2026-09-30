import Foundation

// Editable data: lists offered as starting points across the skills
// flows. The user can always write their own instead.

struct LifeDomain: Identifiable, Hashable, Sendable {
    let key: String
    let name: String
    let symbol: String
    var id: String { key }
}

enum TherapyCatalog {
    /// Every skill in the app, for chain-analysis weak links, the diary
    /// card, and if-then plans.
    static let skills: [String] = [
        "TIPP: Temperature", "TIPP: Intense exercise", "TIPP: Paced breathing",
        "TIPP: Paired muscle relaxation", "STOP", "Check the Facts", "Opposite Action",
        "Problem solving", "Thought Record", "Behavioral Experiment", "Behavioral Activation",
        "Defusion", "Leaves on a stream", "Values check-in", "Committed Action",
        "Chain Analysis", "Reach out to someone",
    ]

    /// Diary-card name for each tool (so completed sessions pre-tick it).
    static func skillName(for tool: TherapyTool) -> String {
        switch tool {
        case .crisisSkills: "STOP"
        case .valuesCheckIn: "Values check-in"
        default: tool.title
        }
    }

    static let masteryActivities: [String] = [
        "Tidy one surface for 10 minutes",
        "Wash the dishes",
        "Reply to one message you've been putting off",
        "A 15-minute workout",
        "Do 20 minutes of one work task",
        "Make your bed",
        "Cook something simple",
    ]

    static let pleasureActivities: [String] = [
        "Walk for 10 minutes",
        "Listen to three songs you love",
        "Message a friend",
        "Have a favorite snack, slowly",
        "Sit outside for 5 minutes",
        "Call someone you like talking to",
        "Read a few pages of something you enjoy",
    ]

    static let lifeDomains: [LifeDomain] = [
        LifeDomain(key: "romantic", name: "Relationships", symbol: "heart"),
        LifeDomain(key: "family", name: "Family", symbol: "house"),
        LifeDomain(key: "friends", name: "Friends & social", symbol: "person.2"),
        LifeDomain(key: "work", name: "Work & career", symbol: "briefcase"),
        LifeDomain(key: "learning", name: "Learning & growth", symbol: "book"),
        LifeDomain(key: "health", name: "Health & body", symbol: "figure.walk"),
        LifeDomain(key: "fun", name: "Recreation & fun", symbol: "sparkles"),
        LifeDomain(key: "community", name: "Community & contribution", symbol: "hands.sparkles"),
        LifeDomain(key: "meaning", name: "Spirituality & meaning", symbol: "leaf"),
    ]

    static let valueWords: [String] = [
        "accepting", "adventurous", "authentic", "calm", "caring", "compassionate",
        "courageous", "creative", "curious", "dependable", "disciplined", "encouraging",
        "fair", "forgiving", "generous", "grateful", "honest", "humble", "independent",
        "kind", "loving", "loyal", "open", "patient", "persistent", "playful", "present",
        "respectful", "responsible", "supportive", "trusting", "warm",
    ]

    static let vulnerabilities: [String] = [
        "Poor sleep", "Hunger", "Illness or pain", "Stress",
        "Alcohol or substances", "Conflict earlier", "Loneliness",
    ]

    static let captureTags: [String] = [
        "Work", "Home", "Partner", "Family", "Friends", "Health", "Money", "Online", "Commute",
    ]

    static let suggestedUrges: [String] = [
        "Avoid", "Snap at someone", "Doomscroll", "Isolate", "Overeat", "Drink",
    ]

    /// Where to find a therapist (linked from the onboarding note and
    /// settings). SAMHSA's treatment locator (US).
    static let findTherapistURL = URL(string: "https://findtreatment.gov")!
}
