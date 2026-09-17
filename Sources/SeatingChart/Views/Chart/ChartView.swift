import SwiftUI

struct ChartView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            controls
            Divider()
            chartArea
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    openWindow(id: PresentationScene.windowID)
                } label: {
                    Label(L("chart.present"), systemImage: "play.rectangle")
                }
                .disabled(store.currentChart == nil)
                .help(L("chart.present_help"))

                Button {
                    ChartExport.exportPDF(store: store)
                } label: {
                    Label(L("chart.export_pdf"), systemImage: "arrow.down.document")
                }
                .disabled(store.currentChart == nil)

                Button {
                    ChartExport.printChart(store: store)
                } label: {
                    Label(L("chart.print"), systemImage: "printer")
                }
                .disabled(store.currentChart == nil)
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Picker(L("chart.class"), selection: $store.chartClassID) {
                    Text(L("chart.none")).tag(UUID?.none)
                    ForEach(store.classes) { schoolClass in
                        Text(schoolClass.name).tag(Optional(schoolClass.id))
                    }
                }
                .frame(maxWidth: 220)

                Picker(L("chart.room"), selection: $store.chartRoomID) {
                    Text(L("chart.none")).tag(UUID?.none)
                    ForEach(store.rooms) { room in
                        Text(room.name).tag(Optional(room.id))
                    }
                }
                .frame(maxWidth: 220)

                Spacer()

                Button {
                    store.generate()
                } label: {
                    Label(L("chart.generate"), systemImage: "shuffle")
                }
                .disabled(!store.canGenerate)
                .buttonStyle(.borderedProminent)

                Button {
                    store.generate()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(!store.canGenerate)
                .help(L("chart.generate_again"))
            }

            HStack(spacing: 14) {
                Picker(L("chart.mode"), selection: $store.modeKind) {
                    Text(L("chart.mode.random")).tag(ModeKind.trueRandom)
                    Text(L("chart.mode.constrained")).tag(ModeKind.constrained)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
                .labelsHidden()

                if store.modeKind == .constrained {
                    Picker(L("chart.adjacency"), selection: $store.adjacencyMode) {
                        Text(L("chart.adjacency.relaxed")).tag(AdjacencyMode.relaxed)
                        Text(L("chart.adjacency.strict")).tag(AdjacencyMode.strict)
                    }
                    .frame(maxWidth: 260)
                }

                Spacer()

                Text(capacityHint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var capacityHint: String {
        guard let schoolClass = store.currentClass, let room = store.currentRoom else {
            return L("chart.pick_class_and_room")
        }
        return L("chart.capacity", schoolClass.students.count, room.enabledDesks.count)
    }

    // MARK: - Chart

    @ViewBuilder
    private var chartArea: some View {
        if let room = store.currentRoom, let schoolClass = store.currentClass {
            if room.desks.isEmpty {
                ContentUnavailableView(L("chart.empty_room"), systemImage: "square.dashed",
                                       description: Text(L("chart.empty_room_hint")))
            } else if store.currentChart == nil {
                ContentUnavailableView(L("chart.not_generated"), systemImage: "shuffle",
                                       description: Text(L("chart.not_generated_hint")))
            } else {
                scaledChart(room: room, schoolClass: schoolClass)
            }
        } else {
            ContentUnavailableView(L("chart.pick_class_and_room"), systemImage: "chair",
                                   description: Text(L("chart.pick_hint")))
        }
    }

    private func scaledChart(room: Room, schoolClass: SchoolClass) -> some View {
        let layout = RoomLayoutView(room: room) { desk in
            deskCard(desk, room: room, schoolClass: schoolClass)
        }
        let size = layout.contentSize

        return GeometryReader { proxy in
            let available = CGSize(width: proxy.size.width - 48, height: proxy.size.height - 48)
            let scale = min(1, min(available.width / size.width, available.height / size.height))
            layout
                .frame(width: size.width, height: size.height)
                .scaleEffect(max(scale, 0.2))
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func deskCard(_ desk: Desk, room: Room, schoolClass: SchoolClass) -> some View {
        let studentID = store.currentChart?.assignment[desk.id]
        let student = studentID.flatMap { schoolClass.student($0) }
        let pinnedStudent = store.seatPinnedStudent(atDesk: desk.id)

        return ChartDeskView(
            desk: desk,
            student: student,
            seatNumber: room.seatNumber(of: desk.id) ?? 0,
            isPinned: pinnedStudent != nil
        )
        .contextMenu {
            if desk.isDisabled {
                Text(L("chart.desk_disabled"))
            } else {
                if let student {
                    Button(L("chart.pin_student_here", student.firstName)) {
                        store.pinStudent(student.id, toDesk: desk.id)
                    }
                    .disabled(pinnedStudent == student.id)
                }
                Menu(L("chart.pin_someone_here")) {
                    ForEach(schoolClass.students) { candidate in
                        Button(candidate.firstName) {
                            store.pinStudent(candidate.id, toDesk: desk.id)
                        }
                    }
                }
                if pinnedStudent != nil {
                    Button(L("chart.remove_pin"), role: .destructive) {
                        store.removeSeatPin(deskID: desk.id)
                    }
                }
            }
        }
    }
}
