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

@Suite("Seven-segment rendering")
struct SevenSegmentTests {
    let renderer = SevenSegmentRenderer()
    let metrics = GlyphMetrics.standard
    let centre = CellPoint(x: 38, y: 20)

    /// A full `HH:MM` block must be exactly half of the 76-column grid.
    @Test("Block width is half the grid")
    func blockWidthIsHalfTheGrid() {
        #expect(metrics.blockWidth == 38)
        let layout = GridLayout(viewSize: CGSize(width: 874, height: 402))
        #expect(layout.columns == 76)
        #expect(Double(metrics.blockWidth) / Double(layout.columns) == 0.5)
    }

    @Test("Every lit cell of a 1 is also lit in an 8")
    func oneIsSubsetOfEight() {
        let one = renderer.seed(text: "1", columns: 76, rows: 40, centre: centre)
        let eight = renderer.seed(text: "8", columns: 76, rows: 40, centre: centre)
        #expect(one.populationCount < eight.populationCount)

        for y in 0..<40 {
            for x in 0..<76 where one[x, y] {
                #expect(eight[x, y], "cell \(x),\(y) lit in 1 but not in 8")
            }
        }
    }

    @Test("A 1 is a single stroke-wide bar the full height of the digit")
    func oneIsOneVerticalBar() {
        let bitmap = renderer.seed(text: "1", columns: 76, rows: 40, centre: centre)
        let bounds = try! #require(litBounds(bitmap))
        #expect(bounds.maxX - bounds.minX + 1 == metrics.stroke)
        #expect(bounds.maxY - bounds.minY + 1 == metrics.digitHeight)
    }

    @Test("A 0 is a hollow box with no middle bar")
    func zeroHasNoMiddleBar() {
        let bitmap = renderer.seed(text: "0", columns: 76, rows: 40, centre: centre)
        let bounds = try! #require(litBounds(bitmap))
        let middleY = bounds.minY + (metrics.digitHeight - metrics.stroke) / 2

        // The middle row has lit walls but a dark interior.
        #expect(bitmap[bounds.minX, middleY])
        #expect(bitmap[bounds.maxX, middleY])
        #expect(!bitmap[bounds.minX + metrics.digitWidth / 2, middleY])
    }

    @Test("A full HH:MM occupies exactly the block width")
    func fullTimeFillsTheBlock() {
        let bitmap = renderer.seed(text: "08:30", columns: 76, rows: 40, centre: centre)
        let bounds = try! #require(litBounds(bitmap))
        #expect(bounds.maxX - bounds.minX + 1 == metrics.blockWidth)
        #expect(bounds.maxY - bounds.minY + 1 == metrics.digitHeight)
    }
}

@Suite("Centring")
struct CentringTests {
    let renderer = SevenSegmentRenderer()

    /// The drawn glyphs must straddle the requested centre, whether the time
    /// is a wide `08:30` or a narrow `9:45`. Centring a fixed five-slot block
    /// instead would push single-digit hours visibly to the right.
    ///
    /// Times whose outer digits are `1` are excluded deliberately — see
    /// `oneHugsTheRightOfItsSlot`.
    @Test("Digits are centred on the requested point", arguments: ["9:45", "08:30", "23:59", "07:20"])
    func digitsAreCentred(text: String) {
        let centre = CellPoint(x: 38, y: 20)
        let bitmap = renderer.seed(text: text, columns: 76, rows: 40, centre: centre)
        let bounds = try! #require(litBounds(bitmap))

        // Off by at most half a cell, since an odd width cannot be split evenly.
        let midX = Double(bounds.minX + bounds.maxX) / 2
        let midY = Double(bounds.minY + bounds.maxY) / 2
        #expect(abs(midX - Double(centre.x)) <= 1)
        #expect(abs(midY - Double(centre.y)) <= 1)
    }

    @Test("Moving the centre moves the digits by the same amount")
    func centreOffsetsTranslate() {
        let a = renderer.seed(text: "9:45", columns: 76, rows: 40, centre: CellPoint(x: 30, y: 20))
        let b = renderer.seed(text: "9:45", columns: 76, rows: 40, centre: CellPoint(x: 38, y: 24))
        let boundsA = try! #require(litBounds(a))
        let boundsB = try! #require(litBounds(b))

        #expect(boundsB.minX - boundsA.minX == 8)
        #expect(boundsB.minY - boundsA.minY == 4)
    }

    @Test("A narrow time is narrower than a wide one but shares a centre")
    func narrowTimeStaysCentred() {
        let centre = CellPoint(x: 38, y: 20)
        let wide = try! #require(litBounds(renderer.seed(text: "08:30", columns: 76, rows: 40, centre: centre)))
        let narrow = try! #require(litBounds(renderer.seed(text: "9:45", columns: 76, rows: 40, centre: centre)))

        #expect(narrow.maxX - narrow.minX < wide.maxX - wide.minX)
        #expect(narrow.minX > wide.minX)
        #expect(narrow.maxX < wide.maxX)
    }

    /// Slots are a fixed width, so a `1` — which lights only segments b and c —
    /// sits against the right of its slot instead of being re-centred. That
    /// keeps every other digit in the same place as the time changes, which
    /// matters here because the teal outline is a fixed ghost of the seed.
    @Test("Digit positions do not depend on which digits are shown")
    func slotPositionsAreStable() {
        let centre = CellPoint(x: 38, y: 20)
        let ones = renderer.seed(text: "11:11", columns: 76, rows: 40, centre: centre)
        let eights = renderer.seed(text: "88:88", columns: 76, rows: 40, centre: centre)
        let onesBounds = try! #require(litBounds(ones))
        let eightsBounds = try! #require(litBounds(eights))

        // Both end on the right edge of the last slot.
        #expect(onesBounds.maxX == eightsBounds.maxX)
        // The 1s start five columns into their slot, the width of the gap
        // between a digit's left edge and its right-hand vertical.
        #expect(onesBounds.minX - eightsBounds.minX == metrics.digitWidth - metrics.stroke)
    }

    @Test("A leading 1 shifts the lit pixels right by less than half a slot")
    func oneHugsTheRightOfItsSlot() {
        let centre = CellPoint(x: 38, y: 20)
        let bitmap = renderer.seed(text: "12:45", columns: 76, rows: 40, centre: centre)
        let bounds = try! #require(litBounds(bitmap))
        let midX = Double(bounds.minX + bounds.maxX) / 2

        #expect(midX > Double(centre.x))
        #expect(midX - Double(centre.x) < Double(metrics.digitWidth) / 2)
    }

    private var metrics: GlyphMetrics { .standard }

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
            CGSize(width: 874, height: 402),    // iPhone 17 Pro landscape
            CGSize(width: 1366, height: 1024),  // iPad Pro 13" landscape
            CGSize(width: 402, height: 874),    // portrait, just in case
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

    @Test("A safe-area centre maps to a cell inside the grid")
    func safeAreaCentreMapsIntoGrid() {
        let size = CGSize(width: 874, height: 402)
        let layout = GridLayout(viewSize: size)

        // iPhone landscape: notch on the leading edge pulls the safe centre right.
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
