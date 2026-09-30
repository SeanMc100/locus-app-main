import SwiftUI

/// The interactive screen for one defusion technique.
struct DefusionTechniqueView: View {
    let technique: DefusionTechnique
    let thought: String
    @Binding var data: DefusionData
    var accent: Color = TherapyMethod.act.accent

    var body: some View {
        switch technique {
        case .havingTheThought:
            HavingTheThoughtView(thought: thought, accent: accent)
        case .nameTheStory:
            NameTheStoryView(storyName: $data.storyName, thought: thought, accent: accent)
        case .leaves:
            LeavesOnAStreamView(leaves: $data.leaves, accent: accent)
        case .thankYourMind:
            ThankYourMindView(accent: accent)
        case .sillyVoice:
            SillyVoiceView(thought: thought, accent: accent)
        }
    }
}

// MARK: - "I'm having the thought that…"

private struct HavingTheThoughtView: View {
    let thought: String
    let accent: Color

    @State private var stage = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var framed: String {
        let t = thought.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ".!"))
        let lowered = t.first.map { String($0).lowercased() + t.dropFirst() } ?? t
        switch stage {
        case 0: return t
        case 1: return "I'm having the thought that \(lowered)."
        default: return "I notice I'm having the thought that \(lowered)."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(question: "Say it to yourself, one frame at a time.",
                       helper: "Each frame puts a little distance between you and the thought. It's still there, just less in charge.")
            Text(framed)
                .font(.system(.title2, weight: .semibold))
                .foregroundStyle(stage == 0 ? Ink.primary : accent)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
                .padding(18)
                .card(filled: true)
                .id(stage)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
            if stage < 2 {
                SecondaryButton(title: stage == 0 ? "Add “I'm having the thought that…”" : "Add “I notice…”",
                                symbol: "plus") {
                    withAnimation(.easeInOut(duration: 0.5)) { stage += 1 }
                }
            } else {
                Text("Read it slowly once more. Notice the difference between having a thought and being in it.")
                    .font(.flowHelper)
                    .foregroundStyle(Ink.secondary)
            }
        }
    }
}

// MARK: - Name the story

private struct NameTheStoryView: View {
    @Binding var storyName: String
    let thought: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(question: "If this thought were part of a story your mind tells, what would the story be called?",
                       helper: "Like “the not-good-enough story”. Next time it shows up, you can just recognize it: “Ah, that story again.”")
            FlowLineField(placeholder: "The … story", text: $storyName)
            if !storyName.trimmed.isEmpty {
                Text("“There's the \(storyName.trimmed.replacingOccurrences(of: "the ", with: "", options: [.anchored, .caseInsensitive])) story again.”")
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(accent)
                    .transition(.opacity)
            }
        }
        .animation(.gentle, value: storyName.isEmpty)
    }
}

// MARK: - Leaves on a stream

/// Type a thought, it lands on a leaf, and the leaf drifts away downstream.
/// With Reduce Motion, leaves fade out in place instead.
private struct LeavesOnAStreamView: View {
    @Binding var leaves: [String]
    let accent: Color

    @State private var minutes: Int? = 1
    @State private var startedAt: Date?
    @State private var text = ""
    @State private var floating: [FloatingLeaf] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct FloatingLeaf: Identifiable {
        let id = UUID()
        let text: String
        let lane: CGFloat
        let born: Date
    }

    private let driftSeconds: Double = 9

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(question: "Place each thought on a leaf, and let it float away.",
                       helper: "You don't need to push it or hold it. Just notice it, place it, and watch it go.")
            if startedAt == nil {
                Text("For how long?")
                    .font(.system(.body, weight: .semibold))
                OptionRow(options: [1, 2, 3], selection: $minutes) { "\($0) min" }
            }
            TimelineView(.animation(minimumInterval: reduceMotion ? 0.25 : nil, paused: floating.isEmpty && startedAt == nil)) { context in
                stream(at: context.date)
            }
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Stream")
            .accessibilityValue(floating.isEmpty ? "Empty" : "\(floating.count) leaves floating")

