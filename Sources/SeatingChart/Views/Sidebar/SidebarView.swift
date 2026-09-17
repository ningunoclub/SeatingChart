import SwiftUI

struct SidebarView: View {
    @Environment(AppStore.self) private var store
    @State private var pendingDeletion: SidebarItem?

    var body: some View {
        @Bindable var store = store
        List(selection: $store.sidebarSelection) {
            Section(L("sidebar.classes")) {
                ForEach(store.classes) { schoolClass in
                    Label(displayName(schoolClass.name), systemImage: "person.3")
                        .tag(SidebarItem.schoolClass(schoolClass.id))
                        .contextMenu {
                            Button(L("transfer.export")) {
                                store.transferSheet = .export(.onlyClass(schoolClass.id))
                            }
                            Divider()
                            Button(L("common.delete"), role: .destructive) {
                                pendingDeletion = .schoolClass(schoolClass.id)
                            }
                        }
                }
                if store.classes.isEmpty {
                    Text(L("sidebar.no_classes")).foregroundStyle(.secondary).font(.callout)
                }
            }

            Section(L("sidebar.rooms")) {
                ForEach(store.rooms) { room in
                    Label(displayName(room.name), systemImage: "square.grid.3x3")
                        .tag(SidebarItem.room(room.id))
                        .contextMenu {
                            Button(L("transfer.export")) {
                                store.transferSheet = .export(.onlyRoom(room.id))
                            }
                            Divider()
                            Button(L("common.delete"), role: .destructive) {
                                pendingDeletion = .room(room.id)
                            }
                        }
                }
                if store.rooms.isEmpty {
                    Text(L("sidebar.no_rooms")).foregroundStyle(.secondary).font(.callout)
                }
            }

            Section {
                Label(L("sidebar.chart"), systemImage: "chair")
                    .tag(SidebarItem.chart)
                Label(L("sidebar.name_picker"), systemImage: "dice")
                    .tag(SidebarItem.namePicker)
                Label(L("sidebar.grouping"), systemImage: "person.2.badge.gearshape")
                    .tag(SidebarItem.grouping)
                Label(L("sidebar.timer"), systemImage: "timer")
                    .tag(SidebarItem.timer)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { toolbar }
        .confirmationDialog(
            deletionTitle,
            isPresented: Binding(get: { pendingDeletion != nil },
                                 set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button(L("common.delete"), role: .destructive) { confirmDeletion() }
            Button(L("common.cancel"), role: .cancel) { pendingDeletion = nil }
        } message: {
            Text(L("sidebar.delete_message"))
        }
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
            Menu {
                Button(L("sidebar.add_class")) { store.sidebarSelection = .schoolClass(store.addClass()) }
                Button(L("sidebar.add_room")) { store.sidebarSelection = .room(store.addRoom()) }
                Divider()
                Button(L("transfer.import")) { BundlePanels.beginImport(store: store) }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 26)
            .help(L("sidebar.add_help"))

            Button {
                pendingDeletion = store.sidebarSelection
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.borderless)
            .disabled(!canDeleteSelection)
            .help(L("sidebar.remove_help"))

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var canDeleteSelection: Bool {
        switch store.sidebarSelection {
        case .schoolClass, .room: true
        case .chart, .namePicker, .grouping, .timer, .none: false
        }
    }

    private func displayName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? L("common.untitled") : name
    }

    private var deletionTitle: String {
        switch pendingDeletion {
        case let .schoolClass(id): L("sidebar.delete_class", displayName(store.schoolClass(id)?.name ?? ""))
        case let .room(id): L("sidebar.delete_room", displayName(store.room(id)?.name ?? ""))
        case .chart, .namePicker, .grouping, .timer, .none: ""
        }
    }

    private func confirmDeletion() {
        switch pendingDeletion {
        case let .schoolClass(id): store.deleteClass(id)
        case let .room(id): store.deleteRoom(id)
        case .chart, .namePicker, .grouping, .timer, .none: break
        }
        pendingDeletion = nil
    }
}
