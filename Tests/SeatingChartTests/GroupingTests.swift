import Foundation
import Testing
@testable import SeatingChart

@Suite("Auto grouping")
struct GroupingTests {

    private func draw(_ schoolClass: SchoolClass, sizing: GroupSizing,
                      quota: GroupQuota = .none, teamNames: [String] = [],
                      representatives: Bool = false, seed: UInt64 = 11) -> GroupingResult {
        var rng = SplitMix64(seed: seed)
        return GroupDraw.make(from: schoolClass.students, sizing: sizing, quota: quota,
                              teamNames: teamNames, pickRepresentatives: representatives,
                              using: &rng)
    }

    /// Gender make-up of one group, read back through the class.
    private func tally(_ group: StudentGroup, in schoolClass: SchoolClass)
        -> (male: Int, female: Int, unspecified: Int) {
        GroupDraw.tally(group.memberIDs.compactMap { schoolClass.student($0) })
    }

    // MARK: - How many groups

    @Test("A group count is honoured, and never exceeds the class size")
    func groupCountHonoured() {
        #expect(GroupDraw.groupCount(for: .groupCount(4), studentCount: 20) == 4)
        #expect(GroupDraw.groupCount(for: .groupCount(9), studentCount: 5) == 5)
        #expect(GroupDraw.groupCount(for: .groupCount(0), studentCount: 5) == 1)
        #expect(GroupDraw.groupCount(for: .groupCount(4), studentCount: 0) == 0)
    }

    @Test("Max per group rounds up so nobody is left over")
    func maxPerGroupRoundsUp() {
        #expect(GroupDraw.groupCount(for: .maxPerGroup(3), studentCount: 10) == 4)
        #expect(GroupDraw.groupCount(for: .maxPerGroup(5), studentCount: 10) == 2)
        #expect(GroupDraw.groupCount(for: .maxPerGroup(1), studentCount: 7) == 7)

        let schoolClass = Fixture.mixedClass(males: 5, females: 5)
        let result = draw(schoolClass, sizing: .maxPerGroup(3))
        #expect(result.groups.count == 4)
        #expect(result.groups.allSatisfy { $0.memberIDs.count <= 3 })
    }

    // MARK: - Everyone lands somewhere, once

    @Test("Every student is placed exactly once")
    func everyoneOnce() {
        let schoolClass = Fixture.mixedClass(males: 9, females: 7, unspecified: 3)
        let result = draw(schoolClass, sizing: .groupCount(4))
        let placed = result.groups.flatMap(\.memberIDs)

        #expect(placed.count == schoolClass.students.count)
        #expect(Set(placed) == Set(schoolClass.students.map(\.id)))
    }

    @Test("Group sizes differ by at most one")
    func sizesEven() {
        for count in [2, 3, 4, 5, 7] {
            let schoolClass = Fixture.mixedClass(males: 11, females: 12)
            let sizes = draw(schoolClass, sizing: .groupCount(count), seed: UInt64(count))
                .groups.map(\.memberIDs.count)
            #expect((sizes.max() ?? 0) - (sizes.min() ?? 0) <= 1, "uneven for \(count) groups")
            #expect(sizes.allSatisfy { $0 > 0 })
        }
    }

    // MARK: - Gender spread

    @Test("Without a quota the genders still come out even")
    func gendersSpreadEvenly() {
        let schoolClass = Fixture.mixedClass(males: 8, females: 8)
        let result = draw(schoolClass, sizing: .groupCount(4))

        for group in result.groups {
            let split = tally(group, in: schoolClass)
            #expect(split.male == 2)
            #expect(split.female == 2)
        }
        #expect(!result.isShort)
    }

    @Test("Students with no gender set are spread too, not piled into one group")
    func unspecifiedSpreadEvenly() {
        let schoolClass = Fixture.mixedClass(males: 4, females: 4, unspecified: 4)
        let result = draw(schoolClass, sizing: .groupCount(4))

        #expect(result.groups.allSatisfy { tally($0, in: schoolClass).unspecified == 1 })
    }

    // MARK: - Quotas

