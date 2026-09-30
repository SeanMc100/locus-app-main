import Foundation

// Editable data: the phrases the offline risk check looks for.
//
// Each line is a regular expression matched against normalized text:
// lowercase, straight apostrophes, punctuation turned into spaces, single
// spaces. Matches are whole words (a pattern can't match inside a word).
// `don'?t` covers "don't" and "dont". Err toward catching too much: the
// safety screen is calm, and the user can always carry on.
//
// Test changes with the Mac harness (`RiskDetector` + this file), and
// make sure every phrase in `SafetyPhraseSamples` still matches.

enum SafetyPhrases {
    static let suicidalIdeation: [String] = [
        #"(kill|killing|hang|hanging|shoot|shooting|drown|drowning) my ?self"#,
        #"kms"#,
        #"(end|ending|take|taking) my (own )?life"#,
        #"suicid(e|al)"#,
        #"(want|wanted|wanting|going|gonna|ready) to die"#,
        #"wanna die"#,
        #"wish i (was|were) dead"#,
        #"wish i (had never been|was never|were never|wasn't) born"#,
        #"better off dead"#,
        #"(everyone|everybody|they|people|the world|my family|he|she)( would be| would all be|'d be|'d all be| is| are)? better off without me"#,
        #"(don'?t|do not|doesn'?t) want to (be alive|live|exist|wake up|be here anymore)"#,
        #"no (reason|point) (to|in) (live|living|be alive|being alive|keep going|going on)"#,
        #"end it all"#,
        #"not (be|being) (here|around|alive) anymore"#,
        #"unalive"#,
        #"(life|my life) (is not|isn'?t) worth (living|it)"#,
        #"not worth living"#,
        #"can'?t go on living"#,
        #"jump (off|from) (a|the) (bridge|building|roof|cliff)"#,
        #"(go to )?sleep and never wake up"#,
        #"won'?t be (around|here) (much |for much )?longer"#,
    ]

    static let selfHarm: [String] = [
        #"(cut|cutting|burn|burning|hurt|hurting|harm|harming|hit|hitting|punish|punishing) my ?self"#,
        #"self ?harm(ing)?"#,
        #"over ?dos(e|ing)"#,
        #"starve my ?self"#,
    ]

    static let harmToOthers: [String] = [
        #"(want|wanted|going|gonna|plan|planning|about|ready) to (kill|murder|stab|shoot|strangle|hurt|attack|beat up) (him|her|them|someone|somebody|people|everyone|everybody|my \w+)"#,
        #"i (could|will|'ll|am going to|'m going to) (kill|murder|stab|shoot|strangle) (him|her|them|someone|somebody|my \w+)"#,
        #"(want|wish) (him|her|them) (dead|to die)"#,
        #"make (him|her|them) (suffer|bleed)"#,
    ]

    /// Hopelessness only counts when paired with intent language
    /// (`intent`) anywhere in the same text.
    static let hopelessness: [String] = [
        #"no way out"#,
        #"hopeless"#,
        #"can'?t (go on|do this anymore|take (it|this) anymore|keep doing this)"#,
        #"nothing (will|is going to|'s going to) (ever )?(get|be) better"#,
        #"what'?s the point( of (anything|living|it all|going on))?"#,
        #"(i'?m|i am) (just )?a burden"#,
        #"give up on (life|everything)"#,
        #"no future"#,
    ]

    static let intent: [String] = [
        #"(say|saying|said) goodbye"#,
        #"goodbye"#,
        #"won'?t (be (around|here)|have to deal with me)"#,
        #"(have|got|made|making) a plan"#,
        #"tonight"#,
        #"pills"#,
        #"rope"#,
        #"gun"#,
        #"(wrote|write|writing|left) (a|my) (note|letter)"#,
        #"giv(e|ing) (away )?(my|all my) (stuff|things|belongings)"#,
        #"(the|one) last time"#,
        #"(it'?ll|it will) all be over"#,
    ]
}

/// Phrases that must always be caught. The Mac harness checks each one
/// (and the `safeSamples` must not be).
enum SafetyPhraseSamples {
    static let risky: [String] = [
        "I want to kill myself",
        "honestly I just want to die",
        "Everyone would be better off without me.",
        "I don't want to be alive anymore",
        "i dont want to wake up tomorrow",
        "I've been thinking about suicide",
        "I cut myself again last night",
        "I keep thinking about hurting myself",
        "I'm going to hurt him when I see him",
        "There's no way out and I've made a plan",
        "I feel hopeless. I already wrote a note.",
        "thinking of ending my life",
        "I won't be around much longer",
        "kms",
    ]

    static let safeSamples: [String] = [
        "This commute is killing me",
        "Mom is going to kill me when she sees the car",
        "I'm dying to see that movie",
        "I hurt her feelings and I feel awful",
        "The presentation will go badly",
        "What's the point of meetings like this",
        "I feel hopeless about my taxes",
    ]
}
