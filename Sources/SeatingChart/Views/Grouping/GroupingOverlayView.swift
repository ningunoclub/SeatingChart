import SwiftUI

/// What the class sees. Display only — every control lives in the app window.
/// Everything is sized off the frame, the way `NamePickerOverlayView` is, so the
/// same view serves as a 300pt overlay and as the in-app preview.
struct GroupingOverlayView: View {
    var cornerRadius: CGFloat = 16
    @Environment(AppStore.self) private var store

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.black.opacity(0.92))
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                content(in: proxy.size)
                    .padding(.horizontal, proxy.size.width * 0.045)
                    .padding(.vertical, proxy.size.height * 0.055)
            }
        }
    }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        let groups = store.grouping.groups
        if groups.isEmpty {
            Text(L("grouping.waiting"))
                .font(.system(size: max(11, size.height * 0.09), weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
        } else {
            grid(groups, in: size)
        }
    }

    // MARK: - Grid

    /// A hand-laid grid rather than `LazyVGrid`: every card gets an equal share
    /// of the panel, so the whole draw is visible without scrolling at any size.
    private func grid(_ groups: [StudentGroup], in size: CGSize) -> some View {
        let columns = columnCount(for: groups.count, in: size)
        let rows = (groups.count + columns - 1) / columns
        let gap = min(size.width, size.height) * 0.03
        let cardHeight = (size.height * 0.89 - gap * CGFloat(rows - 1)) / CGFloat(rows)
        // The tallest card decides the type size, or one crowded group would
        // spill while its neighbours sit half empty.
        let tallest = groups.map(\.memberIDs.count).max() ?? 1

        return VStack(spacing: gap) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        if index < groups.count {
                            card(groups[index], height: cardHeight, maxMembers: tallest)
                        } else {
                            // Keeps the last row's cards the same width as the
                            // rest instead of stretching them across the gap.
                            Color.clear
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func columnCount(for count: Int, in size: CGSize) -> Int {
        guard count > 1 else { return 1 }
        let aspect = Double(size.width / max(1, size.height))
        // Cards come out roughly square at any panel shape.
        let ideal = (Double(count) * aspect).squareRoot().rounded()
        return min(count, max(1, Int(ideal)))
    }

    private func card(_ group: StudentGroup, height: CGFloat, maxMembers: Int) -> some View {
        // Title then names, sized so the busiest group's rows still fit.
        let nameSize = max(7, min(height * 0.2, height / Double(maxMembers + 2) * 1.25))
        let memberSize = max(6, min(height * 0.15, height / Double(maxMembers + 2)))

        return VStack(alignment: .leading, spacing: memberSize * 0.24) {
            Text(group.name)
                .font(.system(size: nameSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.4)

            ForEach(members(of: group), id: \.id) { student in
                HStack(spacing: memberSize * 0.3) {
                    if student.id == group.representativeID {
                        Image(systemName: "star.fill")
                            .font(.system(size: memberSize * 0.72))
                            .foregroundStyle(.yellow)
                    }
                    Text(student.firstName)
                        .font(.system(size: memberSize, design: .rounded))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, nameSize * 0.5)
        .padding(.vertical, nameSize * 0.4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: nameSize * 0.5))
    }

    /// Members that still exist — a student deleted mid-lesson simply drops out
    /// rather than leaving a blank line on the beamer.
    private func members(of group: StudentGroup) -> [Student] {
        guard let schoolClass = store.groupingClass else { return [] }
        return group.memberIDs.compactMap { schoolClass.student($0) }
    }
}
