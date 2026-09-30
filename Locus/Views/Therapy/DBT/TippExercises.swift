import SwiftUI

/// One TIPP skill, full screen, with its own timer or guide.
struct TippExerciseView: View {
    let skill: TippSkill
    var accent: Color = TherapyMethod.dbt.accent
    let onDone: () -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    content
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.white)
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "Done", action: onDone)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.white.ignoresSafeArea())
            }
            .navigationTitle(skill.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onClose)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch skill {
        case .temperature:
            StepHeader(question: "Cold water on your face",
                       helper: "Splash cold water on your face, or hold a cold pack over your eyes and cheeks, for about 30 seconds while briefly holding your breath.")
            NoticeCard(text: "Why it works: cold on the face triggers the dive reflex, which slows your heart rate.", symbol: "heart.text.square")
            NoticeCard(text: "Skip this if you have a heart condition or an eating disorder, and check with a doctor if you're unsure.",
                       symbol: "exclamationmark.triangle")
            CountdownTimer(seconds: 30, accent: accent)
        case .exercise:
            StepHeader(question: "Move hard, briefly",
                       helper: "Jumping jacks, running in place, or stairs: vigorous enough that it's hard to talk. It burns off the energy the emotion built up.")
            ExerciseTimer(accent: accent)
        case .breathing:
            StepHeader(question: "Breathe out longer than you breathe in",
                       helper: "In for 4, out for 6. A longer out-breath slows your heart rate.")
            PacedBreathingGuide(accent: accent)
        case .muscles:
            StepHeader(question: "Tense, then let go",
                       helper: "Tense each muscle group as you breathe in, then release it completely as you breathe out.")
            PairedRelaxationGuide(accent: accent)
        }
    }
}

// MARK: - Timers

/// A start/stop countdown with a ring. Keeps time from its start date, so
/// it stays right however often the view redraws.
struct CountdownTimer: View {
    let seconds: Int
    var accent: Color = .black

    @State private var startedAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 16) {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let remaining = remaining(at: context.date)
                ZStack {
                    Circle().stroke(Ink.fillStrong, lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: CGFloat(remaining) / CGFloat(seconds))
                        .stroke(accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(reduceMotion ? nil : .linear(duration: 0.25), value: remaining)
                    VStack(spacing: 2) {
                        Text(format(remaining))
                            .font(.system(.largeTitle, weight: .bold))
                            .monospacedDigit()
                        Text(label(remaining))
                            .font(.flowCaption)
                            .foregroundStyle(Ink.secondary)
                    }
                }
                .frame(width: 190, height: 190)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Timer")
                .accessibilityValue("\(Int(remaining.rounded(.up))) seconds left")
            }
            .frame(maxWidth: .infinity)

            SecondaryButton(title: startedAt == nil ? "Start" : "Restart",
                            symbol: startedAt == nil ? "play.fill" : "arrow.counterclockwise") {
                startedAt = .now
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func remaining(at date: Date) -> Double {
        guard let startedAt else { return Double(seconds) }
        return max(0, Double(seconds) - date.timeIntervalSince(startedAt))
    }

    private func format(_ remaining: Double) -> String {
        let s = Int(remaining.rounded(.up))
        return s >= 60 ? String(format: "%d:%02d", s / 60, s % 60) : "\(s)"
    }

    private func label(_ remaining: Double) -> String {
        if startedAt == nil { return "seconds" }
        return remaining <= 0 ? "Done" : "seconds"
    }
}

private struct ExerciseTimer: View {
    let accent: Color
    @State private var seconds: Int? = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How long?")
                .font(.system(.body, weight: .semibold))
            OptionRow(options: [60, 90, 120], selection: $seconds) { "\($0) sec" }
            CountdownTimer(seconds: seconds ?? 60, accent: accent)
                .id(seconds)
        }
    }
}

// MARK: - Paced breathing

/// A circle that grows over a 4-second in-breath and shrinks over a
/// 6-second out-breath. With Reduce Motion, the circle stays still and only
/// the words and count change.
struct PacedBreathingGuide: View {
    var accent: Color = .black
    var inhale: Double = 4
    var exhale: Double = 6

