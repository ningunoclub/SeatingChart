import SwiftUI

/// Keep-apart pairs (editable) and seat pins (read-only — they are created in
/// the chart view, where there is a room to point at).
struct ConstraintsSectionView: View {
    @Binding var schoolClass: SchoolClass
    @Environment(AppStore.self) private var store
    @State private var isAddingPair = false
    @State private var firstPick: UUID?
    @State private var secondPick: UUID?
    @State private var pairWarning: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            keepApartSection
            if !seatPinRows.isEmpty {
                Divider().padding(.vertical, 2)
                seatPinSection
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Keep apart

    private var keepApartSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("class.keep_apart")).font(.subheadline).fontWeight(.medium)
                Spacer()
                Button(L("class.add_pair")) { startAddingPair() }
                    .disabled(schoolClass.students.count < 2)
                    .popover(isPresented: $isAddingPair, arrowEdge: .bottom) { pairPicker }
            }

            if keepApartRows.isEmpty {
                Text(L("class.no_keep_apart")).foregroundStyle(.secondary).font(.callout)
            } else {
                ForEach(keepApartRows) { row in
                    HStack {
                        Text("\(row.first)  ↔  \(row.second)")
                        Spacer()
                        Button {
                            schoolClass.constraints.removeAll { $0 == row.constraint }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(L("class.remove_pair"))
                    }
                }
            }
        }
    }

    private var pairPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("class.add_pair_title")).font(.headline)
            Picker(L("class.pair_first"), selection: $firstPick) {
                ForEach(schoolClass.students) { student in
                    Text(student.firstName).tag(Optional(student.id))
                }
            }
            Picker(L("class.pair_second"), selection: $secondPick) {
                ForEach(schoolClass.students) { student in
                    Text(student.firstName).tag(Optional(student.id))
                }
            }
            if let pairWarning {
                Text(pairWarning).font(.callout).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button(L("common.cancel")) { isAddingPair = false }
                Button(L("class.add_button")) { addPair() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private func startAddingPair() {
        pairWarning = nil
        firstPick = schoolClass.students.first?.id
        secondPick = schoolClass.students.dropFirst().first?.id
        isAddingPair = true
    }

    private func addPair() {
        guard let first = firstPick, let second = secondPick else { return }
        guard first != second else {
            pairWarning = L("class.pair_same_student")
            return
        }
        guard schoolClass.addKeepApart(first, second) else {
            pairWarning = L("class.pair_duplicate")
            return
        }
        isAddingPair = false
    }

    // MARK: - Seat pins

    private var seatPinSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("class.seat_pins")).font(.subheadline).fontWeight(.medium)
            Text(L("class.seat_pins_hint")).font(.caption).foregroundStyle(.secondary)
            ForEach(seatPinRows) { row in
                HStack {
                    Text(row.label)
                    Spacer()
                    Button {
                        schoolClass.constraints.removeAll { $0 == row.constraint }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(L("class.remove_seat_pin"))
                }
            }
        }
    }

    // MARK: - Rows

    private struct PairRow: Identifiable {
        let id: String
        let first: String
        let second: String
        let constraint: Constraint
    }

    private struct PinRow: Identifiable {
        let id: String
        let label: String
        let constraint: Constraint
    }

    private var keepApartRows: [PairRow] {
        schoolClass.constraints.compactMap { constraint in
            guard case let .keepApart(a, b) = constraint,
                  let first = schoolClass.name(of: a), let second = schoolClass.name(of: b)
            else { return nil }
            return PairRow(id: "\(a)-\(b)", first: first, second: second, constraint: constraint)
        }
    }

    private var seatPinRows: [PinRow] {
        schoolClass.constraints.compactMap { constraint in
            guard case let .seatPin(studentID, roomID, deskID) = constraint,
                  let name = schoolClass.name(of: studentID),
                  let room = store.room(roomID),
                  let seat = room.seatNumber(of: deskID)
            else { return nil }
            return PinRow(id: "\(studentID)-\(deskID)",
                          label: L("class.seat_pin_row", name, room.name, seat),
                          constraint: constraint)
        }
    }
}
