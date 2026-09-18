import CoreGraphics
import CoreText
import Foundation

/// Rasterises the time with a real font at the grid's own resolution.
///
/// This is the pixel-resolution counterpart to `DigitRenderer`. When a cell is
/// a single device pixel there is no reason to blow up an 8x14 bitmap — the
/// grid can carry proper letterforms, curves and all, and Life then erodes a
/// genuinely smooth shape.
///
/// The reverse doesn't work: thresholded at LED-matrix sizes a real font comes
/// out with one-cell strokes that die in a single generation, which is why the
/// bitmap faces still exist.
nonisolated struct TypeRenderer {
    var face: ClockFace

    /// Draws `text` centred on `centre`, scaled so its ink is `targetWidth`
    /// cells across.
    func seed(text: String, columns: Int, rows: Int, centre: CellPoint, targetWidth: Int) -> CellBitmap {
        var bitmap = CellBitmap(width: columns, height: rows)
        guard targetWidth > 0, !text.isEmpty else { return bitmap }

        // Measure at a reference size, then scale to the width we want. Doing
        // it by measurement rather than by point size keeps the clock the same
        // width whichever face is chosen.
        let reference: CGFloat = 200
        let referenceInk = inkBounds(of: text, font: face.font(ofSize: reference))
        guard referenceInk.width > 0, referenceInk.height > 0 else { return bitmap }

        let size = reference * CGFloat(targetWidth) / referenceInk.width
        let font = face.font(ofSize: size)
        let ink = inkBounds(of: text, font: font)

        // Core Graphics puts the origin at the bottom left, the grid puts row
        // zero at the top, and the first row in the buffer is the top one.
        let originX = CGFloat(centre.x) - ink.midX
        let originY = CGFloat(rows - centre.y) - ink.midY

        var pixels = [UInt8](repeating: 0, count: columns * rows)
        pixels.withUnsafeMutableBytes { raw in
            guard
                let context = CGContext(
                    data: raw.baseAddress,
                    width: columns,
                    height: rows,
                    bitsPerComponent: 8,
                    bytesPerRow: columns,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                )
            else { return }

            context.setAllowsAntialiasing(true)
            context.setFillColor(gray: 1, alpha: 1)
            context.textPosition = CGPoint(x: originX, y: originY)
            CTLineDraw(line(text, font: font), context)
        }

        // Only the rows and columns the text could have touched need scanning,
        // which matters when the grid runs to millions of cells.
        let drawn = ink.offsetBy(dx: originX, dy: originY)
        let minColumn = max(Int(drawn.minX.rounded(.down)) - 1, 0)
        let maxColumn = min(Int(drawn.maxX.rounded(.up)) + 1, columns - 1)
        // Flip the vertical span back into grid rows.
        let minRow = max(rows - Int(drawn.maxY.rounded(.up)) - 1, 0)
        let maxRow = min(rows - Int(drawn.minY.rounded(.down)) + 1, rows - 1)
        guard minColumn <= maxColumn, minRow <= maxRow else { return bitmap }

        for row in minRow...maxRow {
            let base = row * columns
            for column in minColumn...maxColumn where pixels[base + column] >= 128 {
                bitmap[column, row] = true
            }
        }
        return bitmap
    }

    private func line(_ text: String, font: CTFont) -> CTLine {
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                    CGColor(gray: 1, alpha: 1),
            ]
        )
        return CTLineCreateWithAttributedString(attributed)
    }

    /// The bounds of the drawn glyph outlines, relative to the text origin —
    /// not the typographic line box, which would include leading and leave the
    /// clock looking off-centre.
    private func inkBounds(of text: String, font: CTFont) -> CGRect {
        CTLineGetBoundsWithOptions(line(text, font: font), .useGlyphPathBounds)
    }
}
