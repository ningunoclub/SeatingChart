import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// PDF rendering, save panel and printing — all from the same page view.
@MainActor
enum ChartExport {

    static func exportPDF(store: AppStore) {
        guard let context = Context(store: store) else { return }
        guard let data = pdfData(schoolClass: context.schoolClass, room: context.room,
                                 chart: context.chart, store: store) else {
            store.alert = AppAlert(title: L("alert.export_failed.title"),
                                   message: L("alert.export_failed.message"))
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(context.schoolClass.name) - \(context.room.name).pdf"
        panel.message = L("chart.export_prompt")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
        } catch {
            store.alert = AppAlert(title: L("alert.export_failed.title"),
                                   message: error.localizedDescription)
        }
    }

    static func printChart(store: AppStore) {
        guard let context = Context(store: store),
              let data = pdfData(schoolClass: context.schoolClass, room: context.room,
                                 chart: context.chart, store: store),
              // NSImage keeps the PDF representation, so this prints as vector art.
              let image = NSImage(data: data) else {
            store.alert = AppAlert(title: L("alert.print_failed.title"),
                                   message: L("alert.export_failed.message"))
            return
        }

        let info = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
        info.orientation = .landscape
        info.paperSize = NSSize(width: ChartPageView.pageSize.width,
                                height: ChartPageView.pageSize.height)
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        info.horizontalPagination = .fit
        info.verticalPagination = .fit

        let imageView = NSImageView(frame: NSRect(origin: .zero, size: info.paperSize))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown

        NSPrintOperation(view: imageView, printInfo: info).run()
    }

    // MARK: - Rendering

    private struct Context {
        let schoolClass: SchoolClass
        let room: Room
        let chart: SeatingChart

        init?(store: AppStore) {
            guard let schoolClass = store.currentClass,
                  let room = store.currentRoom,
                  let chart = store.currentChart else { return nil }
            self.schoolClass = schoolClass
            self.room = room
            self.chart = chart
        }
    }

    /// Renders one A4-landscape page. Internal so the render path can be tested
    /// without going through the save panel.
    static func pdfData(schoolClass: SchoolClass, room: Room, chart: SeatingChart,
                        store: AppStore) -> Data? {
        let page = ChartPageView(schoolClass: schoolClass, room: room, chart: chart)
            .environment(store)
        return PDFRenderer.data(from: page, size: ChartPageView.pageSize)
    }
}
