import SwiftUI
import SwiftData
import Charts

/// Local pattern mining over sessions, captures, and diary cards.
struct PatternsView: View {
    @Query(filter: #Predicate<TherapySession> { $0.statusRaw == "complete" && !$0.isPractice })
    private var sessions: [TherapySession]
    @Query private var captures: [QuickCapture]
    @Query private var diaryCards: [DiaryCard]

    var body: some View {
        let data = PatternData(sessions: sessions, captures: captures, diaryCards: diaryCards)
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if data.isEmpty {
                    InsightsEmptyState(symbol: "square.grid.3x3", title: "Patterns appear as you go",
                                       message: "As you capture thoughts, finish skills, and fill in diary cards, this shows your most common triggers and emotions, when intense feelings tend to hit, and which skills and activities help you most.")
                }
                if !data.triggers.isEmpty {
                    countSection("Most frequent situations", data.triggers, note: "From quick-capture tags.")
                }
                if !data.emotions.isEmpty {
                    countSection("Most frequent emotions", data.emotions)
                }
                if !data.distortions.isEmpty {
                    countSection("Most frequent thinking traps", data.distortions)
                }
                if data.heatmap.joined().contains(where: { $0 > 0 }) {
                    heatmapSection(data.heatmap)
                }
                if !data.skillEffects.isEmpty {
                    effectSection("Which skills help you most", data.skillEffects,
                                  note: "Average before → after for each skill. For Behavioral Activation it's mood (higher is better); for the rest, intensity or grip (lower means it eased).")
                }
                if !data.activityEffects.isEmpty {
                    effectSection("Activities that lift your mood", data.activityEffects, scale: 10,
                                  note: "Mood before → after, from Behavioral Activation.")
                }
                if !data.chainFactors.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Across your chains").font(.flowSection)
                        ForEach(data.chainFactors, id: \.factor) { f in
                            Text("\(f.factor) appeared in \(f.count) of \(f.of) chain\(f.of == 1 ? "" : "s").")
                                .font(.flowBody)
                        }
                        ForEach(data.recurringLinks, id: \.0) { link in
                            Text("“\(link.0)” came up \(link.1) times.")
                                .font(.flowHelper)
                                .foregroundStyle(Ink.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Color.white)
        .navigationTitle("Patterns")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func countSection(_ title: String, _ items: [(String, Int)], note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.flowSection)
            if let note {
                Text(note).font(.flowCaption).foregroundStyle(Ink.tertiary)
            }
            Chart(items, id: \.0) { item in
                BarMark(x: .value("Count", item.1), y: .value("Item", item.0.capitalizedFirst))
                    .foregroundStyle(Color.black.opacity(0.7))
                    .annotation(position: .trailing) {
                        Text("\(item.1)").font(.system(.caption)).foregroundStyle(Ink.secondary)
                    }
            }
            .chartXAxis(.hidden)
            .frame(height: CGFloat(items.count) * 34 + 10)
            .accessibilityLabel(title)
            .accessibilityValue(items.map { "\($0.0): \($0.1)" }.joined(separator: ", "))
        }
    }

    private func heatmapSection(_ grid: [[Int]]) -> some View {
        let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let peak = max(grid.joined().max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text("When intense feelings hit").font(.flowSection)
            Text("Moments rated 70% (or 7/10) and above, by day and time.")
                .font(.flowCaption)
                .foregroundStyle(Ink.tertiary)
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                GridRow {
                    Text("")
                    ForEach(InsightsMath.dayParts, id: \.self) { part in
                        Text(part).font(.system(.caption2)).foregroundStyle(Ink.tertiary)
                    }
                }
                ForEach(0..<7, id: \.self) { d in
                    GridRow {
                        Text(days[d]).font(.system(.caption)).foregroundStyle(Ink.secondary)
                        ForEach(0..<InsightsMath.dayParts.count, id: \.self) { p in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(TherapyMethod.dbt.accent.opacity(grid[d][p] == 0 ? 0.05 : 0.2 + 0.8 * Double(grid[d][p]) / Double(peak)))
                                .frame(height: 26)
                                .overlay {
                                    if grid[d][p] > 0 {
                                        Text("\(grid[d][p])").font(.system(.caption2, weight: .semibold))
                                            .foregroundStyle(grid[d][p] * 2 > peak ? .white : Ink.primary)
                                    }
                                }
                                .accessibilityLabel("\(days[d]) \(InsightsMath.dayParts[p]): \(grid[d][p])")
                        }
                    }
                }
            }
        }
    }

    private func effectSection(_ title: String, _ effects: [InsightsMath.Effect], scale: Double = 100, note: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.flowSection)
            Text(note).font(.flowCaption).foregroundStyle(Ink.tertiary)
            ChangeBars(rows: effects.map {
                ChangeRow(label: "\($0.name) (\($0.count)×)", before: $0.before, after: $0.after,
                          scale: scale == 10 ? .outOf10 : .percent)
            }, accent: .black)
        }
    }
}

