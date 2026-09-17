import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// PDF rendering and the save panel for a drawn grouping. Printing stays with
/// the seating chart — ⌘P belongs to the chart.
@MainActor
enum GroupsExport {

    static func exportPDF(store: AppStore) {
        guard let schoolClass = store.groupingClass, !store.grouping.groups.isEmpty else { return }
        guard let data = pdfData(schoolClass: schoolClass, groups: store.grouping.groups) else {
            store.alert = AppAlert(title: L("alert.export_failed.title"),
                                   message: L("alert.export_failed.message"))
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(schoolClass.name) - \(L("grouping.overlay_window")).pdf"
        panel.message = L("grouping.export_prompt")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
        } catch {
            store.alert = AppAlert(title: L("alert.export_failed.title"),
                                   message: error.localizedDescription)
        }
    }

    /// Internal so the render path can be tested without the save panel.
    static func pdfData(schoolClass: SchoolClass, groups: [StudentGroup]) -> Data? {
        PDFRenderer.data(from: GroupsPageView(schoolClass: schoolClass, groups: groups),
                         size: GroupsPageView.pageSize)
    }
}
