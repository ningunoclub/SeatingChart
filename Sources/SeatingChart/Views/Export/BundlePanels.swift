import AppKit
import SwiftUI

/// The open and save panels for data transfer. Split out for the same reason as
/// `ChartExport`'s: everything either side of the panel stays testable.
@MainActor
enum BundlePanels {
    static func chooseExportDestination(defaultName: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [SeatingChartBundle.contentType]
        panel.nameFieldStringValue = "\(defaultName).\(SeatingChartBundle.fileExtension)"
        panel.message = L("transfer.export_prompt")
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    static func chooseImportFile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [SeatingChartBundle.contentType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L("transfer.import_prompt")
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// Picks a file and validates it, then puts the summary sheet up. The one
    /// entry point shared by the menu, the sidebar and a Finder double-click.
    static func beginImport(store: AppStore) {
        guard let url = chooseImportFile(), let bundle = store.readBundle(at: url) else { return }
        store.transferSheet = .importSummary(PendingImport(url: url, bundle: bundle))
    }
}
