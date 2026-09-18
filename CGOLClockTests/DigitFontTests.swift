import CoreGraphics
import Foundation
import Testing
@testable import CGOLClock

/// Bounding box of the lit cells, or `nil` if nothing is lit.
func litBounds(_ bitmap: CellBitmap) -> (minX: Int, maxX: Int, minY: Int, maxY: Int)? {
    var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
    for y in 0..<bitmap.height {
        for x in 0..<bitmap.width where bitmap[x, y] {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    return minX <= maxX ? (minX, maxX, minY, maxY) : nil
}

/// A digit rendered on its own, as a grid of booleans in glyph coordinates.
func glyphCells(_ digit: Int) -> [[Bool]] {
    DigitFont.glyphs[digit].map { mask in
        (0..<DigitFont.width).map { mask & (UInt8(1) << UInt8($0)) != 0 }
    }
}

@Suite("Digit font")
struct DigitFontTests {

    @Test("Every glyph is the declared size")
    func glyphsAreWellFormed() {
        #expect(DigitFont.glyphs.count == 10)
        for digit in 0...9 {
            let rows = DigitFont.glyphs[digit]
            #expect(rows.count == DigitFont.height, "digit \(digit) has \(rows.count) rows")
            for (index, mask) in rows.enumerated() {
                // Nothing may spill past the declared width.
                let overflow = mask >> UInt8(DigitFont.width)
                #expect(overflow == 0, "digit \(digit) row \(index) spills past the glyph")
            }
        }
    }

    @Test("Every digit draws something, and none is blank or solid")
    func glyphsHaveContent() {
        for digit in 0...9 {
            let lit = DigitFont.glyphs[digit].reduce(0) { $0 + $1.nonzeroBitCount }
            #expect(lit > 0, "digit \(digit) is blank")
            #expect(lit < DigitFont.width * DigitFont.height, "digit \(digit) is solid")
        }
    }

    @Test("Every digit spans the full glyph height")
    func glyphsAreFullHeight() {
        for digit in 0...9 {
            let rows = DigitFont.glyphs[digit]
            #expect(rows.first != 0, "digit \(digit) has a blank top row")
            #expect(rows.last != 0, "digit \(digit) has a blank bottom row")
        }
    }

    /// Every digit must be distinguishable from every other, or the clock is
    /// unreadable. Cheap proxy: no two glyphs are identical, and no pair
    /// differs by only a cell or two.
    @Test("All ten digits are clearly distinct")
    func digitsAreDistinct() {
        for a in 0..<9 {
            for b in (a + 1)..<10 {
                let differing = zip(DigitFont.glyphs[a], DigitFont.glyphs[b])
                    .reduce(0) { $0 + ($1.0 ^ $1.1).nonzeroBitCount }
                #expect(differing >= 6, "digits \(a) and \(b) differ by only \(differing) cells")
            }
        }
    }

    /// The point of replacing the seven-segment renderer. Seven-segment glyphs
    /// are all axis-aligned bars, so every one is near-symmetric and they decay
    /// alike. These shapes should not be.
    @Test("The font is not left-right symmetric")
    func fontHasHorizontalVariation() {
        func isMirrored(_ digit: Int) -> Bool {
            DigitFont.glyphs[digit].allSatisfy { mask in
                var reversed: UInt8 = 0
                for column in 0..<DigitFont.width where mask & (UInt8(1) << UInt8(column)) != 0 {
                    reversed |= UInt8(1) << UInt8(DigitFont.width - 1 - column)
                }
                return reversed == mask
            }
        }
        let mirrored = (0...9).filter(isMirrored)
        // 0 and 8 are legitimately symmetric; the rest should not be.
        #expect(mirrored.count <= 2, "too many mirror-symmetric digits: \(mirrored)")
    }

    @Test("The font is not top-bottom symmetric")
    func fontHasVerticalVariation() {
        let flipped = (0...9).filter { DigitFont.glyphs[$0] == DigitFont.glyphs[$0].reversed() }
        #expect(flipped.count <= 2, "too many flip-symmetric digits: \(flipped)")
    }

    /// One-cell strokes evaporate in a single generation, so every lit cell
    /// should have a lit neighbour to lean on.
    @Test("No digit has an isolated single cell")
    func strokesAreThickEnough() {
        for digit in 0...9 {
            let cells = glyphCells(digit)
            for y in 0..<DigitFont.height {
                for x in 0..<DigitFont.width where cells[y][x] {
                    var neighbours = 0
                    for dy in -1...1 {
                        for dx in -1...1 where !(dx == 0 && dy == 0) {
                            let ny = y + dy, nx = x + dx
                            guard ny >= 0, ny < DigitFont.height, nx >= 0, nx < DigitFont.width else { continue }
                            if cells[ny][nx] { neighbours += 1 }
                        }
                    }
                    #expect(neighbours >= 2, "digit \(digit) cell \(x),\(y) has \(neighbours) neighbours")
                }
            }
        }
    }
}

@Suite("Digit rendering")
struct DigitRenderingTests {
    let renderer = DigitRenderer()
    let metrics = GlyphMetrics.standard
    let centre = CellPoint(x: 43, y: 20)

    /// A full `HH:MM` block must be exactly half of the grid.
    @Test("Block width is half the grid")
    func blockWidthIsHalfTheGrid() {
        let layout = GridLayout(viewSize: CGSize(width: 874, height: 402))
        #expect(layout.columns == 2 * metrics.blockWidth)
        #expect(Double(metrics.blockWidth) / Double(layout.columns) == 0.5)
    }

    @Test("A rendered digit matches its glyph")
    func renderedDigitMatchesGlyph() {
        for digit in 0...9 {
            let bitmap = renderer.seed(text: "\(digit)", columns: 86, rows: 40, centre: centre)
            let bounds = try! #require(litBounds(bitmap), "digit \(digit) drew nothing")
            let cells = glyphCells(digit)

            // The glyph's own bounding box, so we can line the two up.
            var glyphMinX = DigitFont.width, glyphMinY = DigitFont.height
            for y in 0..<DigitFont.height {
                for x in 0..<DigitFont.width where cells[y][x] {
                    glyphMinX = min(glyphMinX, x); glyphMinY = min(glyphMinY, y)
                }
            }
            for y in 0..<DigitFont.height {
                for x in 0..<DigitFont.width {
                    let drawn = bitmap[bounds.minX - glyphMinX + x, bounds.minY - glyphMinY + y]
                    #expect(drawn == cells[y][x], "digit \(digit) mismatch at \(x),\(y)")
                }
            }
        }
    }

    @Test("A full HH:MM occupies exactly the block width")
    func fullTimeFillsTheBlock() {
        let bitmap = renderer.seed(text: "08:30", columns: 86, rows: 40, centre: centre)
        let bounds = try! #require(litBounds(bitmap))
        #expect(bounds.maxX - bounds.minX + 1 == metrics.blockWidth)
        #expect(bounds.maxY - bounds.minY + 1 == metrics.digitHeight)
    }

    @Test("The colon draws two separated dots")
    func colonIsTwoDots() {
        let bitmap = renderer.seed(text: ":", columns: 86, rows: 40, centre: centre)
        let bounds = try! #require(litBounds(bitmap))
        #expect(bounds.maxX - bounds.minX + 1 == metrics.colonWidth)

        // There is at least one blank row between the two dots.
        var blankRows = 0
        for y in bounds.minY...bounds.maxY {
            let rowIsEmpty = (bounds.minX...bounds.maxX).allSatisfy { !bitmap[$0, y] }
            if rowIsEmpty { blankRows += 1 }
        }
        #expect(blankRows > 0, "the colon dots are touching")
    }
}

@Suite("Centring")
struct CentringTests {
    let renderer = DigitRenderer()
    let metrics = GlyphMetrics.standard

    @Test("Digits are centred on the requested point", arguments: ["9:45", "08:30", "23:59", "07:20"])
    func digitsAreCentred(text: String) {
        let centre = CellPoint(x: 43, y: 20)
        let bitmap = renderer.seed(text: text, columns: 86, rows: 40, centre: centre)
        let bounds = try! #require(litBounds(bitmap))

        let midX = Double(bounds.minX + bounds.maxX) / 2
        let midY = Double(bounds.minY + bounds.maxY) / 2
        #expect(abs(midX - Double(centre.x)) <= 1)
        #expect(abs(midY - Double(centre.y)) <= 1)
    }

    @Test("Moving the centre moves the digits by the same amount")
    func centreOffsetsTranslate() {
        let a = renderer.seed(text: "9:45", columns: 86, rows: 40, centre: CellPoint(x: 35, y: 20))
        let b = renderer.seed(text: "9:45", columns: 86, rows: 40, centre: CellPoint(x: 43, y: 24))
        let boundsA = try! #require(litBounds(a))
        let boundsB = try! #require(litBounds(b))

        #expect(boundsB.minX - boundsA.minX == 8)
        #expect(boundsB.minY - boundsA.minY == 4)
    }

    @Test("A narrow time is narrower than a wide one but shares a centre")
    func narrowTimeStaysCentred() {
        let centre = CellPoint(x: 43, y: 20)
        let wide = try! #require(litBounds(renderer.seed(text: "08:30", columns: 86, rows: 40, centre: centre)))
        let narrow = try! #require(litBounds(renderer.seed(text: "9:45", columns: 86, rows: 40, centre: centre)))

        #expect(narrow.maxX - narrow.minX < wide.maxX - wide.minX)
        #expect(narrow.minX > wide.minX)
        #expect(narrow.maxX < wide.maxX)
    }

    /// Slots are a fixed width so digit positions don't shift as the time
    /// changes, which matters when the ghost is a fixed record of the seed.
    ///
    /// Ink bounds are not identical across digits — a `1` doesn't reach the
    /// edges of its slot the way an `8` does — so the guarantee is about slot
    /// geometry, with ink staying inside by less than a stroke.
    @Test("Digit positions do not depend on which digits are shown")
    func slotPositionsAreStable() {
        let centre = CellPoint(x: 43, y: 20)
        #expect(renderer.drawnSpan(of: "11:11") == renderer.drawnSpan(of: "88:88"))

        let ones = renderer.seed(text: "11:11", columns: 86, rows: 40, centre: centre)
        let eights = renderer.seed(text: "88:88", columns: 86, rows: 40, centre: centre)
        let onesBounds = try! #require(litBounds(ones))
        let eightsBounds = try! #require(litBounds(eights))

        #expect(abs(onesBounds.minX - eightsBounds.minX) <= 2)
        #expect(abs(onesBounds.maxX - eightsBounds.maxX) <= 2)
        #expect(onesBounds.minY == eightsBounds.minY)
        #expect(onesBounds.maxY == eightsBounds.maxY)
    }

    @Test("Blank slots do not contribute to the drawn span")
    func blankSlotsAreIgnored() {
        let padded = renderer.drawnSpan(of: " 9:45 ")
        let bare = renderer.drawnSpan(of: "9:45")
        #expect(padded.width == bare.width)
        #expect(padded.start > bare.start)
    }
}

@Suite("Clock text")
struct ClockTextTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(hour: Int, minute: Int) -> Date {
        calendar.date(from: DateComponents(timeZone: calendar.timeZone, hour: hour, minute: minute))!
    }

    @Test("24-hour locales pad the hour")
    func twentyFourHour() {
        let locale = Locale(identifier: "en_GB")
        #expect(ClockText.uses24HourTime(locale: locale))
        #expect(ClockText.string(for: date(hour: 9, minute: 5), locale: locale, calendar: calendar) == "09:05")
        #expect(ClockText.string(for: date(hour: 0, minute: 0), locale: locale, calendar: calendar) == "00:00")
        #expect(ClockText.string(for: date(hour: 23, minute: 59), locale: locale, calendar: calendar) == "23:59")
    }

    @Test("12-hour locales drop the leading zero and wrap midnight to 12")
    func twelveHour() {
        let locale = Locale(identifier: "en_US")
        #expect(!ClockText.uses24HourTime(locale: locale))
        #expect(ClockText.string(for: date(hour: 9, minute: 5), locale: locale, calendar: calendar) == "9:05")
        #expect(ClockText.string(for: date(hour: 0, minute: 0), locale: locale, calendar: calendar) == "12:00")
        #expect(ClockText.string(for: date(hour: 13, minute: 7), locale: locale, calendar: calendar) == "1:07")
        #expect(ClockText.string(for: date(hour: 12, minute: 30), locale: locale, calendar: calendar) == "12:30")
    }
}

@Suite("Grid layout")
struct GridLayoutTests {

    @Test(
        "Column count is fixed and cells grow with the screen",
        arguments: [
            CGSize(width: 874, height: 402),    // iPhone 17 Pro landscape
            CGSize(width: 1366, height: 1024),  // iPad Pro 13" landscape
            CGSize(width: 402, height: 874),    // portrait, just in case
        ]
    )
    func layoutForScreen(size: CGSize) {
        let columns = 2 * GlyphMetrics.standard.blockWidth
        let layout = GridLayout(viewSize: size)
        #expect(layout.columns == columns)
        #expect(layout.cellSize == size.width / CGFloat(columns))
        #expect(layout.rows >= GlyphMetrics.standard.blockHeight + 2)
        // The grid covers the full width and no more than the full height.
        #expect(abs(layout.pixelSize.width - size.width) < 0.001)
        #expect(layout.pixelSize.height <= size.height)
        #expect(layout.pixelSize.height > size.height - layout.cellSize)
    }

    @Test("A safe-area centre maps to a cell inside the grid")
    func safeAreaCentreMapsIntoGrid() {
        let size = CGSize(width: 874, height: 402)
        let layout = GridLayout(viewSize: size)

        // iPhone landscape: symmetric side insets, home indicator at the bottom.
        let safeRect = CGRect(x: 59, y: 0, width: 874 - 59 - 59, height: 402 - 21)
        let centre = layout.cell(at: CGPoint(x: safeRect.midX, y: safeRect.midY))
        #expect(centre.x == layout.cell(at: CGPoint(x: size.width / 2, y: 0)).x)
        #expect(centre.y < layout.cell(at: CGPoint(x: 0, y: size.height / 2)).y)
    }

    @Test("Points outside the grid clamp to its edges")
    func cellLookupClamps() {
        let layout = GridLayout(viewSize: CGSize(width: 874, height: 402))
        #expect(layout.cell(at: CGPoint(x: -500, y: -500)) == CellPoint(x: 0, y: 0))
        let far = layout.cell(at: CGPoint(x: 99_999, y: 99_999))
        #expect(far == CellPoint(x: layout.columns - 1, y: layout.rows - 1))
    }

    @Test("A degenerate size still produces a usable grid")
    func degenerateSize() {
        let layout = GridLayout(viewSize: CGSize(width: 0, height: 0))
        #expect(layout.columns >= GlyphMetrics.standard.blockWidth + 2)
        #expect(layout.rows >= GlyphMetrics.standard.blockHeight + 2)
    }
}
