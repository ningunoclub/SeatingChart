import SwiftUI

/// Print-styled one-pager: white background, black text, A4 landscape.
struct ChartPageView: View {
    let schoolClass: SchoolClass
    let room: Room
    let chart: SeatingChart

    /// A4 landscape in PostScript points.
    static let pageSize = CGSize(width: 842, height: 595)
    private static let margin: CGFloat = 34
    private static let headerHeight: CGFloat = 44

    var body: some View {
        let layout = RoomLayoutView(
            room: room,
            cellSize: CGSize(width: 104, height: 76),
            spacing: 10
        ) { desk in
            ChartDeskView(desk: desk,
                          student: chart.assignment[desk.id].flatMap { schoolClass.student($0) },
                          seatNumber: room.seatNumber(of: desk.id) ?? 0,
                          style: .print,
                          height: 76)
        }
        let size = layout.contentSize
        let available = CGSize(width: Self.pageSize.width - 2 * Self.margin,
                               height: Self.pageSize.height - 2 * Self.margin - Self.headerHeight)
        let scale = min(1.2, min(available.width / size.width, available.height / size.height))

        return VStack(spacing: 0) {
            Text(header)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Self.headerHeight, alignment: .top)

            layout
                .frame(width: size.width, height: size.height)
                .scaleEffect(max(scale, 0.1), anchor: .top)
                .frame(width: available.width, height: size.height * max(scale, 0.1))
        }
        .padding(Self.margin)
        .frame(width: Self.pageSize.width, height: Self.pageSize.height, alignment: .top)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private var header: String {
        let date = chart.generatedAt.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        return "\(schoolClass.name) — \(room.name) — \(date)"
    }
}
