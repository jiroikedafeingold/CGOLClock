import Foundation

/// Shared geometry for the hand-drawn 8x14 bitmap digits. The glyph data
/// itself lives on `ClockFace`, which carries one set per typeface.
///
/// Strokes are two cells thick in every face. A one-cell stroke has too few
/// neighbours to survive and evaporates in a single generation.
nonisolated enum DigitFont {
    static let width = 8
    static let height = 14

    /// Turns ASCII art into row bitmasks, bit 0 being the leftmost column.
    static func parse(_ patterns: [[String]]) -> [[UInt8]] {
        patterns.map { rows in
            rows.map { row in
                var mask: UInt8 = 0
                for (column, character) in row.enumerated() where character == "#" {
                    mask |= UInt8(1) << UInt8(column)
                }
                return mask
            }
        }
    }
}

nonisolated struct GlyphMetrics: Equatable {
    var baseGap = 2
    var baseColonWidth = 3
    /// Grid cells per font cell.
    var scale = 1

    static let standard = GlyphMetrics()

    /// Block width at `scale` 1, which fixes the grid's column count.
    static var baseBlockWidth: Int { GlyphMetrics().blockWidth }

    var gap: Int { baseGap * scale }
    var colonWidth: Int { baseColonWidth * scale }
    var digitWidth: Int { DigitFont.width * scale }
    var digitHeight: Int { DigitFont.height * scale }

    /// Cell width of an `HH:MM` block: four digits, a colon, and four gaps.
    var blockWidth: Int { 4 * digitWidth + colonWidth + 4 * gap }
    var blockHeight: Int { digitHeight }

    func scaled(to scale: Int) -> GlyphMetrics {
        var copy = self
        copy.scale = max(1, scale)
        return copy
    }
}

/// Stamps `HH:MM` into a `CellBitmap`.
nonisolated struct DigitRenderer {
    var metrics: GlyphMetrics = .standard
    var face: ClockFace = .round

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
        let scale = metrics.scale
        for (row, mask) in face.glyphs[digit].enumerated() {
            var bits = mask
            while bits != 0 {
                let column = bits.trailingZeroBitCount
                bits &= bits - 1
                bitmap.fill(
                    x: x + column * scale,
                    y: y + row * scale,
                    width: scale,
                    height: scale
                )
            }
        }
    }

    private func drawColon(at x: Int, y: Int, into bitmap: inout CellBitmap) {
        let dot = metrics.colonWidth
        let height = metrics.digitHeight
        bitmap.fill(x: x, y: y + height / 3 - dot / 2, width: dot, height: dot)
        bitmap.fill(x: x, y: y + 2 * height / 3 - dot / 2, width: dot, height: dot)
    }
}

/// Formats the time as the characters the renderer expects.
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
