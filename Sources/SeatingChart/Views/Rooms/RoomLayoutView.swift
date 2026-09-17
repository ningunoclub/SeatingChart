import SwiftUI

/// Read-only rendering of a room: blackboard on top, row labels down the left,
/// and caller-supplied content for each desk. Shared by the chart view, the
/// presentation window and the PDF renderer.
struct RoomLayoutView<DeskContent: View>: View {
    let room: Room
    var cellSize = CGSize(width: 96, height: 72)
    var spacing: CGFloat = 10
    var showsRowLabels = true
    var onDark = false
    @ViewBuilder var deskContent: (Desk) -> DeskContent

    private var pitchX: CGFloat { cellSize.width + spacing }
    private var pitchY: CGFloat { cellSize.height + spacing }
    private var gridWidth: CGFloat {
        max(cellSize.width, CGFloat(room.gridWidth) * pitchX - spacing)
    }
    private var gridHeight: CGFloat {
        max(cellSize.height, CGFloat(room.gridHeight) * pitchY - spacing)
    }
    private var gutterWidth: CGFloat { showsRowLabels ? 56 : 0 }

    /// Total size the layout wants, so callers can scale it to fit.
    var contentSize: CGSize {
        CGSize(width: gutterWidth + gridWidth, height: 26 + 18 + gridHeight)
    }

    var body: some View {
        VStack(spacing: 18) {
            BlackboardView(width: gridWidth, onDark: onDark)
                .padding(.leading, gutterWidth)

            HStack(alignment: .top, spacing: 0) {
                if showsRowLabels {
                    rowLabels.frame(width: gutterWidth, height: gridHeight, alignment: .topLeading)
                }
                desks.frame(width: gridWidth, height: gridHeight, alignment: .topLeading)
            }
        }
    }

    private var desks: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(room.orderedDesks) { desk in
                deskContent(desk)
                    .frame(width: cellSize.width, height: cellSize.height)
                    .offset(x: CGFloat(desk.gridX) * pitchX, y: CGFloat(desk.gridY) * pitchY)
            }
        }
    }

    private var rowLabels: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(room.rowByGridY.sorted(by: { $0.key < $1.key }), id: \.key) { gridY, row in
                Text(L("room.row_number", row))
                    .font(.caption)
                    .foregroundStyle(onDark ? Color.white.opacity(0.5) : Color.secondary)
                    .frame(width: gutterWidth - 10, height: cellSize.height, alignment: .trailing)
                    .offset(x: 0, y: CGFloat(gridY) * pitchY)
            }
        }
    }
}
