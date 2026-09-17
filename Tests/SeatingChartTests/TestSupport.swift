import Foundation
import Testing
@testable import SeatingChart

enum Fixture {
    /// A room of `rows` × `seatsPerRow` desks.
    static func room(rows: Int, seatsPerRow: Int, aisleAfterSeat: Int? = nil,
                     name: String = "Room 204") -> Room {
        Room(name: name, desks: Room.regularLayout(rows: rows, seatsPerRow: seatsPerRow,
                                                   aisleAfterSeat: aisleAfterSeat))
    }

    static func schoolClass(_ names: [String], name: String = "5a") -> SchoolClass {
        SchoolClass(name: name, students: names.map { Student(firstName: $0) })
    }

    /// `males` names, then `females`, then `unspecified` — named M1…, F1…, U1…
    /// so a group's make-up can be read straight off the assertion.
    static func mixedClass(males: Int, females: Int, unspecified: Int = 0,
                           name: String = "5a") -> SchoolClass {
        var students: [Student] = []
        students += (0..<max(0, males)).map { Student(firstName: "M\($0 + 1)", gender: .male) }
        students += (0..<max(0, females)).map { Student(firstName: "F\($0 + 1)", gender: .female) }
        students += (0..<max(0, unspecified)).map { Student(firstName: "U\($0 + 1)") }
        return SchoolClass(name: name, students: students)
    }

    static func id(_ schoolClass: SchoolClass, _ firstName: String) -> UUID {
        schoolClass.students.first { $0.firstName == firstName }!.id
    }

    /// Order-independent fingerprint of an assignment, for "did it change?" checks.
    static func signature(of chart: SeatingChart) -> String {
        chart.assignment
            .map { "\($0.key.uuidString)>\($0.value.uuidString)" }
            .sorted()
            .joined(separator: "|")
    }

    /// Asserts generation throws a `GeneratorError` matching `predicate`.
    static func expectGeneratorError(
        schoolClass: SchoolClass, room: Room, mode: GenerationMode,
        rng: inout SplitMix64,
        sourceLocation: SourceLocation = #_sourceLocation,
        _ predicate: (GeneratorError) -> Bool
    ) {
        do {
            _ = try SeatingGenerator.generate(schoolClass: schoolClass, room: room,
                                              mode: mode, rng: &rng)
            Issue.record("expected the generator to fail", sourceLocation: sourceLocation)
        } catch let error as GeneratorError {
            #expect(predicate(error), "unexpected generator error: \(error)",
                    sourceLocation: sourceLocation)
        } catch {
            Issue.record("unexpected error: \(error)", sourceLocation: sourceLocation)
        }
    }
}
