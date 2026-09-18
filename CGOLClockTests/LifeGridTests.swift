import Testing
@testable import CGOLClock

@Suite("LifeGrid rules")
struct LifeGridRuleTests {

    @Test("An empty board stays empty")
    func emptyBoardStaysEmpty() {
        let grid = LifeGrid(width: 76, height: 40)
        for _ in 0..<5 { grid.step() }
        #expect(grid.populationCount == 0)
    }

    @Test("A 2x2 block is a still life")
    func blockIsStill() {
        let block = [
            Coordinate(x: 4, y: 4), Coordinate(x: 5, y: 4),
            Coordinate(x: 4, y: 5), Coordinate(x: 5, y: 5),
        ]
        let grid = makeGrid(width: 20, height: 20, live: block)
        for _ in 0..<10 { grid.step() }
        #expect(liveCells(grid) == Set(block))
    }

    @Test("A blinker oscillates with period 2")
    func blinkerOscillates() {
        let horizontal = [Coordinate(x: 1, y: 2), Coordinate(x: 2, y: 2), Coordinate(x: 3, y: 2)]
        let vertical = [Coordinate(x: 2, y: 1), Coordinate(x: 2, y: 2), Coordinate(x: 2, y: 3)]
        let grid = makeGrid(width: 20, height: 20, live: horizontal)

        grid.step()
        #expect(liveCells(grid) == Set(vertical))
        grid.step()
        #expect(liveCells(grid) == Set(horizontal))
    }

    @Test("A glider translates by one cell diagonally every four generations")
    func gliderTranslates() {
        let grid = makeGrid(width: 40, height: 40, live: glider(x: 5, y: 5))
        for _ in 0..<4 { grid.step() }
        #expect(liveCells(grid) == Set(glider(x: 6, y: 6)))
        for _ in 0..<8 { grid.step() }
        #expect(liveCells(grid) == Set(glider(x: 8, y: 8)))
    }

    @Test("Generation counter advances and resets on load")
    func generationCounter() {
        let grid = LifeGrid(width: 76, height: 20)
        for _ in 0..<7 { grid.step() }
        #expect(grid.generation == 7)
        grid.load(CellBitmap(width: 76, height: 20))
        #expect(grid.generation == 0)
    }
}

@Suite("LifeGrid toroidal wrapping")
struct LifeGridWrapTests {

    @Test("A blinker spanning the left and right edges oscillates")
    func horizontalEdgeBlinker() {
        let width = 20
        let horizontal = [
            Coordinate(x: width - 1, y: 5), Coordinate(x: 0, y: 5), Coordinate(x: 1, y: 5),
        ]
        let vertical = [
            Coordinate(x: 0, y: 4), Coordinate(x: 0, y: 5), Coordinate(x: 0, y: 6),
        ]
        let grid = makeGrid(width: width, height: 20, live: horizontal)

        grid.step()
        #expect(liveCells(grid) == Set(vertical))
        grid.step()
        #expect(liveCells(grid) == Set(horizontal))
    }

    @Test("A blinker spanning the top and bottom edges oscillates")
    func verticalEdgeBlinker() {
        let height = 20
        let vertical = [
            Coordinate(x: 5, y: height - 1), Coordinate(x: 5, y: 0), Coordinate(x: 5, y: 1),
        ]
        let horizontal = [
            Coordinate(x: 4, y: 0), Coordinate(x: 5, y: 0), Coordinate(x: 6, y: 0),
        ]
        let grid = makeGrid(width: 20, height: height, live: vertical)

        grid.step()
        #expect(liveCells(grid) == Set(horizontal))
        grid.step()
        #expect(liveCells(grid) == Set(vertical))
    }

    @Test("A glider leaving the bottom-right corner reappears at the top-left")
    func gliderWrapsBothAxes() {
        let grid = makeGrid(width: 16, height: 16, live: glider(x: 12, y: 12))
        // Four cells of diagonal travel puts the bounding box back at the origin.
        for _ in 0..<16 { grid.step() }
        #expect(liveCells(grid) == Set(glider(x: 0, y: 0)))
    }
}

