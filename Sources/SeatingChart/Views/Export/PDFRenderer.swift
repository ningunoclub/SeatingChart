import AppKit
import SwiftUI

/// One SwiftUI view rendered to a one-page PDF. Shared by the seating-chart and
/// the groups exports so the two render paths cannot drift apart.
@MainActor
enum PDFRenderer {
    static func data<Content: View>(from view: Content, size: CGSize) -> Data? {
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(size)

        var result: Data?
        renderer.render { renderedSize, renderInContext in
            let buffer = NSMutableData()
            var box = CGRect(origin: .zero, size: renderedSize)
            guard let consumer = CGDataConsumer(data: buffer as CFMutableData),
                  let pdf = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            renderInContext(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            result = buffer as Data
        }
        return result
    }
}
