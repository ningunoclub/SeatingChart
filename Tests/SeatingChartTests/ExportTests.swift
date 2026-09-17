import CoreGraphics
import Foundation
import Testing
@testable import SeatingChart

@Suite("PDF export")
@MainActor
struct ExportTests {

    @Test("A generated chart renders to a one-page A4 landscape PDF")
    func rendersPDF() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SeatingChartExport-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppStore(persistence: Persistence(rootDirectory: root))

        let schoolClass = Fixture.schoolClass((1...18).map { "S\($0)" }, name: "5a")
        let room = Fixture.room(rows: 3, seatsPerRow: 6, aisleAfterSeat: 3, name: "Room 204")
        var rng = SplitMix64(seed: 11)
        let chart = try SeatingGenerator.generate(schoolClass: schoolClass, room: room,
                                                  mode: .trueRandom, rng: &rng)

        let data = try #require(ChartExport.pdfData(schoolClass: schoolClass, room: room,
                                                    chart: chart, store: store))
        #expect(data.starts(with: Array("%PDF".utf8)))
        #expect(data.count > 1_000, "a page with 18 names should not be near-empty")

        let document = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        #expect(document.numberOfPages == 1)
        let box = try #require(document.page(at: 1)).getBoxRect(.mediaBox)
        #expect(abs(box.width - ChartPageView.pageSize.width) < 1)
        #expect(abs(box.height - ChartPageView.pageSize.height) < 1)
        #expect(box.width > box.height, "A4 landscape")
    }

    @Test("A grouping renders to a one-page A4 portrait PDF")
    func rendersGroupsPDF() throws {
        let schoolClass = Fixture.mixedClass(males: 12, females: 12, name: "5a")
        var rng = SplitMix64(seed: 4)
        let result = GroupDraw.make(from: schoolClass.students, sizing: .groupCount(6),
                                    pickRepresentatives: true, using: &rng)

        let data = try #require(GroupsExport.pdfData(schoolClass: schoolClass,
                                                     groups: result.groups))
        #expect(data.starts(with: Array("%PDF".utf8)))
        #expect(data.count > 1_000, "a page with 24 names should not be near-empty")

        let document = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        #expect(document.numberOfPages == 1)
        let box = try #require(document.page(at: 1)).getBoxRect(.mediaBox)
        #expect(abs(box.width - GroupsPageView.pageSize.width) < 1)
        #expect(abs(box.height - GroupsPageView.pageSize.height) < 1)
        #expect(box.height > box.width, "A4 portrait")
    }
}