    @Test("A satisfiable quota is always met")
    func quotaMet() {
        let schoolClass = Fixture.mixedClass(males: 8, females: 8)
        let result = draw(schoolClass, sizing: .groupCount(4),
                          quota: GroupQuota(male: 2, female: 2))

        #expect(!result.isShort)
        for group in result.groups {
            let split = tally(group, in: schoolClass)
            #expect(split.male == 2)
            #expect(split.female == 2)
        }
    }

    @Test("A quota the class cannot fill reports the shortfall and still seats everyone")
    func quotaShortfall() {
        // Four groups want 3 male each — 12 in all — but there are only 4.
        let schoolClass = Fixture.mixedClass(males: 4, females: 12)
        let result = draw(schoolClass, sizing: .groupCount(4),
                          quota: GroupQuota(male: 3, female: 1))

        #expect(result.missingMale == 8)
        #expect(result.missingFemale == 0)
        #expect(result.groups.flatMap(\.memberIDs).count == schoolClass.students.count)
        #expect(Set(result.groups.flatMap(\.memberIDs)) == Set(schoolClass.students.map(\.id)))
    }

    @Test("A one-sided quota leaves the other gender to the even spread")
    func oneSidedQuota() {
        let schoolClass = Fixture.mixedClass(males: 6, females: 6)
        let result = draw(schoolClass, sizing: .groupCount(3), quota: GroupQuota(male: 2, female: 0))

        #expect(!result.isShort)
        #expect(result.groups.allSatisfy { tally($0, in: schoolClass).male == 2 })
        #expect(result.groups.allSatisfy { tally($0, in: schoolClass).female == 2 })
    }

    // MARK: - Representatives

    @Test("Each group gets one representative, drawn from its own members")
    func representatives() {
        let schoolClass = Fixture.mixedClass(males: 6, females: 6)
        let result = draw(schoolClass, sizing: .groupCount(3), representatives: true)

        for group in result.groups {
            #expect(group.representativeID != nil)
            #expect(group.memberIDs.contains { $0 == group.representativeID })
        }
    }

    @Test("No representatives when the option is off")
    func noRepresentatives() {
        let schoolClass = Fixture.mixedClass(males: 4, females: 4)
        let result = draw(schoolClass, sizing: .groupCount(2))

        #expect(result.groups.allSatisfy { $0.representativeID == nil })
    }

    // MARK: - Names

    @Test("Custom names are used in order, with numbers past the end of the list")
    func teamNames() {
        let schoolClass = Fixture.mixedClass(males: 5, females: 5)
        let result = draw(schoolClass, sizing: .groupCount(4),
                          teamNames: ["Lions", "  ", "Bears"])

        #expect(result.groups[0].name == "Lions")
        // A blank entry is not a name — the numbered fallback covers it.
        #expect(result.groups[1].name == GroupDraw.teamName(at: 1, from: []))
        #expect(result.groups[2].name == "Bears")
        #expect(result.groups[3].name == GroupDraw.teamName(at: 3, from: []))
    }

    @Test("The numbered fallback counts from one")
    func numberedFallback() {
        #expect(GroupDraw.teamName(at: 0, from: []).contains("1"))
        #expect(GroupDraw.teamName(at: 4, from: []).contains("5"))
    }

    // MARK: - Degenerate classes

    @Test("An empty class makes no groups")
    func emptyClass() {
        var rng = SplitMix64(seed: 1)
        let result = GroupDraw.make(from: [], sizing: .groupCount(3), using: &rng)
        #expect(result.groups.isEmpty)
    }

    @Test("Asking for more groups than there are students makes no empty group")
    func moreGroupsThanStudents() {
        let schoolClass = Fixture.mixedClass(males: 2, females: 1)
        let result = draw(schoolClass, sizing: .groupCount(10))

        #expect(result.groups.count == 3)
        #expect(result.groups.allSatisfy { $0.memberIDs.count == 1 })
    }

    // MARK: - The tally behind the settings bar

    @Test("The tally counts each gender")
    func tallyCounts() {
        let schoolClass = Fixture.mixedClass(males: 3, females: 5, unspecified: 2)
        let counted = GroupDraw.tally(schoolClass.students)

        #expect(counted.male == 3)
        #expect(counted.female == 5)
        #expect(counted.unspecified == 2)
    }
}