/// Everything the patterns screen and the AI digest need, computed once.
struct PatternData {
    var triggers: [(String, Int)] = []
    var emotions: [(String, Int)] = []
    var distortions: [(String, Int)] = []
    var heatmap: [[Int]] = []
    var skillEffects: [InsightsMath.Effect] = []
    var activityEffects: [InsightsMath.Effect] = []
    var chainFactors: [(factor: String, count: Int, of: Int)] = []
    var recurringLinks: [(String, Int)] = []

    var isEmpty: Bool {
        triggers.isEmpty && emotions.isEmpty && distortions.isEmpty && skillEffects.isEmpty
            && activityEffects.isEmpty && chainFactors.isEmpty && !heatmap.joined().contains(where: { $0 > 0 })
    }

    init(sessions: [TherapySession], captures: [QuickCapture], diaryCards: [DiaryCard]) {
        var emotionWords: [String] = []
        var distortionNames: [String] = []
        var intenseMoments: [Date] = []
        var chains: [ChainData] = []
        var activities: [(name: String, before: Double, after: Double)] = []

        for s in sessions {
            switch s.tool {
            case .thoughtRecord:
                if let d = s.decode(ThoughtRecordData.self) {
                    emotionWords += d.emotionsBefore.map(\.word)
                    distortionNames += d.distortions.compactMap { Distortions.named($0)?.name }
                    intenseMoments += d.emotionsBefore.filter { $0.intensity >= 70 }.map { _ in s.createdAt }
                }
            case .checkTheFacts:
                if let e = s.decode(CheckFactsData.self)?.emotion {
                    emotionWords.append(e.word)
                    if e.intensity >= 70 { intenseMoments.append(s.createdAt) }
                }
            case .oppositeAction:
                if let e = s.decode(OppositeActionData.self)?.emotion {
                    emotionWords.append(e.word)
                    if e.intensity >= 70 { intenseMoments.append(s.createdAt) }
                }
            case .crisisSkills:
                if let i = s.decode(CrisisData.self)?.intensityBefore, i >= 7 { intenseMoments.append(s.createdAt) }
            case .chainAnalysis:
                if let d = s.decode(ChainData.self) { chains.append(d) }
            case .behavioralActivation:
                if let d = s.decode(ActivationData.self), d.did == true, let b = d.moodBefore, let a = d.moodAfter {
                    activities.append((d.activity, Double(b), Double(a)))
                }
            default: break
            }
        }
        for c in captures {
            if !c.word.isEmpty { emotionWords.append(c.word) }
            if c.intensity >= 7 { intenseMoments.append(c.createdAt) }
        }
        for card in diaryCards {
            emotionWords += card.emotions.map(\.word)
            if card.emotions.contains(where: { $0.intensity >= 80 }) { intenseMoments.append(card.updatedAt) }
        }

        triggers = InsightsMath.topCounts(captures.map(\.tag))
        emotions = InsightsMath.topCounts(emotionWords)
        distortions = InsightsMath.topCounts(distortionNames)
        heatmap = InsightsMath.heatmap(intenseMoments)
        skillEffects = InsightsMath.effects(sessions.compactMap { s in
            guard let b = s.metricBefore, let a = s.metricAfter else { return nil }
            return (s.tool.title, b, a)
        }).sorted { abs($0.change) > abs($1.change) }
        activityEffects = InsightsMath.effects(activities).sorted { $0.change > $1.change }.prefix(5).map { $0 }
        chainFactors = InsightsMath.chainFactors(chains)
        recurringLinks = InsightsMath.recurringLinks(chains)
    }
}

extension PatternDigest {
    /// Counts and averages only (no journal text) for the AI summary.
    @MainActor
    static func build(sessions: [TherapySession], captures: [QuickCapture] = [], diaryCards: [DiaryCard] = []) -> PatternDigest {
        let data = PatternData(sessions: sessions, captures: captures, diaryCards: diaryCards)
        var digest = PatternDigest()
        digest.sessionCount = sessions.count
        digest.topEmotions = data.emotions.map { "\($0.0) (\($0.1))" }
        digest.topDistortions = data.distortions.map { "\($0.0) (\($0.1))" }
        digest.topTriggers = data.triggers.map { "\($0.0) (\($0.1))" }
        digest.skillAverages = data.skillEffects.map { "\($0.name): \(Int($0.before)) → \(Int($0.after)) over \($0.count)" }
        digest.chainFactors = data.chainFactors.map { "\($0.factor): \($0.count) of \($0.of) chains" }
        // Link kinds only, not the user's wording.
        digest.recurringLinks = data.recurringLinks.map { "a recurring \($0.0.split(separator: ":").first.map(String.init) ?? "link") (\($0.1)×)" }
        return digest
    }
}
