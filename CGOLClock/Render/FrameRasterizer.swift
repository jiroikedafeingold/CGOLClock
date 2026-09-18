import CoreGraphics

/// Turns a `LifeGrid` into a `CGImage`, one texel block per cell.
///
/// The image is tiny — a few hundred texels on a side — and the view scales it
/// up with nearest-neighbour filtering, so the GPU does the magnification and
/// the pixels stay hard-edged. Each cell becomes a `texelsPerCell` square with
/// a `litSize` square drawn inside it; the leftover row and column form the
/// dark gutter that gives the LED-matrix look.
///
/// Drawing order per frame is background, then live cells, then the ghost.
/// The ghost marks the cells the digits started from, and goes last, stroked
/// as a hollow ring rather than filled — so a cell that is still alive reads
/// as an amber square inside a teal frame, and one that has died reads as an
/// empty teal frame.
nonisolated final class FrameRasterizer {
    let columns: Int
    let rows: Int

    private let texelsPerCell: Int
    private let litSize: Int
    private let pixelWidth: Int
    private let pixelHeight: Int
    private let texelCount: Int

    private let backgroundColor: UInt32
    private let liveColor: UInt32
    private let ghostColor: UInt32

    /// Row-major indices of the cells the digits started from, rebuilt once
    /// per minute.
    private var ghostCells: [Int] = []

    private let frame: UnsafeMutablePointer<UInt32>
    private let context: CGContext

    init(columns: Int, rows: Int, palette: Palette = .amberLED, texelsPerCell: Int = 8, litSize: Int = 6) {
        precondition(columns > 0 && rows > 0, "grid must be non-empty")
        precondition(litSize >= 3 && litSize <= texelsPerCell, "lit square must fit its cell and have an interior")

        self.columns = columns
        self.rows = rows
        self.texelsPerCell = texelsPerCell
        self.litSize = litSize
        self.pixelWidth = columns * texelsPerCell
        self.pixelHeight = rows * texelsPerCell
        self.texelCount = columns * texelsPerCell * rows * texelsPerCell

        self.backgroundColor = palette.background.packed
        self.liveColor = palette.live.packed
        self.ghostColor = palette.ghostOverBackground.packed

        frame = .allocate(capacity: texelCount)
        frame.initialize(repeating: backgroundColor, count: texelCount)

        guard
            let context = CGContext(
                data: frame,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: pixelWidth * MemoryLayout<UInt32>.size,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            )
        else {
            preconditionFailure("could not create a bitmap context for the frame buffer")
        }
        self.context = context
    }

    deinit {
        frame.deallocate()
    }

    var pixelSize: CGSize {
        CGSize(width: pixelWidth, height: pixelHeight)
    }

    /// Records which cells the digits started from. Called once when the
    /// minute changes; the cells are stroked afresh on every frame.
    func setGhost(_ ghost: CellBitmap) {
        precondition(ghost.width == columns && ghost.height == rows, "size mismatch")
        ghostCells.removeAll(keepingCapacity: true)
        for y in 0..<rows {
            for x in 0..<columns where ghost[x, y] {
                ghostCells.append(y * columns + x)
            }
        }
    }

    func image(for grid: LifeGrid) -> CGImage? {
        precondition(grid.width == columns && grid.height == rows, "size mismatch")
        frame.update(repeating: backgroundColor, count: texelCount)

        grid.withWords { words in
            let wordsPerRow = grid.wordsPerRow
            for y in 0..<rows {
                let rowBase = y * wordsPerRow
                for wordIndex in 0..<wordsPerRow {
                    var word = words[rowBase + wordIndex]
                    // Walk only the set bits rather than all 64 columns.
                    while word != 0 {
                        let column = wordIndex * 64 + word.trailingZeroBitCount
                        word &= word - 1
                        fillCell(x: column, y: y)
                    }
                }
            }
        }

        // Last, so a live cell underneath shows through the middle of the ring.
        for cell in ghostCells {
            strokeCell(x: cell % columns, y: cell / columns)
        }

        return context.makeImage()
    }

    @inline(__always)
    private func fillCell(x: Int, y: Int) {
        let left = x * texelsPerCell
        let top = y * texelsPerCell
        for row in 0..<litSize {
            let base = (top + row) * pixelWidth + left
            for column in 0..<litSize {
                frame[base + column] = liveColor
            }
        }
    }

    /// One-texel hollow square on the same footprint as a filled cell.
    @inline(__always)
    private func strokeCell(x: Int, y: Int) {
        let left = x * texelsPerCell
        let top = y * texelsPerCell
        let last = litSize - 1

        let topRow = top * pixelWidth + left
        let bottomRow = (top + last) * pixelWidth + left
        for column in 0..<litSize {
            frame[topRow + column] = ghostColor
            frame[bottomRow + column] = ghostColor
        }
        for row in 1..<last {
            let base = (top + row) * pixelWidth + left
            frame[base] = ghostColor
            frame[base + last] = ghostColor
        }
    }
}
