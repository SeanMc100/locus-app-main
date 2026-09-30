import SwiftUI
import SwiftData

/// Export a date range as a readable PDF and/or a JSON backup. Shows what
/// will be included first; files leave the app only via the share sheet.
struct ExportView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var from = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var to = Date.now
    @State private var includeSessions = true
    @State private var includeLedger = true
    @State private var includeDiary = true
    @State private var files: [URL] = []
    @State private var error: String?

    private var options: TherapyExporter.Options {
        TherapyExporter.Options(from: min(from, to), to: max(from, to),
                                sessions: includeSessions, ledger: includeLedger, diary: includeDiary)
    }

    var body: some View {
        let contents = TherapyExporter.contents(options, in: modelContext)
        Form {
            Section("Date range") {
                DatePicker("From", selection: $from, displayedComponents: .date)
                DatePicker("To", selection: $to, displayedComponents: .date)
            }
            Section {
                Toggle("Skills sessions", isOn: $includeSessions)
                Toggle("Belief ledger", isOn: $includeLedger)
                Toggle("Diary cards", isOn: $includeDiary)
            } header: {
                Text("Include")
            } footer: {
                Text(preview(contents))
            }
            Section {
                Button("Create PDF") { make { try TherapyExporter.pdf(contents, options: options) } }
                Button("Create JSON backup") { make { try TherapyExporter.json(contents, options: options) } }
            } footer: {
                Text("Files are created on this device. Nothing is sent anywhere unless you choose to share it. Journal entries themselves aren't included.")
            }
            if !files.isEmpty {
                Section("Ready to share") {
                    ForEach(files, id: \.self) { url in
                        ShareLink(item: url) {
                            Label(url.lastPathComponent, systemImage: url.pathExtension == "pdf" ? "doc.richtext" : "curlybraces")
                        }
                    }
                }
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func preview(_ c: TherapyExporter.Contents) -> String {
        var parts: [String] = []
        if includeSessions { parts.append("\(c.sessions.count) session\(c.sessions.count == 1 ? "" : "s")") }
        if includeLedger { parts.append("\(c.beliefs.count) belief\(c.beliefs.count == 1 ? "" : "s")") }
        if includeDiary { parts.append("\(c.diaryCards.count) diary card\(c.diaryCards.count == 1 ? "" : "s")") }
        return parts.isEmpty ? "Nothing selected." : "Will include: " + parts.joined(separator: ", ") + "."
    }

    private func make(_ build: () throws -> URL) {
        do {
            let url = try build()
            files.removeAll { $0.pathExtension == url.pathExtension }
            files.append(url)
            error = nil
        } catch {
            self.error = "Couldn't create the file: \(error.localizedDescription)"
        }
    }
}
