import SwiftUI

/// The "Modify" sheet behind Team names. Edits a copy and writes it back on
/// Save, so Cancel really cancels.
struct TeamNamesSheet: View {
    let model: GroupingModel
    /// How many groups the current settings would make — the list is seeded to
    /// that length, so the common case needs no adding at all.
    let plannedCount: Int
    @Environment(\.dismiss) private var dismiss

    /// Identified rows rather than array indices: a `TextField` bound through an
    /// index goes to the wrong row the moment one above it is deleted.
    private struct Row: Identifiable, Hashable {
        let id = UUID()
        var text: String
    }

    @State private var rows: [Row] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("grouping.team_names_title")).font(.headline)

            List {
                ForEach($rows) { $row in
                    TextField(L("grouping.team_name_placeholder"), text: $row.text)
                        .textFieldStyle(.plain)
                }
                .onDelete { rows.remove(atOffsets: $0) }
                .onMove { rows.move(fromOffsets: $0, toOffset: $1) }

                if rows.isEmpty {
                    Text(L("grouping.no_team_names"))
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds()
            .frame(height: 220)

            Text(L("grouping.team_names_hint"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(L("grouping.add_team_name")) {
                    rows.append(Row(text: GroupDraw.teamName(at: rows.count, from: [])))
                }
                Button(L("grouping.use_numbers")) { rows = [] }
                    .disabled(rows.isEmpty)

                Spacer()

                Button(L("common.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("grouping.save_team_names")) { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 400)
        .onAppear(perform: seed)
    }

    /// Starts from the saved names, or from the numbered defaults for however
    /// many groups are about to be made.
    private func seed() {
        guard rows.isEmpty else { return }
        if model.teamNames.isEmpty {
            rows = (0..<max(1, plannedCount)).map { Row(text: GroupDraw.teamName(at: $0, from: [])) }
        } else {
            rows = model.teamNames.map { Row(text: $0) }
        }
    }

    private func save() {
        // Blanks are dropped rather than kept as empty slots — an unnamed card
        // helps nobody, and the numbered fallback covers the gap.
        model.teamNames = rows
            .map { $0.text.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        // Groups already on screen pick up the new names without a re-roll.
        model.renameGroups()
        dismiss()
    }
}
