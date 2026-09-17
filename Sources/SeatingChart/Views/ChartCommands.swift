import SwiftUI

/// Menu-bar entries for the chart actions, so the shortcuts work wherever the
/// focus happens to be.
struct ChartCommands: Commands {
    let store: AppStore
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L("sidebar.add_class")) {
                store.sidebarSelection = .schoolClass(store.addClass())
            }
            .keyboardShortcut("n", modifiers: .command)

            Button(L("sidebar.add_room")) {
                store.sidebarSelection = .room(store.addRoom())
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        // `.importExport` is the File-menu slot macOS reserves for this, and it
        // is empty by default, so `replacing:` simply fills it.
        CommandGroup(replacing: .importExport) {
            Button(L("transfer.export")) {
                store.transferSheet = .export(.everything(in: store.document))
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(store.classes.isEmpty && store.rooms.isEmpty)

            Button(L("transfer.import")) { BundlePanels.beginImport(store: store) }
                .keyboardShortcut("i", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .printItem) {
            Button(L("chart.export_pdf")) { ChartExport.exportPDF(store: store) }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(store.currentChart == nil)

            Button(L("chart.print")) { ChartExport.printChart(store: store) }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(store.currentChart == nil)
        }

        CommandMenu(L("menu.chart")) {
            Button(L("chart.generate")) {
                store.sidebarSelection = .chart
                store.generate()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!store.canGenerate)

            Divider()

            Button(L("chart.present")) { openWindow(id: PresentationScene.windowID) }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(store.currentChart == nil)
        }

        CommandMenu(L("menu.picker")) {
            Button(L("picker.pick")) {
                store.sidebarSelection = .namePicker
                store.pickName()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(!store.canPickName)

            // Deliberately not "Show…"/"Hide…": a menu title in a `Commands`
            // body does not reliably re-render when the panel is toggled.
            Button(L("picker.toggle_overlay")) {
                NamePickerOverlayController.shared.toggle(store: store)
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
        }

        CommandMenu(L("menu.grouping")) {
            Button(L("grouping.make")) {
                store.sidebarSelection = .grouping
                store.makeGroups()
            }
            .keyboardShortcut("g", modifiers: [.command, .option])
            .disabled(!store.canMakeGroups)

            Button(L("grouping.export_pdf")) { GroupsExport.exportPDF(store: store) }
                .disabled(store.grouping.groups.isEmpty)

            Divider()

            // Static title for the same reason as the picker's toggle above: a
            // menu title in a `Commands` body does not reliably re-render.
            Button(L("grouping.toggle_overlay")) {
                GroupingOverlayController.shared.toggle(store: store)
            }
            .keyboardShortcut("u", modifiers: [.command, .option])
        }

        CommandMenu(L("menu.timer")) {
            // Static titles for the same reason as the picker's toggle above: a
            // menu title in a `Commands` body does not reliably re-render.
            Button(L("timer.start_pause")) {
                store.sidebarSelection = .timer
                store.timer.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])

            Button(L("timer.reset")) { store.timer.reset() }
                .disabled(store.timer.phase == .idle)

            Divider()

            Button(L("timer.toggle_overlay")) {
                TimerOverlayController.shared.toggle(store: store)
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
        }
    }
}