@Suite("LifeGrid word-boundary handling")
struct LifeGridWordBoundaryTests {

    @Test("A blinker straddling the 64-bit word boundary oscillates")
    func blinkerAcrossWordBoundary() {
        let horizontal = [Coordinate(x: 62, y: 5), Coordinate(x: 63, y: 5), Coordinate(x: 64, y: 5)]
        let vertical = [Coordinate(x: 63, y: 4), Coordinate(x: 63, y: 5), Coordinate(x: 63, y: 6)]
        let grid = makeGrid(width: 128, height: 20, live: horizontal)

        grid.step()
        #expect(liveCells(grid) == Set(vertical))
        grid.step()
        #expect(liveCells(grid) == Set(horizontal))
    }

    @Test("A glider crosses the word boundary intact", arguments: [70, 76, 128, 129])
    func gliderCrossesWordBoundary(width: Int) {
        let grid = makeGrid(width: width, height: 24, live: glider(x: 58, y: 4))
        for _ in 0..<20 { grid.step() }
        #expect(liveCells(grid) == Set(glider(x: 63, y: 9)))
    }

    @Test("No cells survive past the declared width", arguments: [65, 70, 76, 127, 129])
    func noStrayBitsPastWidth(width: Int) {
        let grid = makeGrid(width: width, height: 24, live: randomSoup(width: width, height: 24, seed: 0x2545_F491_4F6C_DD1D))
        for _ in 0..<40 {
            grid.step()
            // populationCount counts every bit in the backing words, so any bit
            // that leaked past `width` would make it exceed the visible count.
            #expect(grid.populationCount == liveCells(grid).count)
        }
    }

    @Test("A blinker at the very last column of a partial word wraps", arguments: [65, 70, 76, 127])
    func blinkerAtPartialWordEdge(width: Int) {
        let horizontal = [
            Coordinate(x: width - 2, y: 5), Coordinate(x: width - 1, y: 5), Coordinate(x: 0, y: 5),
        ]
        let vertical = [
            Coordinate(x: width - 1, y: 4),
            Coordinate(x: width - 1, y: 5),
            Coordinate(x: width - 1, y: 6),
        ]
        let grid = makeGrid(width: width, height: 20, live: horizontal)

        grid.step()
        #expect(liveCells(grid) == Set(vertical))
        grid.step()
        #expect(liveCells(grid) == Set(horizontal))
    }
}

@Suite("LifeGrid matches a naive implementation")
struct LifeGridReferenceTests {

    /// The strongest check available: run a dense soup for many generations and
    /// compare against a straightforward per-cell implementation. Widths are
    /// chosen to exercise exact, partial, and multi-word rows.
    @Test("Soup evolution matches the reference", arguments: [37, 64, 65, 76, 128, 130])
    func matchesNaiveStep(width: Int) {
        let height = 23
        let seed = randomSoup(width: width, height: height, seed: 0x9E37_79B9_7F4A_7C15)
        let grid = makeGrid(width: width, height: height, live: seed)
        var reference = Set(seed)

        for generation in 1...30 {
            grid.step()
            reference = naiveStep(reference, width: width, height: height)
            #expect(liveCells(grid) == reference, "diverged at generation \(generation), width \(width)")
        }
    }

    /// The empty-row fast path must not change the outcome on a tall, sparse grid.
    @Test("Row skipping does not change the outcome")
    func rowSkippingIsTransparent() {
        let width = 76
        let height = 160
        let seed = glider(x: 30, y: 78)
        let grid = makeGrid(width: width, height: height, live: seed)
        var reference = Set(seed)

        for _ in 0..<50 {
            grid.step()
            reference = naiveStep(reference, width: width, height: height)
        }
        #expect(liveCells(grid) == reference)
    }
}
