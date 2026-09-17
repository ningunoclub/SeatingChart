import Foundation
import Testing
@testable import SeatingChart

@Suite("Name picker draw")
struct NamePickerTests {

    /// Draws `count` times, threading the round through as the model does.
    private func draw(_ count: Int, from students: [Student], avoidRepeats: Bool = true,
                      seed: UInt64 = 7, picked: [UUID] = []) -> (winners: [UUID], picked: [UUID]) {
        var rng = SplitMix64(seed: seed)
        var round = picked
        var winners: [UUID] = []
        for _ in 0..<count {
            guard let result = NameDraw.next(from: students, picked: round,
                                             avoidRepeats: avoidRepeats, using: &rng) else { break }
            winners.append(result.winner)
            round = result.picked
        }
        return (winners, round)
    }

    // MARK: - Without replacement

    @Test("Everyone gets a turn before anyone repeats")
    func everyoneBeforeRepeat() {
        let schoolClass = Fixture.schoolClass(["A", "B", "C", "D", "E", "F"])
        let (winners, _) = draw(6, from: schoolClass.students)

        #expect(winners.count == 6)
        #expect(Set(winners).count == 6)
        #expect(Set(winners) == Set(schoolClass.students.map(\.id)))
    }

    @Test("The round starts over once the class is exhausted")
    func roundResets() {
        let schoolClass = Fixture.schoolClass(["A", "B", "C"])
        let (winners, picked) = draw(4, from: schoolClass.students)

        // First three cover everyone; the fourth opens a fresh round.
        #expect(Set(winners.prefix(3)).count == 3)
        #expect(picked.count == 1)
        #expect(picked == [winners[3]])
    }

    @Test("A full round reports everyone as picked")
    func progressCount() {
        let schoolClass = Fixture.schoolClass(["A", "B", "C", "D"])
        let (_, picked) = draw(4, from: schoolClass.students)

        #expect(NameDraw.pickedCount(in: schoolClass.students, picked: picked) == 4)
        #expect(NameDraw.remaining(in: schoolClass.students, picked: picked).isEmpty)
    }

    // MARK: - With replacement

    @Test("Repeats are allowed when the guard is off")
    func repeatsWhenGuardOff() {
        let schoolClass = Fixture.schoolClass(["A", "B"])
        let (winners, picked) = draw(40, from: schoolClass.students, avoidRepeats: false)
        let memberIDs = Set(schoolClass.students.map(\.id))

        #expect(winners.count == 40)
        #expect(winners.allSatisfy(memberIDs.contains))
        // 40 draws from two names without replacement-tracking must repeat.
        #expect(Set(winners).count <= 2)
        #expect(winners.count > Set(winners).count)
        // The round is only about repeat-avoidance, so it stays untouched.
        #expect(picked.isEmpty)
    }

    // MARK: - The class changing mid-round

    @Test("A student deleted mid-round drops out of the pool")
    func deletedStudentDropsOut() {
        let schoolClass = Fixture.schoolClass(["A", "B", "C", "D"])
        let (_, picked) = draw(2, from: schoolClass.students)

        // Someone who already had a turn leaves the class.
        var survivors = schoolClass.students
        survivors.removeAll { $0.id == picked[0] }

        #expect(NameDraw.pickedCount(in: survivors, picked: picked) == 1)
        #expect(NameDraw.remaining(in: survivors, picked: picked).count == 2)

        // Their stale id must not linger in the round either.
        var rng = SplitMix64(seed: 3)
        let result = NameDraw.next(from: survivors, picked: picked,
                                   avoidRepeats: true, using: &rng)
        #expect(result?.picked.contains(picked[0]) == false)
    }

    @Test("A student added mid-round joins the pool immediately")
    func addedStudentJoins() {
        let schoolClass = Fixture.schoolClass(["A", "B"])
        let (_, picked) = draw(2, from: schoolClass.students)
        #expect(NameDraw.remaining(in: schoolClass.students, picked: picked).isEmpty)

        let newcomer = Student(firstName: "C")
        let grown = schoolClass.students + [newcomer]
        #expect(NameDraw.remaining(in: grown, picked: picked).map(\.id) == [newcomer.id])

        // The exhausted round has one name left, so it is drawn next.
        var rng = SplitMix64(seed: 5)
        let result = NameDraw.next(from: grown, picked: picked, avoidRepeats: true, using: &rng)
        #expect(result?.winner == newcomer.id)
    }

    // MARK: - Degenerate classes

    @Test("An empty class draws nothing")
    func emptyClass() {
        var rng = SplitMix64(seed: 1)
        #expect(NameDraw.next(from: [], picked: [], avoidRepeats: true, using: &rng) == nil)
        #expect(NameDraw.next(from: [], picked: [], avoidRepeats: false, using: &rng) == nil)
    }

    @Test("A one-student class keeps returning that student")
    func singleStudent() {
        let schoolClass = Fixture.schoolClass(["A"])
        let only = schoolClass.students[0].id
        let (winners, _) = draw(5, from: schoolClass.students)

        #expect(winners == Array(repeating: only, count: 5))
    }
}
