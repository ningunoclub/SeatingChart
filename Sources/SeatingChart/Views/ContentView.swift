import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 235, max: 320)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(windowTitle)
        .alert(
            store.alert?.title ?? "",
            isPresented: Binding(get: { store.alert != nil },
                                 set: { if !$0 { store.alert = nil } }),
            presenting: store.alert
        ) { _ in
            Button(L("common.ok"), role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
        // One sheet driven by an enum: two `isPresented` sheets on the same view
        // do not both present reliably.
        .sheet(item: $store.transferSheet) { sheet in
            switch sheet {
            case let .export(selection):
                ExportBundleSheet(initialSelection: selection).environment(store)
            case let .importSummary(pending):
                ImportBundleSheet(pending: pending).environment(store)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch store.sidebarSelection {
        case let .schoolClass(id):
            if store.schoolClass(id) != nil {
                ClassEditorView(classID: id).id(id)
            } else {
                EmptyDetailView(message: L("detail.class_gone"))
            }
        case let .room(id):
            if store.room(id) != nil {
                RoomEditorView(roomID: id).id(id)
            } else {
                EmptyDetailView(message: L("detail.room_gone"))
            }
        case .namePicker:
            NamePickerView()
        case .grouping:
            GroupingView()
        case .timer:
            TimerView()
        case .chart, .none:
            ChartView()
        }
    }

    private var windowTitle: String {
        switch store.sidebarSelection {
        case let .schoolClass(id): store.schoolClass(id)?.name ?? L("app.name")
        case let .room(id): store.room(id)?.name ?? L("app.name")
        case .namePicker: L("sidebar.name_picker")
        case .grouping: L("sidebar.grouping")
        case .timer: L("sidebar.timer")
        case .chart, .none: L("sidebar.chart")
        }
    }
}

struct EmptyDetailView: View {
    let message: String

    var body: some View {
        ContentUnavailableView(message, systemImage: "questionmark.square.dashed")
    }
}
