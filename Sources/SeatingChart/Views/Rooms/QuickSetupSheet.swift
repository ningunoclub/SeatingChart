import SwiftUI

/// Builds a regular layout in one step. Replaces whatever the room has now.
struct QuickSetupSheet: View {
    @Binding var room: Room
    @Environment(\.dismiss) private var dismiss

    @State private var rows = 4
    @State private var seatsPerRow = 6
    @State private var useAisle = true
    @State private var aisleAfterSeat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("room.quick_setup")).font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text(L("room.rows"))
                    Stepper(value: $rows, in: 1...10) { Text("\(rows)").monospacedDigit() }
                }
                GridRow {
                    Text(L("room.seats_per_row"))
                    Stepper(value: $seatsPerRow, in: 1...12) {
                        Text("\(seatsPerRow)").monospacedDigit()
                    }
                }
                GridRow {
                    Toggle(L("room.aisle"), isOn: $useAisle)
                        .gridCellColumns(1)
                    Stepper(value: $aisleAfterSeat, in: 1...max(1, seatsPerRow - 1)) {
                        Text(L("room.aisle_after", aisleAfterSeat))
                    }
                    .disabled(!useAisle)
                }
            }

            Text(L("room.quick_setup_summary", rows * seatsPerRow))
                .font(.callout)
                .foregroundStyle(.secondary)

            if !room.desks.isEmpty {
                Label(L("room.quick_setup_warning"), systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button(L("common.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("room.replace_layout")) { apply() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 400)
    }

    private func apply() {
        room.desks = Room.regularLayout(
            rows: rows,
            seatsPerRow: seatsPerRow,
            aisleAfterSeat: useAisle ? min(aisleAfterSeat, seatsPerRow - 1) : nil
        )
        dismiss()
    }
}
