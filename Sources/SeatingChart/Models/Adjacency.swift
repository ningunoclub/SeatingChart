import Foundation

/// Neighbour map derived from the desk grid. A gap in the grid breaks adjacency,
/// which is how separated desk pairs and aisles are modelled.
struct Adjacency {
    let neighbors: [UUID: Set<UUID>]

    init(room: Room, mode: AdjacencyMode) {
        let desks = room.enabledDesks
        var byPosition: [Position: UUID] = [:]
        for desk in desks { byPosition[Position(x: desk.gridX, y: desk.gridY)] = desk.id }

        var map: [UUID: Set<UUID>] = [:]
        for desk in desks {
            var set: Set<UUID> = []
            // Side neighbours are always adjacent.
            for dx in [-1, 1] {
                if let other = byPosition[Position(x: desk.gridX + dx, y: desk.gridY)] {
                    set.insert(other)
                }
            }
            if mode == .strict {
                for dy in [-1, 1] {
                    if let other = byPosition[Position(x: desk.gridX, y: desk.gridY + dy)] {
                        set.insert(other)
                    }
                }
            }
            map[desk.id] = set
        }
        neighbors = map
    }

    func neighbors(of deskID: UUID) -> Set<UUID> { neighbors[deskID] ?? [] }

    func areAdjacent(_ first: UUID, _ second: UUID) -> Bool {
        neighbors[first]?.contains(second) ?? false
    }

    private struct Position: Hashable {
        let x: Int
        let y: Int
    }
}
