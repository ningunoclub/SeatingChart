import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ClassEditorView: View {
    let classID: UUID
    @Environment(AppStore.self) private var store
    @State private var newNames = ""

    var body: some View {
        let schoolClass = store.binding(forClass: classID)

        VStack(alignment: .leading, spacing: 0) {
            header(schoolClass)
            Divider()
            List {
                Section {
                    ForEach(schoolClass.students) { student in
                        StudentRowView(student: student,
                                       schoolClass: schoolClass,
                                       classID: classID,
                                       rowChoices: rowChoices)
                    }
                    if schoolClass.wrappedValue.students.isEmpty {
                        Text(L("class.no_students"))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(L("class.students_count", schoolClass.wrappedValue.students.count))
                }

                Section {
                    ConstraintsSectionView(schoolClass: schoolClass)
                } header: {
                    Text(L("class.rules"))
                }
            }
            .listStyle(.inset)
            .alternatingRowBackgrounds()
        }
    }

    // MARK: - Header

    private func header(_ schoolClass: Binding<SchoolClass>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(L("class.name_placeholder"), text: schoolClass.name)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .semibold))

            HStack(alignment: .top, spacing: 8) {
                TextField(L("class.add_placeholder"), text: $newNames, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addNames)
                    .frame(maxWidth: 360)

                Button(L("class.add_button"), action: addNames)
                    .disabled(newNames.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(L("class.paste_button"), action: pasteNames)
                    .help(L("class.paste_help"))

                Spacer()
            }
        }
        .padding(20)
    }

    // MARK: - Actions

    private func addNames() {
        store.addStudents(names: newNames, to: classID)
        newNames = ""
    }

    private func pasteNames() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        store.addStudents(names: text, to: classID)
    }

    /// Row pins are portable across rooms, so offer every row any room has.
    private var rowChoices: Int {
        max(store.rooms.map(\.rowCount).max() ?? 0, 10)
    }
}

struct StudentRowView: View {
    @Binding var student: Student
    @Binding var schoolClass: SchoolClass
    let classID: UUID
    let rowChoices: Int
    @Environment(AppStore.self) private var store

    private var pinnedRow: Int? { schoolClass.rowPin(for: student.id) }

    var body: some View {
        HStack(spacing: 10) {
            AvatarView(student: student, size: 30)

            TextField(L("class.student_name_placeholder"), text: $student.firstName)
                .textFieldStyle(.plain)

            GenderMenu(gender: $student.gender)

            if let pinnedRow {
                Text(L("room.row_number", pinnedRow))
                    .font(.caption)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.accentColor)
                    .help(L("class.pinned_row_help"))
            }

            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 26)
        }
        .padding(.vertical, 3)
        .contextMenu { menuItems }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button(L("class.set_photo")) { pickPhoto() }
        if student.photoFileName != nil {
            Button(L("class.remove_photo")) { store.removePhoto(for: student.id, in: classID) }
        }
        Divider()
        Menu(L("class.gender")) {
            GenderMenuItems(gender: $student.gender)
        }
        Menu(L("class.pin_to_row")) {
            ForEach(1...rowChoices, id: \.self) { row in
                Button(L("room.row_number", row)) { schoolClass.setRowPin(row, for: student.id) }
            }
        }
        if pinnedRow != nil {
            Button(L("class.remove_row_pin")) { schoolClass.setRowPin(nil, for: student.id) }
        }
        Divider()
        Button(L("class.delete_student"), role: .destructive) {
            store.deleteStudent(student.id, from: classID)
        }
    }

    private func pickPhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L("class.photo_prompt", student.firstName)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.setPhoto(from: url, for: student.id, in: classID)
    }
}
