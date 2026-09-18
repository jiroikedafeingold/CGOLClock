import Foundation
@testable import CGOLClock

struct Coordinate: Hashable {
    let x: Int
    let y: Int
}

/// Cells of a glider whose bounding box has its top-left corner at `x, y`.
/// Four generations later the same shape reappears one cell right and down.
func glider(x: Int, y: Int) -> [Coordinate] {
    [
        Coordinate(x: x + 1, y: y),
        Coordinate(x: x + 2, y: y + 1),
        Coordinate(x: x, y: y + 2),
        Coordinate(x: x + 1, y: y + 2),
        Coordinate(x: x + 2, y: y + 2),
    ]
}

func makeGrid(width: Int, height: Int, live: [Coordinate]) -> LifeGrid {
    let grid = LifeGrid(width: width, height: height)
    for cell in live {
        grid[cell.x, cell.y] = true
    }
    return grid
}

/// Every live cell inside the declared bounds. Compared against
/// `populationCount` this also proves no bits survived past `width`.
func liveCells(_ grid: LifeGrid) -> Set<Coordinate> {
    var result: Set<Coordinate> = []
    for y in 0..<grid.height {
        for x in 0..<grid.width where grid[x, y] {
            result.insert(Coordinate(x: x, y: y))
        }
    }
    return result
}

/// Straightforward per-cell toroidal Life, used to cross-check the SWAR step.
func naiveStep(_ cells: Set<Coordinate>, width: Int, height: Int) -> Set<Coordinate> {
    var neighbourCounts: [Coordinate: Int] = [:]
    for cell in cells {
        for dy in -1...1 {
            for dx in -1...1 where !(dx == 0 && dy == 0) {
                let neighbour = Coordinate(
                    x: (cell.x + dx + width) % width,
                    y: (cell.y + dy + height) % height
                )
                neighbourCounts[neighbour, default: 0] += 1
            }
        }
    }
    var next: Set<Coordinate> = []
    for (cell, count) in neighbourCounts where count == 3 || (count == 2 && cells.contains(cell)) {
        next.insert(cell)
    }
    return next
}

/// Deterministic soup so a failing cross-check is reproducible.
func randomSoup(width: Int, height: Int, seed: UInt64, density: UInt64 = 3) -> [Coordinate] {
    var state = seed
    var cells: [Coordinate] = []
    for y in 0..<height {
        for x in 0..<width {
            // xorshift64
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            if state % 10 < density {
                cells.append(Coordinate(x: x, y: y))
            }
        }
    }
    return cells
}
