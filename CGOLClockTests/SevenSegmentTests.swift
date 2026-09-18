import CoreGraphics
import Foundation
import Testing
@testable import CGOLClock

@Suite("Seven-segment rendering")
struct SevenSegmentTests {
    let renderer = SevenSegmentRenderer()
    let metrics = GlyphMetrics.standard

    /// The `HH:MM` block must be exactly half of the 76-column grid.
    @Test("Block width is half the grid")
    func blockWidthIsHalfTheGrid() {
        #expect(metrics.blockWidth == 38)
        let layout = GridLayout(viewSize: CGSize(width: 402, height: 874))
        #expect(layout.columns == 76)
        #expect(Double(metrics.blockWidth) / Double(layout.columns) == 0.5)
    }

    @Test("Every digit draws the expected segment count")
    func digitsDrawExpectedSegments() {
        // A "1" lights only the two right verticals; an "8" lights everything.
        let one = renderer.seed(text: "1", columns: 40, rows: 20)
        let eight = renderer.seed(text: "8", columns: 40, rows: 20)
        #expect(one.populationCount < eight.populationCount)

        // Every lit cell of a "1" is also lit in an "8", since 8 is the union
        // of all seven segments.
        for y in 0..<20 {
            for x in 0..<40 where one[x, y] {
                #expect(eight[x, y], "cell \(x),\(y) lit in 1 but not in 8")
            }
        }
    }

    @Test("A 1 occupies only the right-hand verticals")
    func oneIsTwoVerticalBars() {
        let columns = 40
        let rows = 20
        let bitmap = renderer.seed(text: "1", columns: columns, rows: rows)
        let originX = (columns - metrics.blockWidth) / 2
        let originY = (rows - metrics.blockHeight) / 2

        // Segments b and c: a stroke-wide column at the right of the digit box,
        // running the full digit height.
        var expected = CellBitmap(width: columns, height: rows)
        expected.fill(
            x: originX + metrics.digitWidth - metrics.stroke,
            y: originY,
            width: metrics.stroke,
            height: metrics.digitHeight
        )
        #expect(bitmap == expected)
    }

    @Test("A 0 is a hollow box with no middle bar")
    func zeroHasNoMiddleBar() {
        let columns = 40
        let rows = 20
        let bitmap = renderer.seed(text: "0", columns: columns, rows: rows)
        let originX = (columns - metrics.blockWidth) / 2
        let originY = (rows - metrics.blockHeight) / 2
        let middleY = originY + (metrics.digitHeight - metrics.stroke) / 2

        // The centre of the middle row is dark, but the left and right walls
        // that pass through it are lit.
        #expect(!bitmap[originX + metrics.digitWidth / 2, middleY])
        #expect(bitmap[originX, middleY])
        #expect(bitmap[originX + metrics.digitWidth - 1, middleY])
    }

    @Test("A full HH:MM seed fits inside the block and is centred")
    func seedIsCentredAndBounded() {
        let columns = 76
        let rows = 40
        let bitmap = renderer.seed(text: "08:30", columns: columns, rows: rows)
        let originX = (columns - metrics.blockWidth) / 2
        let originY = (rows - metrics.blockHeight) / 2

        for y in 0..<rows {
            for x in 0..<columns where bitmap[x, y] {
                #expect(x >= originX && x < originX + metrics.blockWidth)
                #expect(y >= originY && y < originY + metrics.blockHeight)
            }
        }
        #expect(bitmap.populationCount > 0)
    }

    @Test("A blank leading hour does not shift the remaining digits")
    func blankLeadingDigitKeepsAlignment() {
        let withBlank = renderer.seed(text: " 9:05", columns: 76, rows: 40)
        let withZero = renderer.seed(text: "09:05", columns: 76, rows: 40)
        let zeroOnly = renderer.seed(text: "0", columns: 76, rows: 40)

        // The two differ by exactly the leading zero's cells.
        for y in 0..<40 {
            for x in 0..<76 where withBlank[x, y] != withZero[x, y] {
                #expect(zeroOnly[x, y], "difference at \(x),\(y) is not the leading zero")
            }
        }
    }
}

@Suite("Outline")
struct OutlineTests {

    @Test("The outline of a block is the ring around it, and never overlaps it")
    func outlineOfBlock() {
        var bitmap = CellBitmap(width: 20, height: 20)
        bitmap.fill(x: 5, y: 5, width: 3, height: 3)
        let outline = bitmap.outline()

        // A 3x3 square has a 5x5 ring around it: 25 - 9 = 16 cells.
        #expect(outline.populationCount == 16)
        #expect(outline[4, 4])
        #expect(outline[8, 8])
        #expect(!outline[6, 6], "outline must not cover the shape itself")

        for y in 0..<20 {
            for x in 0..<20 where bitmap[x, y] {
                #expect(!outline[x, y])
            }
        }
    }

    @Test("An empty bitmap has an empty outline")
    func emptyOutline() {
        #expect(CellBitmap(width: 20, height: 20).outline().populationCount == 0)
    }
}

@Suite("Grid layout")
struct GridLayoutTests {

    @Test(
        "Column count is fixed and cells grow with the screen",
        arguments: [
            CGSize(width: 402, height: 874),    // iPhone 17 Pro portrait
            CGSize(width: 1024, height: 1366),  // iPad Pro 13" portrait
            CGSize(width: 1366, height: 1024),  // iPad Pro 13" landscape
        ]
    )
    func layoutForScreen(size: CGSize) {
        let layout = GridLayout(viewSize: size)
        #expect(layout.columns == 76)
        #expect(layout.cellSize == size.width / 76)
        #expect(layout.rows >= GlyphMetrics.standard.blockHeight + 2)
        // The grid covers the full width and no more than the full height.
        #expect(abs(layout.pixelSize.width - size.width) < 0.001)
        #expect(layout.pixelSize.height <= size.height)
        #expect(layout.pixelSize.height > size.height - layout.cellSize)
    }

    @Test("A degenerate size still produces a usable grid")
    func degenerateSize() {
        let layout = GridLayout(viewSize: CGSize(width: 0, height: 0))
        #expect(layout.columns >= GlyphMetrics.standard.blockWidth + 2)
        #expect(layout.rows >= GlyphMetrics.standard.blockHeight + 2)
    }
}
