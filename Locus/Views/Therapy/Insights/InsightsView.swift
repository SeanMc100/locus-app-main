import SwiftUI
import SwiftData
import Charts

/// Insights: everything computed on this device from the user's own
/// records. AI (if on) only adds a short summary on top.
struct InsightsView: View {
    // No @Query here on purpose: the screens this pushes query the same
    // models, and a parent and pushed child both observing a query made
    // each fetch re-render the other in a loop (hang). Counts are read on
    // appear instead.
    @Environment(\.modelContext) private var modelContext
    @State private var beliefCount = 0
    @State private var dueCards = 0
    @State private var summary: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Computed on this device from what you've recorded.")
                    .font(.flowHelper)
                    .foregroundStyle(Ink.secondary)
                    .padding(.bottom, 6)

                if !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        CapsLabel("Summary (AI, on this device)")
                        ForEach(summary, id: \.self) { line in
                            Text(line).font(.flowHelper)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(filled: true)
                }

                link("Belief Ledger", "Recurring beliefs and how strongly you hold them over time.",
                     "books.vertical", beliefCount == 0 ? nil : "\(beliefCount)") { BeliefLedgerView() }
                link("Prediction Calibration", "How often feared predictions come true, against how sure you were.",
                     "scope", nil) { CalibrationView() }
                link("Patterns", "Triggers, emotions, times of day, and which skills help you most.",
                     "square.grid.3x3", nil) { PatternsView() }
                link("Values Gap", "Where importance and action are furthest apart.",
                     "safari", nil) { ValuesGapView() }
                link("Practice", "Your reframe deck, if-then plans, and calm-time rehearsal.",
                     "rectangle.stack", dueCards > 0 ? "\(dueCards) due" : nil) { PracticeView() }
                link("Export", "A PDF or JSON copy of a date range, e.g. to bring to a therapist.",
                     "square.and.arrow.up", nil) { ExportView() }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Color.white)
        .navigationTitle("Insights")
        .onAppear(perform: loadCounts)
        .task {
            guard TherapyAI.isEnabled else { return }
            let complete = SessionStatus.complete.rawValue
            let sessions = (try? modelContext.fetch(FetchDescriptor<TherapySession>(
                predicate: #Predicate { $0.statusRaw == complete && !$0.isPractice }))) ?? []
            summary = await TherapyAI.summarize(PatternDigest.build(sessions: sessions))
        }
    }

    private func loadCounts() {
        beliefCount = (try? modelContext.fetchCount(FetchDescriptor<LedgerBelief>())) ?? 0
        let now = Date.now
        dueCards = (try? modelContext.fetchCount(FetchDescriptor<PracticeCard>(
            predicate: #Predicate { !$0.isArchived && $0.dueAt <= now }))) ?? 0
    }

    private func link<Destination: View>(_ title: String, _ detail: String, _ symbol: String, _ badge: String?,
                                          @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            NavigationCardLabel(title: title + (badge.map { " · \($0)" } ?? ""), detail: detail, symbol: symbol)
        }
        .buttonStyle(.plain)
    }
}

/// Empty states say what will appear and why it's useful.
struct InsightsEmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Ink.tertiary)
                .accessibilityHidden(true)
            Text(title).font(.flowSection)
            Text(message)
                .font(.flowHelper)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(filled: true)
    }
}

// MARK: - Belief Ledger

struct BeliefLedgerView: View {
    @Query private var beliefs: [LedgerBelief]