            HStack(spacing: 8) {
                FlowLineField(placeholder: "A thought…", text: $text)
                SecondaryButton(title: "Place", symbol: "leaf") { place() }
                    .disabled(text.trimmed.isEmpty)
                    .opacity(text.trimmed.isEmpty ? 0.4 : 1)
            }
            if let startedAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = max(0, Double((minutes ?? 1) * 60) - context.date.timeIntervalSince(startedAt))
                    Text(left > 0 ? "\(Int(left) / 60):\(String(format: "%02d", Int(left) % 60)) left" : "Time's up. Let the last leaves drift off.")
                        .font(.flowCaption)
                        .foregroundStyle(Ink.tertiary)
                }
            } else {
                SecondaryButton(title: "Start", symbol: "play.fill") { startedAt = .now }
            }
        }
    }

    private func stream(at date: Date) -> some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [accent.opacity(0.06), Color(red: 0.86, green: 0.91, blue: 0.93).opacity(0.7)],
                               startPoint: .top, endPoint: .bottom)
                // Gentle ripples.
                ForEach(0..<5, id: \.self) { i in
                    let phase = reduceMotion ? 0 : date.timeIntervalSinceReferenceDate / 3
                    Capsule()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 60, height: 2)
                        .position(x: (CGFloat(i) * 83 + CGFloat(phase * 20)).truncatingRemainder(dividingBy: geo.size.width + 60) - 30,
                                  y: geo.size.height * (0.15 + CGFloat(i) * 0.18))
                }
                ForEach(floating) { leaf in
                    let age = date.timeIntervalSince(leaf.born)
                    let p = min(max(age / driftSeconds, 0), 1)
                    LeafView(text: leaf.text, accent: accent)
                        .position(x: reduceMotion ? geo.size.width / 2 : -70 + (geo.size.width + 140) * CGFloat(p),
                                  y: geo.size.height * leaf.lane + (reduceMotion ? 0 : CGFloat(sin(age * 1.3)) * 8))
                        .rotationEffect(.degrees(reduceMotion ? 0 : sin(age) * 6))
                        .opacity(reduceMotion ? 1 - p : (p > 0.85 ? (1 - p) / 0.15 : 1))
                }
            }
        }
        .onChange(of: Int(date.timeIntervalSinceReferenceDate)) {
            floating.removeAll { date.timeIntervalSince($0.born) > driftSeconds }
        }
    }

    private func place() {
        let t = text.trimmed
        guard !t.isEmpty else { return }
        if startedAt == nil { startedAt = .now }
        leaves.append(t)
        floating.append(FloatingLeaf(text: t, lane: [0.3, 0.5, 0.7].randomElement() ?? 0.5, born: .now))
        text = ""
    }
}

private struct LeafView: View {
    let text: String
    let accent: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "leaf.fill")
                .foregroundStyle(accent.opacity(0.8))
            Text(text)
                .font(.flowCaption.weight(.medium))
                .lineLimit(2)
                .foregroundStyle(Ink.primary.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: 170)
        .background(Capsule().fill(Color.white.opacity(0.92)))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}

// MARK: - Thank your mind

private struct ThankYourMindView: View {
    let accent: Color
    @State private var thanked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(question: "Thank your mind.",
                       helper: "Minds throw up thoughts like this to protect us. You can appreciate the effort without doing what the thought says.")
            Button {
                withAnimation(.gentle) { thanked = true }
            } label: {
                VStack(spacing: 12) {
                    Image(systemName: thanked ? "checkmark.circle.fill" : "hands.clap")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(accent)
                    Text("“Thanks, mind, for trying to protect me.”")
                        .font(.system(.title3, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Ink.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .card(filled: true, selected: thanked)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(thanked ? "Thanked your mind" : "Thank your mind")
            if thanked {
                Text("Noticed. The thought can stay; you don't have to argue with it.")
                    .font(.flowHelper)
                    .foregroundStyle(Ink.secondary)
                    .transition(.opacity)
            }
        }
        .sensoryFeedback(.success, trigger: thanked)
    }
}

// MARK: - Silly voice

/// The thought in a playful style, repeated quickly until the words start
/// to lose their grip. Short and light.
private struct SillyVoiceView: View {
    let thought: String
    let accent: Color

    @State private var repetitions = 0
    @State private var running = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let styles: [(Font.Design, CGFloat, Bool)] = [
        (.rounded, 30, false), (.serif, 24, true), (.monospaced, 20, false),
        (.rounded, 34, true), (.default, 22, false), (.serif, 28, false),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(question: "Hear it in a silly voice.",
                       helper: "Read it in a cartoon voice, or sing it to “Happy Birthday”. Or tap below and let it repeat fast until the words blur.")
            let style = styles[repetitions % styles.count]
            Text(thought.trimmed)
                .font(.system(size: style.1, weight: .bold, design: style.0))
                .italic(style.2)
                .foregroundStyle(repetitions.isMultiple(of: 2) ? accent : Ink.primary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 150)
                .padding(18)
                .card(filled: true)
                .rotationEffect(.degrees(reduceMotion ? 0 : Double((repetitions % 3) - 1) * 3))
                .animation(reduceMotion ? nil : .spring(duration: 0.25), value: repetitions)
                .accessibilityLabel(thought)
            SecondaryButton(title: running ? "Repeating…" : "Repeat it quickly", symbol: "repeat") {
                guard !running else { return }
                running = true
                Task {
                    for _ in 0..<14 {
                        try? await Task.sleep(for: .milliseconds(reduceMotion ? 400 : 220))
                        repetitions += 1
                    }
                    running = false
                }
            }
            if repetitions >= 14 {
                Text("Just words. Sounds, really.")
                    .font(.flowHelper)
                    .foregroundStyle(Ink.secondary)
            }
        }
    }
}
