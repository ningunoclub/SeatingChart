import SwiftUI

enum PresentationScene {
    static let windowID = "presentation"
}

/// Second window for the beamer: black, no chrome, layout scaled to fill.
/// It reads the current chart from the store, so regenerating updates it live.
struct PresentationView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .onExitCommand { dismiss() }
    }

    @ViewBuilder
    private var content: some View {
        if let room = store.currentRoom, let schoolClass = store.currentClass,
           let chart = store.currentChart {
            GeometryReader { proxy in
                let layout = RoomLayoutView(
                    room: room,
                    cellSize: CGSize(width: 150, height: 118),
                    spacing: 16,
                    showsRowLabels: false,
                    onDark: true
                ) { desk in
                    ChartDeskView(desk: desk,
                                  student: chart.assignment[desk.id].flatMap { schoolClass.student($0) },
                                  seatNumber: room.seatNumber(of: desk.id) ?? 0,
                                  style: .presentation,
                                  height: 118)
                }
                let size = layout.contentSize
                let available = CGSize(width: proxy.size.width - 80,
                                       height: proxy.size.height - 120)
                let scale = min(available.width / size.width, available.height / size.height)

                VStack(spacing: 0) {
                    Text(L("chart.presentation_title", schoolClass.name, room.name))
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.top, 22)
                    Spacer(minLength: 0)
                    layout
                        .frame(width: size.width, height: size.height)
                        .scaleEffect(max(scale, 0.1))
                        .frame(width: proxy.size.width, height: size.height * max(scale, 0.1))
                    Spacer(minLength: 0)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        } else {
            Text(L("chart.presentation_empty"))
                .font(.title2)
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}
