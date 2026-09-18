import CoreGraphics
import Foundation
import Testing
@testable import CGOLClock

/// Reads a rendered frame back out so we can assert on actual texels.
struct RenderedFrame {
    let width: Int
    let height: Int
    private let texels: [UInt32]

    init(_ image: CGImage) {
        let imageWidth = image.width
        let imageHeight = image.height
        let bytesPerRow = image.bytesPerRow
        let data = image.dataProvider!.data! as Data

        var decoded = [UInt32](repeating: 0, count: imageWidth * imageHeight)
        data.withUnsafeBytes { raw in
            for y in 0..<imageHeight {
                let row = raw.baseAddress!.advanced(by: y * bytesPerRow)
                    .assumingMemoryBound(to: UInt32.self)
                for x in 0..<imageWidth {
                    decoded[y * imageWidth + x] = row[x]
                }
            }
        }

        width = imageWidth
        height = imageHeight
        texels = decoded
    }

    /// Ignores the alpha byte, which the context is told to skip.
    subscript(x: Int, y: Int) -> UInt32 {
        texels[y * width + x] & 0x00FF_FFFF
    }
}

private let palette = Palette.amberLED
private let background = palette.background.packed & 0x00FF_FFFF
private let live = palette.live.packed & 0x00FF_FFFF
private let ghost = palette.outlineOverBackground.packed & 0x00FF_FFFF

@Suite("Frame rasteriser")
struct FrameRasterizerTests {
    let columns = 12
    let rows = 8
    /// Matches the rasteriser's defaults so texel maths lines up.
    let texelsPerCell = 8
    let litSize = 6

    private func render(live liveCells: [CellPoint], outline outlineCells: [CellPoint]) -> RenderedFrame {
        let grid = LifeGrid(width: columns, height: rows)
        for cell in liveCells { grid[cell.x, cell.y] = true }

        var outline = CellBitmap(width: columns, height: rows)
        for cell in outlineCells { outline[cell.x, cell.y] = true }

        let rasterizer = FrameRasterizer(columns: columns, rows: rows)
        rasterizer.setOutline(outline)
        return RenderedFrame(rasterizer.image(for: grid)!)
    }

    @Test("The image is one texel block per cell")
    func imageSize() {
        let frame = render(live: [], outline: [])
        #expect(frame.width == columns * texelsPerCell)
        #expect(frame.height == rows * texelsPerCell)
    }

    @Test("An empty grid with no outline is pure background")
    func emptyIsBackground() {
        let frame = render(live: [], outline: [])
        for y in 0..<frame.height {
            for x in 0..<frame.width {
                #expect(frame[x, y] == background)
            }
        }
    }

    @Test("A live cell is a filled square with a gutter around it")
    func liveCellIsFilled() {
        let frame = render(live: [CellPoint(x: 3, y: 2)], outline: [])
        let left = 3 * texelsPerCell
        let top = 2 * texelsPerCell

        for row in 0..<litSize {
            for column in 0..<litSize {
                #expect(frame[left + column, top + row] == live)
            }
        }
        // The gutter row and column stay dark.
        #expect(frame[left + litSize, top] == background)
        #expect(frame[left, top + litSize] == background)
    }

    /// The point of the change: the ghost is a hollow square, not a filled one.
    @Test("An outline cell is a hollow ring with a dark centre")
    func outlineCellIsHollow() {
        let frame = render(live: [], outline: [CellPoint(x: 4, y: 3)])
        let left = 4 * texelsPerCell
        let top = 3 * texelsPerCell
        let last = litSize - 1

        // Every texel on the perimeter is ghost coloured.
        for offset in 0..<litSize {
            #expect(frame[left + offset, top] == ghost, "top edge at \(offset)")
            #expect(frame[left + offset, top + last] == ghost, "bottom edge at \(offset)")
            #expect(frame[left, top + offset] == ghost, "left edge at \(offset)")
            #expect(frame[left + last, top + offset] == ghost, "right edge at \(offset)")
        }
        // The interior is not.
        for row in 1..<last {
            for column in 1..<last {
                #expect(frame[left + column, top + row] == background, "interior \(column),\(row)")
            }
        }
    }

    /// The reason the ring is stroked last rather than baked into a template.
    @Test("The ghost ring stays visible where a live cell shares the cell")
    func ghostSurvivesALiveCell() {
        let cell = CellPoint(x: 5, y: 4)
        let frame = render(live: [cell], outline: [cell])
        let left = cell.x * texelsPerCell
        let top = cell.y * texelsPerCell
        let last = litSize - 1

        // Ring still teal...
        for offset in 0..<litSize {
            #expect(frame[left + offset, top] == ghost)
            #expect(frame[left + offset, top + last] == ghost)
            #expect(frame[left, top + offset] == ghost)
            #expect(frame[left + last, top + offset] == ghost)
        }
        // ...and the live cell shows through the middle.
        for row in 1..<last {
            for column in 1..<last {
                #expect(frame[left + column, top + row] == live, "interior \(column),\(row)")
            }
        }
    }

    @Test("The ghost and live colours are actually distinguishable")
    func coloursDiffer() {
        #expect(ghost != background)
        #expect(ghost != live)
        #expect(live != background)
    }

    @Test("Re-setting the outline replaces the previous one")
    func outlineIsReplaced() {
        let rasterizer = FrameRasterizer(columns: columns, rows: rows)
        let grid = LifeGrid(width: columns, height: rows)

        var first = CellBitmap(width: columns, height: rows)
        first[2, 2] = true
        rasterizer.setOutline(first)

        var second = CellBitmap(width: columns, height: rows)
        second[7, 5] = true
        rasterizer.setOutline(second)

        let frame = RenderedFrame(rasterizer.image(for: grid)!)
        #expect(frame[2 * texelsPerCell, 2 * texelsPerCell] == background, "stale outline left behind")
        #expect(frame[7 * texelsPerCell, 5 * texelsPerCell] == ghost)
    }
}
