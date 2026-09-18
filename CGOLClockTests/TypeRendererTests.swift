import CoreGraphics
import Foundation
import Testing
@testable import CGOLClock

@Suite("Real-font rendering")
struct TypeRendererTests {
    /// Roughly an iPhone 17 Pro landscape grid at pixel resolution, shrunk
    /// enough to keep the tests quick.
    let columns = 1200
    let rows = 560
    var centre: CellPoint { CellPoint(x: columns / 2, y: rows / 2) }
    var targetWidth: Int { columns / 2 }

    private func render(_ text: String, face: ClockFace = .round) -> CellBitmap {
        TypeRenderer(face: face).seed(
            text: text,
            columns: columns,
            rows: rows,
            centre: centre,
            targetWidth: targetWidth
        )
    }

    @Test("Text is rasterised to about the requested width", arguments: ClockFace.allCases)
    func widthMatchesRequest(face: ClockFace) {
        let bounds = try! #require(litBounds(render("10:48", face: face)))
        let width = bounds.maxX - bounds.minX + 1
        // Within a couple of cells of the target, allowing for rounding and
        // the difference between the measured and rasterised outline.
        #expect(abs(width - targetWidth) <= 4, "\(face) drew \(width), wanted \(targetWidth)")
    }

    @Test("Text is centred on the requested point", arguments: ClockFace.allCases)
    func centredOnRequestedPoint(face: ClockFace) {
        let bounds = try! #require(litBounds(render("10:48", face: face)))
        let midX = Double(bounds.minX + bounds.maxX) / 2
        let midY = Double(bounds.minY + bounds.maxY) / 2
        #expect(abs(midX - Double(centre.x)) <= 2)
        #expect(abs(midY - Double(centre.y)) <= 2)
    }

    /// The reason this renderer exists: at pixel resolution the glyphs should
    /// be genuine letterforms, not an 8x14 bitmap blown up. A scaled bitmap has
    /// runs that are exact multiples of the scale factor; real type does not.
    @Test("Strokes are not quantised to a blown-up bitmap")
    func strokesAreNotBlocky() {
        let bitmap = render("10:48")
        let bounds = try! #require(litBounds(bitmap))

        var runLengths: Set<Int> = []
        for y in bounds.minY...bounds.maxY {
            var run = 0
            for x in bounds.minX...(bounds.maxX + 1) {
                if x <= bounds.maxX && bitmap[x, y] {
                    run += 1
                } else if run > 0 {
                    runLengths.insert(run)
                    run = 0
                }
            }
        }
        // A 30x-scaled bitmap would only ever produce a handful of distinct
        // run lengths, all multiples of 30.
        #expect(runLengths.count > 20, "only \(runLengths.count) distinct stroke widths — looks quantised")
    }

    /// Curves and diagonals mean the left edge should wander, unlike the
    /// stepped edges of a scaled bitmap.
    @Test("Outlines are smooth rather than stepped")
    func outlinesAreSmooth() {
        let bitmap = render("0")
        let bounds = try! #require(litBounds(bitmap))

        var leftEdges: [Int] = []
        for y in bounds.minY...bounds.maxY {
            for x in bounds.minX...bounds.maxX where bitmap[x, y] {
                leftEdges.append(x)
                break
            }
        }
        // A round glyph's left edge takes many distinct positions down its height.
        #expect(Set(leftEdges).count > 15, "left edge only takes \(Set(leftEdges).count) positions")
    }

    @Test("Every digit and the colon render something", arguments: Array("0123456789:"))
    func everyCharacterDraws(character: Character) {
        #expect(litBounds(render(String(character))) != nil, "\(character) drew nothing")
    }

    @Test("The two faces are visibly different")
    func facesDiffer() {
        let round = render("10:48", face: .round)
        let block = render("10:48", face: .block)

        var differing = 0
        for y in 0..<rows {
            for x in 0..<columns where round[x, y] != block[x, y] {
                differing += 1
            }
        }
        #expect(differing > 1000, "the faces differ by only \(differing) cells")
    }

    @Test("A degenerate target width draws nothing rather than crashing")
    func zeroWidthIsSafe() {
        let bitmap = TypeRenderer(face: .round).seed(
            text: "10:48", columns: columns, rows: rows, centre: centre, targetWidth: 0
        )
        #expect(bitmap.populationCount == 0)
    }

    @Test("Empty text draws nothing")
    func emptyTextIsSafe() {
        #expect(render("").populationCount == 0)
    }

    @Test("Nothing is drawn outside the grid")
    func staysInsideTheGrid() {
        // A target far wider than the grid must still be clipped safely.
        let bitmap = TypeRenderer(face: .round).seed(
            text: "88:88",
            columns: columns,
            rows: rows,
            centre: centre,
            targetWidth: columns * 3
        )
        #expect(bitmap.populationCount > 0)
        let bounds = try! #require(litBounds(bitmap))
        #expect(bounds.minX >= 0 && bounds.maxX < columns)
        #expect(bounds.minY >= 0 && bounds.maxY < rows)
    }
}
