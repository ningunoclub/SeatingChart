import SwiftUI

/// Picks what goes into a single `.seatingchart` file. Everything is ticked to
/// start with, so the common case — a full backup — is one Return away.
struct ExportBundleSheet: View {
    let initialSelection: BundleSelection

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var classIDs: Set<UUID> = []
    @State private var roomIDs: Set<UUID> = []
    @State private var includePhotos = true
    @State private var includeCharts = true
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("transfer.export_title")).font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section(title: L("transfer.classes"),
                            isEmpty: store.classes.isEmpty,
                            emptyMessage: L("sidebar.no_classes"),
                            allIDs: store.classes.map(\.id),
                            selection: $classIDs) {
                        ForEach(store.classes) { schoolClass in
                            row(id: schoolClass.id,
                                name: schoolClass.name,
                                detail: L("transfer.class_row", schoolClass.students.count),
                                selection: $classIDs)
                        }
                    }

                    section(title: L("transfer.rooms"),
                            isEmpty: store.rooms.isEmpty,
                            emptyMessage: L("sidebar.no_rooms"),
                            allIDs: store.rooms.map(\.id),
                            selection: $roomIDs) {
                        ForEach(store.rooms) { room in
                            row(id: room.id,
                                name: room.name,
                                detail: L("transfer.room_row", room.desks.count),
                                selection: $roomIDs)
                        }
                    }
                }
                .padding(.trailing, 4)
            }
            .frame(maxHeight: 260)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Toggle(L("transfer.include_photos"), isOn: $includePhotos)
                Text(L("transfer.include_photos_help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle(L("transfer.include_charts"), isOn: $includeCharts)
                    .padding(.top, 4)
            }

            HStack {
                if selection.isEmpty {
                    Text(L("transfer.nothing_selected"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("common.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("transfer.export_button")) { export() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 440)
        .onAppear {
            // Once only: re-running this on every redraw would undo the ticking.
            guard !didLoad else { return }
            didLoad = true
            classIDs = initialSelection.classIDs
            roomIDs = initialSelection.roomIDs
            includePhotos = initialSelection.includePhotos
            includeCharts = initialSelection.includeCharts
        }
    }

    private var selection: BundleSelection {
        BundleSelection(classIDs: classIDs, roomIDs: roomIDs,
                        includePhotos: includePhotos, includeCharts: includeCharts)
    }

    @ViewBuilder
    private func section<Content: View>(title: String,
                                        isEmpty: Bool,
                                        emptyMessage: String,
                                        allIDs: [UUID],
                                        selection: Binding<Set<UUID>>,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline).fontWeight(.semibold)
                Spacer()
                if !isEmpty {
                    Button(L("transfer.select_all")) { selection.wrappedValue = Set(allIDs) }
                        .buttonStyle(.link)
                        .disabled(selection.wrappedValue.count == allIDs.count)
                    Button(L("transfer.select_none")) { selection.wrappedValue = [] }
                        .buttonStyle(.link)
                        .disabled(selection.wrappedValue.isEmpty)
                }
            }
            if isEmpty {
                Text(emptyMessage).font(.callout).foregroundStyle(.secondary)
            } else {
                content()
            }
        }
    }

    private func row(id: UUID, name: String, detail: String,
                     selection: Binding<Set<UUID>>) -> some View {
        Toggle(isOn: Binding(
            get: { selection.wrappedValue.contains(id) },
            set: { isOn in
                if isOn { selection.wrappedValue.insert(id) } else { selection.wrappedValue.remove(id) }
            }
        )) {
            HStack {
                Text(displayName(name))
                Text(detail).foregroundStyle(.secondary)
            }
        }
    }

    private func displayName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? L("common.untitled") : name
    }

    private func export() {
        let chosen = selection
        let name = defaultFileName
        guard !chosen.isEmpty else { return }
        dismiss()
        // The save panel goes up only once the sheet is gone: a modal panel
        // stacked on top of a sheet can end up behind it.
        Task { @MainActor in
            guard let url = BundlePanels.chooseExportDestination(defaultName: name) else { return }
            store.exportBundle(selection: chosen, to: url)
        }
    }

    /// A single item exports under its own name; anything wider is just "Seating Chart".
    private var defaultFileName: String {
        if classIDs.count == 1, roomIDs.isEmpty, let only = store.schoolClass(classIDs.first) {
            return displayName(only.name)
        }
        if roomIDs.count == 1, classIDs.isEmpty, let only = store.room(roomIDs.first) {
            return displayName(only.name)
        }
        return L("transfer.default_filename")
    }
}
