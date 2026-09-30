import SwiftUI

/// Lets the user fix, remove, or add items before sorting.
struct ReviewItemsView: View {
    @Binding var items: [ExtractedItem]
    let onCancel: () -> Void
    let onContinue: () -> Void

    @State private var newItem = ""
    @FocusState private var addFieldFocused: Bool

    /// Includes unsubmitted text in the add field, since continuing adds it.
    private var validCount: Int {
        let pending = newItem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1
        return items.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count + pending
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Here's what came up")
                        .font(.system(size: 28, weight: .bold))
                    Text("Edit, remove, or add anything. Next, you'll decide what's in your control.")
                        .font(.system(size: 15))
                        .foregroundStyle(.black.opacity(0.5))
                }
                .padding(.vertical, 8)
                .listRowSeparator(.hidden)
            }

            Section {
                ForEach($items) { $item in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Circle()
                            .fill(.black)
                            .frame(width: 5, height: 5)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
                        TextField("Item", text: $item.text, axis: .vertical)
                            .font(.system(size: 17))
                    }
                    .padding(.vertical, 6)
                }
                .onDelete { items.remove(atOffsets: $0) }
                .onMove { items.move(fromOffsets: $0, toOffset: $1) }

                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.4))
                    TextField("Add an item", text: $newItem)
                        .font(.system(size: 17))
                        .focused($addFieldFocused)
                        .submitLabel(.done)
                        .onSubmit(addItem)
                    if !newItem.isEmpty {
                        Button("Add", action: addItem)
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.white)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: validCount == 0 ? "Add an item to continue" : "Sort \(validCount) \(validCount == 1 ? "item" : "items")",
                          disabled: validCount == 0) {
                addItem()
                items = items
                    .map { ExtractedItem(text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    .filter { !$0.text.isEmpty }
                onContinue()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.white.ignoresSafeArea())
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addItem() {
        let trimmed = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(ExtractedItem(text: trimmed))
        newItem = ""
        addFieldFocused = true
    }
}
