import Foundation

// Editable data: thinking traps offered (optionally) inside the thought
// record. An aid for noticing, never a quiz, and "None of these" is fine.

struct Distortion: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let definition: String
    let example: String
}

enum Distortions {
    static let all: [Distortion] = [
        Distortion(id: "allOrNothing", name: "All-or-nothing thinking",
                   definition: "Seeing things in black and white, with no middle ground.",
                   example: "“If it isn't perfect, it's a failure.”"),
        Distortion(id: "overgeneralization", name: "Overgeneralization",
                   definition: "Treating one event as a never-ending pattern.",
                   example: "“This always happens to me.”"),
        Distortion(id: "mentalFilter", name: "Mental filter",
                   definition: "Focusing on one negative detail and missing the rest.",
                   example: "Remembering the one critical comment, not the ten kind ones."),
        Distortion(id: "discountingPositive", name: "Discounting the positive",
                   definition: "Deciding good things don't count.",
                   example: "“They only said that to be nice.”"),
        Distortion(id: "mindReading", name: "Mind reading",
                   definition: "Assuming you know what others think.",
                   example: "“She thinks I'm boring.”"),
        Distortion(id: "fortuneTelling", name: "Fortune telling (catastrophizing)",
                   definition: "Predicting things will go badly, often as badly as possible.",
                   example: "“I'll freeze and everyone will laugh.”"),
        Distortion(id: "magnification", name: "Magnification / minimization",
                   definition: "Blowing up the bad, shrinking the good.",
                   example: "“My mistake ruined everything; my wins were luck.”"),
        Distortion(id: "emotionalReasoning", name: "Emotional reasoning",
                   definition: "Taking a feeling as proof of a fact.",
                   example: "“I feel stupid, so I must be stupid.”"),
        Distortion(id: "shoulds", name: "“Should” statements",
                   definition: "Rigid rules about how you or others must be.",
                   example: "“I should be further along by now.”"),
        Distortion(id: "labeling", name: "Labeling",
                   definition: "Summing up a whole person with one word.",
                   example: "“I'm a loser.”"),
        Distortion(id: "personalization", name: "Personalization",
                   definition: "Taking responsibility for things outside your control.",
                   example: "“They're in a bad mood because of me.”"),
        Distortion(id: "blaming", name: "Blaming",
                   definition: "Putting all the responsibility on someone else.",
                   example: "“It's entirely their fault I feel this way.”"),
    ]

    static func named(_ id: String) -> Distortion? {
        all.first { $0.id == id }
    }
}
