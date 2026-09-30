import Foundation

// Editable data: emotion families, the words inside them, and the DBT
// notes used by Check the Facts and Opposite Action.

enum EmotionFamily: String, Codable, CaseIterable, Identifiable, Sendable {
    case anger, fear, sadness, shame, disgust, joy, surprise, love

    var id: String { rawValue }

    var name: String {
        switch self {
        case .anger: "Anger"
        case .fear: "Fear / Anxiety"
        case .sadness: "Sadness"
        case .shame: "Shame / Guilt"
        case .disgust: "Disgust"
        case .joy: "Joy"
        case .surprise: "Surprise"
        case .love: "Love"
        }
    }

    /// Specific words, the plain family word first.
    var words: [String] {
        switch self {
        case .anger: ["angry", "irritated", "frustrated", "resentful", "jealous", "betrayed", "furious"]
        case .fear: ["afraid", "anxious", "nervous", "dread", "panicky", "insecure", "overwhelmed", "worried"]
        case .sadness: ["sad", "disappointed", "lonely", "hurt", "grief", "hopeless", "discouraged"]
        case .shame: ["ashamed", "guilty", "embarrassed", "humiliated", "inadequate", "regretful"]
        case .disgust: ["disgusted", "repulsed", "contempt", "revolted"]
        case .joy: ["happy", "content", "proud", "relieved", "excited", "grateful", "hopeful"]
        case .surprise: ["surprised", "shocked", "startled", "confused", "amazed"]
        case .love: ["loving", "affectionate", "tender", "connected", "caring"]
        }
    }

    /// What this emotion typically fits (DBT Check the Facts).
    var fitsWhen: String {
        switch self {
        case .anger: "Anger fits when an important goal is blocked, or you or someone you care about is attacked or treated unfairly."
        case .fear: "Fear fits when there's a real threat to your life, health, or wellbeing, or to someone you care about."
        case .sadness: "Sadness fits when you've lost something or someone, or things aren't how you wanted or hoped."
        case .shame: "Guilt fits when you've acted against your own values. Shame fits when you'd be rejected by people who matter if something about you were known."
        case .disgust: "Disgust fits when something could contaminate you, or someone's actions truly violate your values."
        case .joy: "Joy fits when something is good, pleasant, or what you wanted."
        case .surprise: "Surprise fits when something unexpected happens."
        case .love: "Love fits when a person, animal, or thing enhances your life or the lives of people you care about."
        }
    }

    /// Common opposite actions, shown as starting suggestions only.
    var oppositeActions: [String] {
        switch self {
        case .fear: ["Approach what you're avoiding, a small step at a time", "Do the thing you're afraid of, over and over", "Stay instead of leaving"]
        case .sadness: ["Get active: do something, however small", "Reach out instead of withdrawing", "Do one thing that builds a sense of competence"]
        case .anger: ["Gently step away instead of attacking", "Do something a little kind", "Try to see it from their side"]
        case .shame: ["Share it with someone safe instead of hiding", "Hold your head up and keep eye contact", "Keep doing the thing, openly"]
        case .disgust: ["Move closer instead of pulling away", "Be kind to the person", "Take it in, rather than pushing it away"]
        case .joy: ["Pause and let the feeling settle", "Pay attention to someone else"]
        case .surprise: ["Slow down and take stock"]
        case .love: ["Stop expressing it for now", "Give yourself distance", "Distract yourself from thoughts of them"]
        }
    }

    /// The same notes for guilt specifically, when a guilt word is chosen.
    static let guiltOppositeActions = ["Keep doing what set off the guilt, without apologizing", "Don't try to make up for it when there's nothing to make up for"]
    static let guiltWords: Set<String> = ["guilty", "regretful"]

    var symbol: String {
        switch self {
        case .anger: "flame"
        case .fear: "exclamationmark.triangle"
        case .sadness: "cloud.rain"
        case .shame: "eye.slash"
        case .disgust: "hand.raised.slash"
        case .joy: "sun.max"
        case .surprise: "sparkle"
        case .love: "heart"
        }
    }
}
