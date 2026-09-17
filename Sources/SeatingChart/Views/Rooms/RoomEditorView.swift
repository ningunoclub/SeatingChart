import SwiftUI

/// Visual room layout editor: click an empty cell to add a desk, drag to move,
/// right-click for disable/delete.
struct RoomEditorView: View {
    let roomID: UUID
    @Environment(AppStore.self) private var store
    @State private var showingQuickSetup = false
    @State private var draggedDeskID: UUID?
    @State private var dragTranslation: CGSize = .zero

    private let cell: CGFloat = 44
    private let spacing: CGFloat = 6
    private let gutter: CGFloat = 56
    private var pitch: CGFloat { cell + spacing }

    var body: some View {
        let room = store.binding(forRoom: roomID)

        VStack(alignment: .leading, spacing: 0) {
            header(room)
            Divider()
            ScrollView([.horizontal, .vertical]) {
                canvas(room).padding(28)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .toolbar {
            ToolbarItem(placement: .status) {
                Text(L("room.counts", room.wrappedValue.desks.count,
                       room.wrappedValue.enabledDesks.count))
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            ToolbarItem(placement: .primaryAction) {
                Picker(L("room.numbering"), selection: room.seatNumbering) {
                    Text(L("room.numbering.front_left")).tag(SeatNumbering.frontLeft)
                    Text(L("room.numbering.front_right")).tag(SeatNumbering.frontRight)
                }
                .pickerStyle(.menu)
                .help(L("room.numbering_help"))
            }
            ToolbarItem(placement: .primaryAction) {
                Button(L("room.quick_setup")) { showingQuickSetup = true }
                    .help(L("room.quick_setup_help"))
            }
        }
        .sheet(isPresented: $showingQuickSetup) {
            QuickSetupSheet(room: room)
        }
    }

    // MARK: - Header

    private func header(_ room: Binding<Room>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(L("room.name_placeholder"), text: room.name)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .semibold))
            Text(L("room.editor_hint"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    // MARK: - Canvas

    private func canvas(_ room: Binding<Room>) -> some View {
        let value = room.wrappedValue
        let columns = max(value.gridWidth + 2, 8)
        let rows = max(value.gridHeight + 2, 5)
        let gridWidth = CGFloat(columns) * pitch - spacing
        let gridHeight = CGFloat(rows) * pitch - spacing

        return VStack(spacing: 18) {
            BlackboardView(width: gridWidth).padding(.leading, gutter)

            HStack(alignment: .top, spacing: 0) {
                rowLabels(value)
                    .frame(width: gutter, height: gridHeight, alignment: .topLeading)
                ZStack(alignment: .topLeading) {
                    emptyCells(room, columns: columns, rows: rows)
                    ForEach(value.orderedDesks) { desk in
                        deskView(desk, room: room)
                    }
                }
                .frame(width: gridWidth, height: gridHeight, alignment: .topLeading)
            }
        }
    }

    private func rowLabels(_ room: Room) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(room.rowByGridY.sorted(by: { $0.key < $1.key }), id: \.key) { gridY, row in
                Text(L("room.row_number", row))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: gutter - 10, height: cell, alignment: .trailing)
                    .offset(y: CGFloat(gridY) * pitch)
            }
        }
    }

    private func emptyCells(_ room: Binding<Room>, columns: Int, rows: Int) -> some View {
        ForEach(0..<rows, id: \.self) { y in
            ForEach(0..<columns, id: \.self) { x in
                if room.wrappedValue.desk(atX: x, y: y) == nil {
                    RoundedRectangle(cornerRadius: Theme.deskCorner)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(.quaternary)
                        .frame(width: cell, height: cell)
                        .contentShape(Rectangle())
                        .offset(x: CGFloat(x) * pitch, y: CGFloat(y) * pitch)
                        .onTapGesture {
                            room.wrappedValue.desks.append(Desk(gridX: x, gridY: y))
                        }
                        .help(L("room.add_desk_help"))
                }
            }
        }
    }

    private func deskView(_ desk: Desk, room: Binding<Room>) -> some View {
        let isDragging = draggedDeskID == desk.id
        let seat = room.wrappedValue.seatNumber(of: desk.id) ?? 0

        return EditorDeskView(seatNumber: seat, isDisabled: desk.isDisabled)
            .frame(width: cell, height: cell)
            .offset(x: CGFloat(desk.gridX) * pitch, y: CGFloat(desk.gridY) * pitch)
            .offset(isDragging ? dragTranslation : .zero)
            .scaleEffect(isDragging ? 1.08 : 1)
            .zIndex(isDragging ? 1 : 0)
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        draggedDeskID = desk.id
                        dragTranslation = value.translation
                    }
                    .onEnded { value in
                        drop(desk, translation: value.translation, room: room)
                        draggedDeskID = nil
                        dragTranslation = .zero
                    }
            )
            .contextMenu {
                Button(desk.isDisabled ? L("room.enable_desk") : L("room.disable_desk")) {
                    toggleDisabled(desk, room: room)
                }
                Button(L("room.delete_desk"), role: .destructive) {
                    room.wrappedValue.desks.removeAll { $0.id == desk.id }
                }
            }
    }

    // MARK: - Editing

    /// Snaps to the nearest cell; a drop onto an occupied or off-grid cell reverts.
    private func drop(_ desk: Desk, translation: CGSize, room: Binding<Room>) {
        let targetX = desk.gridX + Int((translation.width / pitch).rounded())
        let targetY = desk.gridY + Int((translation.height / pitch).rounded())
        guard targetX >= 0, targetY >= 0 else { return }
        guard targetX != desk.gridX || targetY != desk.gridY else { return }
        guard room.wrappedValue.desk(atX: targetX, y: targetY) == nil else { return }
        guard let index = room.wrappedValue.desks.firstIndex(where: { $0.id == desk.id }) else { return }
        room.wrappedValue.desks[index].gridX = targetX
        room.wrappedValue.desks[index].gridY = targetY
    }

    private func toggleDisabled(_ desk: Desk, room: Binding<Room>) {
        guard let index = room.wrappedValue.desks.firstIndex(where: { $0.id == desk.id }) else { return }
        room.wrappedValue.desks[index].isDisabled.toggle()
    }
}

/// One desk as drawn in the editor: seat number, hatched when disabled.
struct EditorDeskView: View {
    let seatNumber: Int
    let isDisabled: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.deskCorner)
            .fill(isDisabled ? AnyShapeStyle(Color.gray.opacity(0.12))
                             : AnyShapeStyle(Color.accentColor.opacity(0.16)))
            .overlay {
                if isDisabled { HatchPattern() }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.deskCorner)
                    .strokeBorder(isDisabled ? Color.secondary.opacity(0.4) : Color.accentColor.opacity(0.6))
            }
            .overlay {
                Text("\(seatNumber)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(isDisabled ? Color.secondary : Color.primary)
            }
            .help(isDisabled ? L("room.disabled_desk_help") : L("room.desk_help"))
    }
}

/// Diagonal stripes marking a desk that is never assigned.
struct HatchPattern: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 7
            }
            context.stroke(path, with: .color(.secondary.opacity(0.35)), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.deskCorner))
        .allowsHitTesting(false)
    }
}
