import Foundation

/// Cell dimensions of the seven-segment digits.
///
/// `stroke` is deliberately 2 rather than 1. A one-cell-thick bar has too few
/// neighbours to survive and evaporates in a single generation; at two cells
/// thick the bars die back unevenly, shed gliders, and leave still-life blocks
/// behind — which is the whole point of the display.
nonisolated struct GlyphMetrics: Equatable {
    var digitWidth = 7
    var digitHeight = 14
    var stroke = 2
    var gap = 2
    var colonWidth = 2

    static let standard = GlyphMetrics()

    /// Cell width of an `HH:MM` block: four digits, a colon, and four gaps.
    var blockWidth: Int { 4 * digitWidth + colonWidth + 4 * gap }
    var blockHeight: Int { digitHeight }
}

/// Renders `HH:MM` into a `CellBitmap` as blocky seven-segment digits.
///
/// Segments are laid out parametrically rather than stored as a fixed font, so
/// the same code produces sensible digits at any `GlyphMetrics`.
nonisolated struct SevenSegmentRenderer {
    var metrics: GlyphMetrics = .standard

    /// Segment bits, in the conventional order a, b, c, d, e, f, g:
    ///
    ///      aaa
    ///     f   b
    ///      ggg
    ///     e   c
    ///      ddd
    private static let segmentMasks: [UInt8] = [
        0b0111111,  // 0
        0b0000110,  // 1
        0b1011011,  // 2
        0b1001111,  // 3
        0b1100110,  // 4
        0b1101101,  // 5
        0b1111101,  // 6
        0b0000111,  // 7
        0b1111111,  // 8
        0b1101111,  // 9
    ]

    /// Draws `text` into a `columns` x `rows` bitmap with the centre of the
    /// *drawn* glyphs at `centre`.
    ///
    /// Centring the drawn extent rather than a fixed five-slot block matters:
    /// a single-digit hour would otherwise sit visibly right of centre.
    /// Characters other than `0...9` and `:` advance the cursor without
    /// drawing, so callers can still reserve blank slots if they want to.
    func seed(text: String, columns: Int, rows: Int, centre: CellPoint) -> CellBitmap {
        var bitmap = CellBitmap(width: columns, height: rows)
        let span = drawnSpan(of: text)
        let originX = centre.x - span.width / 2 - span.start
        let originY = centre.y - metrics.blockHeight / 2

        var x = originX
        for character in text {
            switch character {
            case "0"..."9":
                let digit = Int(character.asciiValue! - UInt8(ascii: "0"))
                draw(digit: digit, at: x, y: originY, into: &bitmap)
                x += metrics.digitWidth + metrics.gap
            case ":":
                drawColon(at: x, y: originY, into: &bitmap)
                x += metrics.colonWidth + metrics.gap
            default:
                x += metrics.digitWidth + metrics.gap
            }
        }
        return bitmap
    }

    /// Where the drawn glyphs start relative to the first slot, and how wide
    /// they are. Leading and trailing blank slots contribute nothing.
    func drawnSpan(of text: String) -> (start: Int, width: Int) {
        var offset = 0
        var start: Int?
        var end = 0

        for character in text {
            let glyphWidth: Int? = switch character {
            case "0"..."9": metrics.digitWidth
            case ":": metrics.colonWidth
            default: nil
            }
            if let glyphWidth {
                if start == nil { start = offset }
                end = offset + glyphWidth
            }
            offset += (character == ":" ? metrics.colonWidth : metrics.digitWidth) + metrics.gap
        }

        guard let start else { return (0, 0) }
        return (start, end - start)
    }

    private func draw(digit: Int, at x: Int, y: Int, into bitmap: inout CellBitmap) {
        let mask = Self.segmentMasks[digit]
        let w = metrics.digitWidth
        let h = metrics.digitHeight
        let t = metrics.stroke
        // Middle segment sits so the upper and lower halves are equal.
        let middleY = (h - t) / 2

        if mask & 0b0000001 != 0 { bitmap.fill(x: x, y: y, width: w, height: t) }
        if mask & 0b0000010 != 0 {
            bitmap.fill(x: x + w - t, y: y, width: t, height: middleY + t)
        }
        if mask & 0b0000100 != 0 {
            bitmap.fill(x: x + w - t, y: y + middleY, width: t, height: h - middleY)
        }
        if mask & 0b0001000 != 0 { bitmap.fill(x: x, y: y + h - t, width: w, height: t) }
        if mask & 0b0010000 != 0 {
            bitmap.fill(x: x, y: y + middleY, width: t, height: h - middleY)
        }
        if mask & 0b0100000 != 0 { bitmap.fill(x: x, y: y, width: t, height: middleY + t) }
        if mask & 0b1000000 != 0 { bitmap.fill(x: x, y: y + middleY, width: w, height: t) }
    }

    private func drawColon(at x: Int, y: Int, into bitmap: inout CellBitmap) {
        let size = metrics.colonWidth
        bitmap.fill(x: x, y: y + metrics.digitHeight / 3 - size / 2, width: size, height: size)
        bitmap.fill(x: x, y: y + 2 * metrics.digitHeight / 3 - size / 2, width: size, height: size)
    }
}

/// Formats the time as the five characters the renderer expects.
nonisolated enum ClockText {

    /// `HH:MM` for `date`, honouring the locale's 12- or 24-hour preference.
    /// 12-hour times drop the leading zero entirely — the renderer centres
    /// whatever it is given, so a narrower `9:45` still sits in the middle.
    static func string(for date: Date, locale: Locale = .current, calendar: Calendar = .current) -> String {
        var hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)

        if !uses24HourTime(locale: locale) {
            hour %= 12
            if hour == 0 { hour = 12 }
            return "\(hour):\(twoDigits(minute))"
        }
        return "\(twoDigits(hour)):\(twoDigits(minute))"
    }

    static func uses24HourTime(locale: Locale = .current) -> Bool {
        let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "H"
        return !template.contains("a")
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