    private var sorted: [LedgerBelief] {
        beliefs.sorted { $0.occurrences != $1.occurrences ? $0.occurrences > $1.occurrences : $0.lastSeenAt > $1.lastSeenAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if beliefs.isEmpty {
                    InsightsEmptyState(symbol: "books.vertical", title: "No beliefs tracked yet",
                                       message: "When you work on a thought, you can add it to your ledger. Each time it comes back, it's linked here, with how strongly you believed it, the evidence you found, and the balanced thoughts you wrote, so you can watch it loosen over time.")
                }
                ForEach(sorted) { belief in
                    NavigationLink {
                        BeliefDetailView(belief: belief)
                    } label: {
                        BeliefRow(belief: belief)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Color.white)
        .navigationTitle("Belief Ledger")
    }
}

private struct BeliefRow: View {
    let belief: LedgerBelief

    var body: some View {
        let trend = InsightsMath.trend(belief.ratings)
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("“\(belief.canonicalText)”")
                    .font(.system(.body, weight: .semibold))
                    .multilineTextAlignment(.leading)
                if !belief.storyName.isEmpty {
                    Text("The “\(belief.storyName)” story")
                        .font(.flowCaption)
                        .foregroundStyle(TherapyMethod.act.accent)
                }
                Text("\(belief.occurrences) time\(belief.occurrences == 1 ? "" : "s") · last \(belief.lastSeenAt.formatted(.relative(presentation: .named)))")
                    .font(.flowCaption)
                    .foregroundStyle(Ink.tertiary)
            }
            Spacer(minLength: 0)
            TrendBadge(trend: trend)
        }
        .foregroundStyle(Ink.primary)
        .padding(16)
        .card()
        .accessibilityElement(children: .combine)
    }
}

struct TrendBadge: View {
    let trend: Trend

    var body: some View {
        let (symbol, label): (String, String) = switch trend {
        case .weaker: ("arrow.down.right", "Loosening")
        case .stronger: ("arrow.up.right", "Stronger")
        case .steady: ("arrow.right", "Steady")
        case .unknown: ("minus", "Not enough ratings")
        }
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
            Text(label)
                .font(.system(.caption2, weight: .medium))
        }
        .foregroundStyle(Ink.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Trend: \(label)")
    }
}

struct BeliefDetailView: View {
    @Bindable var belief: LedgerBelief

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var sessions: [TherapySession]
    @State private var confirmDelete = false

    private var linked: [TherapySession] {
        let ids = Set(belief.sessionIDs)
        return sessions.filter { ids.contains($0.idString) }.sorted { $0.createdAt < $1.createdAt }
    }

    private var evidenceAgainst: [(Date, String)] {
        linked.compactMap { s -> (Date, String)? in
            switch s.tool {
            case .thoughtRecord:
                guard let d = s.decode(ThoughtRecordData.self), !d.evidenceAgainst.trimmed.isEmpty else { return nil }
                return (s.createdAt, d.evidenceAgainst.trimmed)
            case .behavioralExperiment:
                guard let d = s.decode(ExperimentData.self), d.cameTrue == .no || d.cameTrue == .partly else { return nil }
                return (s.createdAt, "Experiment: \(d.outcome.trimmed)")
            default: return nil
            }
        }
    }

    private var balancedThoughts: [(Date, String)] {
        linked.compactMap { s in
            guard s.tool == .thoughtRecord, let d = s.decode(ThoughtRecordData.self), !d.balancedThought.trimmed.isEmpty else { return nil }
            return (s.createdAt, d.balancedThought.trimmed)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Belief", text: $belief.canonicalText, axis: .vertical)
                        .font(.flowTitle)
                    Text("Shown up \(belief.occurrences) time\(belief.occurrences == 1 ? "" : "s") since \(belief.createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.flowCaption)
                        .foregroundStyle(Ink.tertiary)
                    FlowLineField(placeholder: "Story name (optional)", text: $belief.storyName)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Strength over time").font(.flowSection)
                    if belief.ratings.count < 2 {
                        Text("Ratings from each session will chart here.")
                            .font(.flowHelper)
                            .foregroundStyle(Ink.secondary)
                    } else {
                        BeliefChart(ratings: belief.ratings.sorted { $0.date < $1.date })
                    }
                }

                if !evidenceAgainst.isEmpty {
                    listSection("Evidence you've found against it", evidenceAgainst)
                }
                if !balancedThoughts.isEmpty {
                    listSection("Balanced thoughts you've written", balancedThoughts)
                }

                if !linked.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sessions").font(.flowSection)
                        ForEach(linked) { s in
                            NavigationLink { SessionDetailView(session: s) } label: {
                                NavigationCardLabel(title: s.tool.title,
                                                    detail: s.createdAt.formatted(date: .abbreviated, time: .shortened),
                                                    symbol: s.tool.symbol)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Color.white)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Remove from ledger", role: .destructive) { confirmDelete = true }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .confirmationDialog("Remove this belief from your ledger?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                modelContext.delete(belief)
                try? modelContext.save()
                dismiss()
            }
        } message: {
            Text("The sessions themselves are kept.")
        }
    }