    @State private var minutes: Int? = 1
    @State private var startedAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if startedAt == nil {
                Text("For how long?")
                    .font(.system(.body, weight: .semibold))
                OptionRow(options: [1, 2, 3], selection: $minutes) { "\($0) min" }
            }
            TimelineView(.animation(minimumInterval: reduceMotion ? 0.5 : nil, paused: startedAt == nil)) { context in
                let state = breathState(at: context.date)
                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(accent.opacity(0.12))
                            .frame(width: 240, height: 240)
                        Circle()
                            .fill(accent.opacity(0.35))
                            .frame(width: 240, height: 240)
                            .scaleEffect(reduceMotion ? 0.8 : state.scale)
                        VStack(spacing: 4) {
                            Text(state.word)
                                .font(.system(.title2, weight: .semibold))
                            if startedAt != nil && !state.finished {
                                Text("\(state.count)")
                                    .font(.system(.title3, weight: .medium))
                                    .monospacedDigit()
                                    .foregroundStyle(Ink.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(state.word)
                    if startedAt != nil {
                        Text(state.finished ? "Nicely done." : state.remainingLabel)
                            .font(.flowCaption)
                            .foregroundStyle(Ink.tertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            SecondaryButton(title: startedAt == nil ? "Start" : "Start again",
                            symbol: startedAt == nil ? "play.fill" : "arrow.counterclockwise") {
                startedAt = .now
            }
            .frame(maxWidth: .infinity)
        }
    }

    private struct BreathState {
        var word: String
        var count: Int
        var scale: CGFloat
        var finished: Bool
        var remainingLabel: String
    }

    private func breathState(at date: Date) -> BreathState {
        guard let startedAt else {
            return BreathState(word: "Ready", count: 0, scale: 0.6, finished: false, remainingLabel: "")
        }
        let total = Double((minutes ?? 1) * 60)
        let elapsed = date.timeIntervalSince(startedAt)
        if elapsed >= total {
            return BreathState(word: "Done", count: 0, scale: 0.6, finished: true, remainingLabel: "")
        }
        let cycle = inhale + exhale
        let t = elapsed.truncatingRemainder(dividingBy: cycle)
        let left = Int((total - elapsed).rounded(.up))
        let remainingLabel = "\(left / 60):\(String(format: "%02d", left % 60)) left"
        if t < inhale {
            let p = eased(t / inhale)
            return BreathState(word: "Breathe in", count: Int(inhale - t) + 1, scale: 0.6 + 0.4 * p,
                               finished: false, remainingLabel: remainingLabel)
        }
        let p = eased((t - inhale) / exhale)
        return BreathState(word: "Breathe out", count: Int(cycle - t) + 1, scale: 1.0 - 0.4 * p,
                           finished: false, remainingLabel: remainingLabel)
    }

    /// Sine ease in-out: slow at the turn of each breath.
    private func eased(_ x: Double) -> CGFloat {
        CGFloat(0.5 - 0.5 * cos(.pi * min(max(x, 0), 1)))
    }
}

// MARK: - Paired muscle relaxation

/// Walks through muscle groups: tense on the in-breath (5 s), release on
/// the out-breath (8 s).
struct PairedRelaxationGuide: View {
    var accent: Color = .black

    static let groups = ["hands and forearms", "upper arms", "shoulders", "face and jaw",
                         "stomach", "thighs", "calves and feet"]
    private let tense: Double = 5
    private let release: Double = 8

    @State private var startedAt: Date?

    var body: some View {
        VStack(spacing: 20) {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let s = state(at: context.date)
                VStack(alignment: .leading, spacing: 16) {
                    if let s {
                        Text("\(s.index + 1) of \(Self.groups.count)")
                            .font(.flowCaption.weight(.medium))
                            .foregroundStyle(Ink.tertiary)
                        Text(s.tensing ? "Breathe in and tense your \(Self.groups[s.index])" : "Breathe out and let go")
                            .font(.flowQuestion)
                            .fixedSize(horizontal: false, vertical: true)
                            .contentTransition(.opacity)
                        Text(s.tensing ? "Hold it: \(s.count)" : "Notice the difference: \(s.count)")
                            .font(.flowHelper)
                            .foregroundStyle(Ink.secondary)
                            .monospacedDigit()
                        ProgressView(value: Double(s.index) + (s.tensing ? 0 : 0.5), total: Double(Self.groups.count))
                            .tint(accent)
                    } else if startedAt != nil {
                        Text("Done. Notice how your body feels now.")
                            .font(.flowQuestion)
                    } else {
                        Text("About \(Int(Double(Self.groups.count) * (tense + release) / 60) + 1) minutes, one muscle group at a time.")
                            .font(.flowHelper)
                            .foregroundStyle(Ink.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .card(filled: true)
                .animation(.gentle, value: s?.tensing)
            }
            SecondaryButton(title: startedAt == nil ? "Start" : "Start again",
                            symbol: startedAt == nil ? "play.fill" : "arrow.counterclockwise") {
                startedAt = .now
            }
        }
    }

    private struct GroupState {
        var index: Int
        var tensing: Bool
        var count: Int
    }

    private func state(at date: Date) -> GroupState? {
        guard let startedAt else { return nil }
        let elapsed = date.timeIntervalSince(startedAt)
        let per = tense + release
        let index = Int(elapsed / per)
        guard index < Self.groups.count else { return nil }
        let t = elapsed - Double(index) * per
        if t < tense {
            return GroupState(index: index, tensing: true, count: Int(tense - t) + 1)
        }
        return GroupState(index: index, tensing: false, count: Int(per - t) + 1)
    }
}
