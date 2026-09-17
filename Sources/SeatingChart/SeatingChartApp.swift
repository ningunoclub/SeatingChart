import AppKit
import SwiftUI

@main
struct SeatingChartApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = AppStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 1000, minHeight: 700)
        }
        .commands { ChartCommands(store: store) }

        Window(L("chart.present_window"), id: PresentationScene.windowID) {
            PresentationView()
                .environment(store)
        }
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)
    }
}

/// SwiftPM executables launch as accessory apps; promote to a regular app so the
/// window and menu bar appear when run with `swift run`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Opening a `.seatingchart` from Finder. Handled here rather than with
    /// `.onOpenURL`, because on a cold launch AppKit delivers the URL before
    /// SwiftUI has built `ContentView` and a view modifier would miss it. The
    /// request lands in store state, so the sheet presents on the first render
    /// either way.
    func application(_ application: NSApplication, open urls: [URL]) {
        let store = AppStore.shared
        // Re-targeting a live `.sheet(item:)` at a different item is unreliable.
        guard store.transferSheet == nil else { return }
        guard let url = urls.first(where: {
            $0.pathExtension.lowercased() == SeatingChartBundle.fileExtension
        }), let bundle = store.readBundle(at: url) else { return }
        store.transferSheet = .importSummary(PendingImport(url: url, bundle: bundle))
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppStore.shared.saveNow()
        // Writes the overlays' frames out so they reopen where they were left.
        NamePickerOverlayController.shared.close()
        GroupingOverlayController.shared.close()
        TimerOverlayController.shared.close()
    }
}
