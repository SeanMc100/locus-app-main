import Foundation
import SwiftData
import UIKit

/// Builds a readable PDF and a JSON backup of a date range, for the user to
/// share themselves (e.g. with a therapist). Files go to a temporary folder
/// and leave the app only through the share sheet.
@MainActor
enum TherapyExporter {
    struct Options {
        var from: Date
        var to: Date
        var sessions = true
        var ledger = true
        var diary = true
    }

    struct Contents {
        var sessions: [TherapySession] = []
        var beliefs: [LedgerBelief] = []
        var diaryCards: [DiaryCard] = []
    }

    static func contents(_ options: Options, in context: ModelContext) -> Contents {
        let start = Calendar.current.startOfDay(for: options.from)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: options.to)) ?? options.to
        var c = Contents()
        if options.sessions {
            let complete = SessionStatus.complete.rawValue
            let d = FetchDescriptor<TherapySession>(predicate: #Predicate { $0.statusRaw == complete && !$0.isPractice },
                                                    sortBy: [SortDescriptor(\.createdAt)])
            c.sessions = ((try? context.fetch(d)) ?? []).filter { $0.createdAt >= start && $0.createdAt < end }
        }
        if options.ledger {
            c.beliefs = ((try? context.fetch(FetchDescriptor<LedgerBelief>())) ?? [])
                .filter { $0.lastSeenAt >= start && $0.createdAt < end }
        }
        if options.diary {
            let d = FetchDescriptor<DiaryCard>(sortBy: [SortDescriptor(\.day)])
            c.diaryCards = ((try? context.fetch(d)) ?? []).filter { $0.day >= start && $0.day < end }
        }
        return c
    }

    // MARK: JSON

    struct ExportFile: Codable {
        struct Session: Codable {
            var id: String
            var tool: String
            var method: String
            var createdAt: Date
            var completedAt: Date?
            var targetThought: String
            var triage: TriageAnswers?
            var metricBefore: Double?
            var metricAfter: Double?
            /// The tool's own record, as stored.
            var data: String
        }
        struct Belief: Codable {
            var text: String
            var storyName: String
            var createdAt: Date
            var occurrences: Int
            var ratings: [BeliefRatingPoint]
        }
        struct Diary: Codable {
            var day: Date
            var emotions: [EmotionRating]
            var urges: [UrgeRating]
            var skillsUsed: [String]
            var note: String
        }
        var exportedAt: Date
        var from: Date
        var to: Date
        var sessions: [Session]
        var beliefs: [Belief]
        var diaryCards: [Diary]
    }

    static func json(_ c: Contents, options: Options) throws -> URL {
        let file = ExportFile(
            exportedAt: .now, from: options.from, to: options.to,
            sessions: c.sessions.map {
                .init(id: $0.idString, tool: $0.tool.rawValue, method: $0.method.rawValue, createdAt: $0.createdAt,
                      completedAt: $0.completedAt, targetThought: $0.targetThought, triage: $0.triage,
                      metricBefore: $0.metricBefore, metricAfter: $0.metricAfter,
                      data: String(decoding: $0.payload, as: UTF8.self))
            },
            beliefs: c.beliefs.map { .init(text: $0.canonicalText, storyName: $0.storyName, createdAt: $0.createdAt,
                                           occurrences: $0.occurrences, ratings: $0.ratings) },
            diaryCards: c.diaryCards.map { .init(day: $0.day, emotions: $0.emotions, urges: $0.urges,
                                                 skillsUsed: $0.skillsUsed, note: $0.note) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let url = folder().appending(path: "Locus skills \(stamp(options)).json")
        try encoder.encode(file).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    // MARK: PDF

    static func pdf(_ c: Contents, options: Options) throws -> URL {
        let formatter = UIMarkupTextPrintFormatter(markupText: html(c, options: options))
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)   // US Letter
        renderer.setValue(page, forKey: "paperRect")
        renderer.setValue(page.insetBy(dx: 54, dy: 54), forKey: "printableRect")

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, page, [kCGPDFContextTitle as String: "Locus skills"])
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for i in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: i, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()

        let url = folder().appending(path: "Locus skills \(stamp(options)).pdf")
        try (data as Data).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func html(_ c: Contents, options: Options) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\n", with: "<br>")
        }
        let range = "\(options.from.formatted(date: .abbreviated, time: .omitted)) – \(options.to.formatted(date: .abbreviated, time: .omitted))"
        var h = """
        <html><head><style>
        body { font-family: -apple-system, Helvetica; font-size: 11pt; color: #111; }
        h1 { font-size: 20pt; margin-bottom: 2pt; } h2 { font-size: 14pt; margin-top: 18pt; border-bottom: 1px solid #ddd; }
        h3 { font-size: 12pt; margin: 12pt 0 2pt; } .muted { color: #666; font-size: 9pt; }
        .label { color: #666; font-size: 8.5pt; text-transform: uppercase; letter-spacing: 0.5pt; margin-top: 6pt; }
        .block { margin: 1pt 0 4pt; } .session { page-break-inside: avoid; margin-bottom: 10pt; }
        </style></head><body>
        <h1>Locus skills record</h1>
        <div class="muted">\(esc(range)) · exported \(Date.now.formatted(date: .abbreviated, time: .shortened))</div>
        <p class="muted">A personal self-help record. Not a clinical document.</p>
        """
        if options.sessions {
            h += "<h2>Sessions (\(c.sessions.count))</h2>"
            for s in c.sessions {
                let summary = SessionSummary(session: s)
                h += "<div class='session'><h3>\(esc(s.tool.title))</h3><div class='muted'>\((s.completedAt ?? s.createdAt).formatted(date: .abbreviated, time: .shortened))</div>"
                for change in summary.changes {
                    let unit = change.scale == 10 ? "/10" : "%"
                    h += "<div class='block'><b>\(esc(change.label)):</b> \(Int(change.before))\(unit)"
                    if let after = change.after { h += " → \(Int(after))\(unit)" }
                    h += "</div>"
                }
                if let chain = summary.chain {
                    h += "<div class='label'>Chain</div><div class='block'>Event: \(esc(chain.promptingEvent))</div>"
                    for link in chain.links {
                        let weak = chain.weakLinks.first { $0.linkID == link.id }
                        h += "<div class='block'>→ \(esc(link.kind.label)): \(esc(link.text))\(weak.map { " <i>(next time: \(esc($0.response)))</i>" } ?? "")</div>"
                    }
                    h += "<div class='block'>Behavior: \(esc(chain.problemBehavior))</div>"
                }
                for block in summary.blocks {
                    h += "<div class='label'>\(esc(block.title))</div><div class='block'>\(esc(block.text))</div>"
                }
                h += "</div>"
            }
        }
        if options.ledger {
            h += "<h2>Belief ledger (\(c.beliefs.count))</h2>"
            for b in c.beliefs {
                let ratings = b.ratings.sorted { $0.date < $1.date }.map { "\(Int($0.value))%" }.joined(separator: " → ")
                h += "<div class='session'><h3>“\(esc(b.canonicalText))”</h3><div class='muted'>\(b.occurrences) time(s)\(b.storyName.isEmpty ? "" : " · the “\(esc(b.storyName))” story")</div>"
                if !ratings.isEmpty { h += "<div class='block'>Ratings: \(ratings)</div>" }
                h += "</div>"
            }
        }
        if options.diary {
            h += "<h2>Diary cards (\(c.diaryCards.count))</h2>"
            for d in c.diaryCards {
                h += "<div class='session'><h3>\(d.day.formatted(date: .complete, time: .omitted))</h3>"
                if !d.emotions.isEmpty {
                    h += "<div class='block'>Emotions: \(esc(d.emotions.map { "\($0.word) \(Int($0.intensity / 20))/5" }.joined(separator: ", ")))</div>"
                }
                if !d.urges.isEmpty {
                    h += "<div class='block'>Urges: \(esc(d.urges.map { "\($0.name) \($0.intensity)/5\($0.acted ? " (acted)" : "")" }.joined(separator: ", ")))</div>"
                }
                if !d.skillsUsed.isEmpty { h += "<div class='block'>Skills: \(esc(d.skillsUsed.joined(separator: ", ")))</div>" }
                if !d.note.isEmpty { h += "<div class='block'>Note: \(esc(d.note))</div>" }
                h += "</div>"
            }
        }
        return h + "</body></html>"
    }

    private static func folder() -> URL {
        let dir = URL.temporaryDirectory.appending(path: "Export", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func stamp(_ o: Options) -> String {
        let f = Date.FormatStyle().year().month(.twoDigits).day(.twoDigits)
        return "\(o.from.formatted(f).replacingOccurrences(of: "/", with: "-")) to \(o.to.formatted(f).replacingOccurrences(of: "/", with: "-"))"
    }
}
