import SwiftUI

/// Print-styled one-pager for a drawn grouping: white background, black text,
/// A4 portrait — groups are a list, not a room.
struct GroupsPageView: View {
    let schoolClass: SchoolClass
    let groups: [StudentGroup]
    var date = Date()

    /// A4 portrait in PostScript points.
    static let pageSize = CGSize(width: 595, height: 842)
    private static let margin: CGFloat = 34
    private static let headerHeight: CGFloat = 40
    private static let gap: CGFloat = 12
    private static let titleSize: CGFloat = 13
    private static let memberSize: CGFloat = 11
    private static let titleLine: CGFloat = 18
    private static let memberLine: CGFloat = 15
    private static let cardPadding: CGFloat = 10

    var body: some View {
        let columns = columnCount
        let rows = chunked(groups, into: columns)
        let available = CGSize(width: Self.pageSize.width - 2 * Self.margin,
                               height: Self.pageSize.height - 2 * Self.margin - Self.headerHeight)
        let contentHeight = rows.reduce(0) { $0 + rowHeight($1) }
            + Self.gap * CGFloat(max(0, rows.count - 1))
        // Only ever shrink: a class of six should not be blown up to fill A4.
        let scale = min(1, available.height / max(1, contentHeight))

        return VStack(spacing: 0) {
            Text(L("grouping.page_header", schoolClass.name, groups.count, formattedDate))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Self.headerHeight, alignment: .top)

            VStack(spacing: Self.gap) {
                ForEach(rows.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: Self.gap) {
                        ForEach(rows[index]) { group in
                            card(group)
                        }
                        // Keeps a short last row's cards the same width as the rest.
                        ForEach(0..<(columns - rows[index].count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(width: available.width, height: contentHeight, alignment: .top)
            .scaleEffect(scale, anchor: .top)
            .frame(width: available.width, height: contentHeight * scale, alignment: .top)
        }
        .padding(Self.margin)
        .frame(width: Self.pageSize.width, height: Self.pageSize.height, alignment: .top)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    // MARK: - Cards

    private func card(_ group: StudentGroup) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(group.name)
                .font(.system(size: Self.titleSize, weight: .semibold))
                .foregroundStyle(.black)
                .frame(height: Self.titleLine, alignment: .leading)

            ForEach(members(of: group), id: \.id) { student in
                HStack(spacing: 4) {
                    if student.id == group.representativeID {
                        Image(systemName: "star.fill")
                            .font(.system(size: Self.memberSize * 0.7))
                    }
                    Text(student.firstName)
                        .font(.system(size: Self.memberSize))
                }
                .foregroundStyle(.black)
                .frame(height: Self.memberLine, alignment: .leading)
            }
        }
        .padding(Self.cardPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.black.opacity(0.35), lineWidth: 0.75)
        }
    }

    // MARK: - Layout arithmetic

    /// Cards keep a readable width: never more than three across.
    private var columnCount: Int {
        min(3, max(1, Int(Double(groups.count).squareRoot().rounded(.up))))
    }

    /// Every metric here is fixed, so the height a row will take can be worked
    /// out up front — which is what lets the page scale itself to fit.
    private func rowHeight(_ row: [StudentGroup]) -> CGFloat {
        let tallest = row.map { members(of: $0).count }.max() ?? 0
        return Self.cardPadding * 2 + Self.titleLine + 3
            + CGFloat(tallest) * (Self.memberLine + 3)
    }

    private func chunked(_ groups: [StudentGroup], into columns: Int) -> [[StudentGroup]] {
        stride(from: 0, to: groups.count, by: columns).map {
            Array(groups[$0..<min($0 + columns, groups.count)])
        }
    }

    private func members(of group: StudentGroup) -> [Student] {
        group.memberIDs.compactMap { schoolClass.student($0) }
    }

    private var formattedDate: String {
        date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
    }
}