    private func listSection(_ title: String, _ items: [(Date, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.flowSection)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.0.formatted(date: .abbreviated, time: .omitted))
                        .font(.flowCaption)
                        .foregroundStyle(Ink.tertiary)
                    Text(item.1).font(.flowBody)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
        }
    }
}

// MARK: - Prediction calibration

struct CalibrationView: View {
    @Query(filter: #Predicate<TherapySession> { $0.statusRaw == "complete" && !$0.isPractice })
    private var sessions: [TherapySession]

    static func points(from sessions: [TherapySession]) -> [CalibrationPoint] {
        sessions.compactMap { s -> CalibrationPoint? in
            switch s.tool {
            case .behavioralExperiment:
                guard let d = s.decode(ExperimentData.self), let c = d.confidence, let o = d.cameTrue else { return nil }
                return CalibrationPoint(confidence: c, outcome: o.score, severityExpected: d.severityExpected, severityActual: d.severityActual)
            case .checkTheFacts:
                guard let d = s.decode(CheckFactsData.self), let c = d.threatLikelihood, let o = d.threatHappened else { return nil }
                return CalibrationPoint(confidence: c, outcome: o.score)
            default: return nil
            }
        }
    }

    var body: some View {
        let points = Self.points(from: sessions)
        let summary = InsightsMath.calibration(points)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if summary.count < InsightsMath.calibrationMinimum {
                    InsightsEmptyState(symbol: "scope", title: "\(summary.count) of \(InsightsMath.calibrationMinimum) predictions recorded",
                                       message: "Each Behavioral Experiment you finish (and each Check the Facts threat you later mark) is a prediction with a real outcome. After \(InsightsMath.calibrationMinimum), you'll see how often your feared predictions actually come true, compared with how sure you were.")
                    ProgressView(value: Double(summary.count), total: Double(InsightsMath.calibrationMinimum))
                        .tint(TherapyMethod.cbt.accent)
                        .accessibilityLabel("\(summary.count) of \(InsightsMath.calibrationMinimum)")
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your feared predictions came true \(Int(summary.cameTrueRate.rounded()))% of the time. You estimated \(Int(summary.averageEstimate.rounded()))% on average.")
                            .font(.flowQuestion)
                            .fixedSize(horizontal: false, vertical: true)
                        if let ratio = summary.severityRatio {
                            Text("When things did go wrong, you rated them \(Int(ratio.rounded()))% as bad as you expected.")
                                .font(.flowBody)
                                .foregroundStyle(Ink.primary.opacity(0.8))
                        }
                        Text("From \(summary.count) predictions (“partly” counts as half).")
                            .font(.flowCaption)
                            .foregroundStyle(Ink.tertiary)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Calibration").font(.flowSection)
                        Text("Each dot: how sure you were (across) against how often it happened (up). On the dashed line, you'd be perfectly calibrated.")
                            .font(.flowHelper)
                            .foregroundStyle(Ink.secondary)
                        Chart {
                            LineMark(x: .value("Predicted", 0), y: .value("Actual", 0), series: .value("Series", "Perfect"))
                                .foregroundStyle(Ink.tertiary)
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            LineMark(x: .value("Predicted", 100), y: .value("Actual", 100), series: .value("Series", "Perfect"))
                                .foregroundStyle(Ink.tertiary)
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            ForEach(summary.buckets) { b in
                                PointMark(x: .value("Predicted", b.predicted), y: .value("Actual", b.actual))
                                    .foregroundStyle(TherapyMethod.cbt.accent)
                                    .symbolSize(CGFloat(60 + b.count * 30))
                                    .annotation(position: .top) {
                                        Text("\(b.count)").font(.system(.caption2)).foregroundStyle(Ink.tertiary)
                                    }
                            }
                        }
                        .chartXScale(domain: 0...100)
                        .chartYScale(domain: 0...100)
                        .chartXAxisLabel("How sure you were (%)")
                        .chartYAxisLabel("How often it happened (%)")
                        .frame(height: 260)
                        .accessibilityLabel("Calibration chart")
                        .accessibilityValue(summary.buckets.map { "\($0.lower) to \($0.upper) percent sure: happened \(Int($0.actual)) percent, \($0.count) predictions" }.joined(separator: "; "))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Color.white)
        .navigationTitle("Prediction Calibration")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Values gap

struct ValuesGapView: View {
    @Query(sort: \ValueDomain.order) private var domains: [ValueDomain]
    @Query(filter: #Predicate<TherapySession> { $0.statusRaw == "complete" && $0.toolRaw == "committedAction" })
    private var actions: [TherapySession]
    @State private var flow: FlowLaunch?

    private var clarified: [ValueDomain] {
        domains.filter { $0.isClarified && !$0.isHidden }
            .sorted { gap($0) > gap($1) }
    }

    private func gap(_ d: ValueDomain) -> Int { (d.importance ?? 0) - (d.latestConsistency ?? 0) }

    private func actionsLast30(_ d: ValueDomain) -> Int {
        let since = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        return actions.filter { s in
            guard (s.completedAt ?? .distantPast) >= since, let data = s.decode(CommittedActionData.self) else { return false }
            return data.valueDomainID == d.idString && data.did == true
        }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if clarified.isEmpty {
                    InsightsEmptyState(symbol: "safari", title: "No values clarified yet",
                                       message: "In Values Check-in, rate how important each area of life is and how consistently you've been acting on it. This view then shows where the gap is widest, and the small steps you've taken toward each.")
                    SecondaryButton(title: "Start Values Check-in", symbol: "safari") {
                        flow = FlowLaunch(start: .tool(.valuesCheckIn, TherapyLaunch()))
                    }
                } else {
                    Text("Sorted by largest gap between how important it is and how much you've acted on it.")
                        .font(.flowHelper)
                        .foregroundStyle(Ink.secondary)
                    ForEach(clarified) { d in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: d.symbol).foregroundStyle(TherapyMethod.act.accent)
                                Text(d.name).font(.system(.body, weight: .semibold))
                                Spacer()
                                Text("Gap \(max(gap(d), 0))")
                                    .font(.flowCaption.weight(.bold))
                                    .foregroundStyle(Ink.secondary)
                            }
                            ChangeBars(rows: [ChangeRow(label: "Importance → acting on it", before: Double(d.importance ?? 0),
                                                        after: Double(d.latestConsistency ?? 0), scale: .outOf10)],
                                       accent: TherapyMethod.act.accent)
                            Text("\(actionsLast30(d)) committed action\(actionsLast30(d) == 1 ? "" : "s") in the last 30 days")
                                .font(.flowCaption)
                                .foregroundStyle(Ink.tertiary)
                            if gap(d) >= 3 {
                                SecondaryButton(title: "Plan a Committed Action", symbol: TherapyTool.committedAction.symbol) {
                                    flow = FlowLaunch(start: .tool(.committedAction, TherapyLaunch(valueDomainID: d.idString)))
                                }
                            }
                        }
                        .padding(16)
                        .card()
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Color.white)
        .navigationTitle("Values Gap")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $flow) { launch in
            TherapyFlowHost(start: launch.start) { flow = nil }
        }
    }
}

/// Belief (or "how hooked") ratings over time, 0–100.
private struct BeliefChart: View {
    let ratings: [BeliefRatingPoint]

    private func kind(_ p: BeliefRatingPoint) -> String { p.kind == .belief ? "Belief" : "How hooked" }

    var body: some View {
        Chart(ratings, id: \.self) { point in
            LineMark(x: .value("Date", point.date), y: .value("Rating", point.value))
                .foregroundStyle(by: .value("Kind", kind(point)))
                .interpolationMethod(.monotone)
            PointMark(x: .value("Date", point.date), y: .value("Rating", point.value))
                .foregroundStyle(by: .value("Kind", kind(point)))
        }
        .chartForegroundStyleScale(["Belief": TherapyMethod.cbt.accent, "How hooked": TherapyMethod.act.accent])
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { value in
                AxisGridLine()
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%") }
            }
        }
        .frame(height: 200)
        .accessibilityLabel("Belief strength over time")
        .accessibilityValue(ratings.map { "\(Int($0.value))%" }.joined(separator: ", "))
    }
}
