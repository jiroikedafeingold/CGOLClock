import CoreGraphics

/// How a cell is drawn, which depends entirely on how big it is.
nonisolated struct RenderStyle: Equatable {
    /// Texels per cell, including the gutter.
    let texelsPerCell: Int
    /// Texels of the square drawn inside each cell.
    let litSize: Int
    /// Whether a ghost cell is stroked as a ring or blended into one colour.
    /// Blending is what you do when a cell is a single pixel and there is no
    /// room to draw a ring inside it.
    let blendsGhost: Bool

    /// Chunky cells: big enough to draw a live square inside a ghost ring.
    static let matrix = RenderStyle(texelsPerCell: 8, litSize: 6, blendsGhost: false)

    /// One texel per cell. There is no room for a ring, so a cell that is both
    /// live and part of the seed takes a blended colour instead.
    static let pixel = RenderStyle(texelsPerCell: 1, litSize: 1, blendsGhost: true)

    static func forResolution(_ resolution: Resolution) -> RenderStyle {
        switch resolution {
        case .matrix: .matrix
        case .pixel: .pixel
        }
    }
}

/// Turns a `LifeGrid` into a `CGImage`, one texel block per cell.
///
/// In matrix style the image is tiny — a few hundred texels on a side — and the
/// view scales it up with nearest-neighbour filtering, so the GPU does the
/// magnification and the pixels stay hard-edged. In pixel style the image is
/// already at device resolution and is displayed one-to-one.
///
/// Drawing order per frame is background, then live cells, then the ghost.
/// The ghost marks the cells the digits started from and goes last, so it is
/// never painted over.
nonisolated final class FrameRasterizer {
    let columns: Int
    let rows: Int
    let style: RenderStyle
    let palette: Palette

    private let pixelWidth: Int
    private let pixelHeight: Int
    private let texelCount: Int

    private let backgroundColor: UInt32
    private let liveColor: UInt32
    private let ghostColor: UInt32
    private let overlapColor: UInt32

    /// Row-major indices of the cells the digits started from, rebuilt once
    /// per minute.
    private var ghostCells: [Int] = []

    private let frame: UnsafeMutablePointer<UInt32>
    private let context: CGContext

    init(columns: Int, rows: Int, palette: Palette = .amberLED, style: RenderStyle = .matrix) {
        precondition(columns > 0 && rows > 0, "grid must be non-empty")
        precondition(style.litSize > 0 && style.litSize <= style.texelsPerCell, "lit square must fit its cell")
        precondition(style.blendsGhost || style.litSize >= 3, "a stroked ring needs an interior")

        self.columns = columns
        self.rows = rows
        self.style = style
        self.palette = palette
        self.pixelWidth = columns * style.texelsPerCell
        self.pixelHeight = rows * style.texelsPerCell
        self.texelCount = columns * style.texelsPerCell * rows * style.texelsPerCell

        self.backgroundColor = palette.background.packed
        self.liveColor = palette.live.packed
        self.ghostColor = palette.ghostOverBackground.packed
        self.overlapColor = palette.overlap.packed

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
    /// minute changes; the cells are drawn afresh on every frame.
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

        // At one texel per cell the cell index *is* the texel index, which
        // takes a divide and a modulo out of the inner loops. That matters:
        // pixel resolution runs to millions of cells a frame.
        let oneToOne = style.texelsPerCell == 1

        grid.withWords { words in
            let wordsPerRow = grid.wordsPerRow
            for y in 0..<rows {
                let rowBase = y * wordsPerRow
                let texelRow = y * pixelWidth
                for wordIndex in 0..<wordsPerRow {
                    var word = words[rowBase + wordIndex]
                    let columnBase = wordIndex * 64
                    // Walk only the set bits rather than all 64 columns.
                    while word != 0 {
                        let column = columnBase + word.trailingZeroBitCount
                        word &= word - 1
                        if oneToOne {
                            frame[texelRow + column] = liveColor
                        } else {
                            fillCell(x: column, y: y)
                        }
                    }
                }
            }
        }

        if style.blendsGhost {
            // One texel per cell, so "is this cell alive" is just the texel we
            // already wrote. Live and ghost combine into a third colour.
            for cell in ghostCells {
                frame[cell] = frame[cell] == liveColor ? overlapColor : ghostColor
            }
        } else {
            for cell in ghostCells {
                strokeCell(x: cell % columns, y: cell / columns)
            }
        }

        return context.makeImage()
    }

    @inline(__always)
    private func fillCell(x: Int, y: Int) {
        let size = style.litSize
        let left = x * style.texelsPerCell
        let top = y * style.texelsPerCell
        for row in 0..<size {
            let base = (top + row) * pixelWidth + left
            for column in 0..<size {
                frame[base + column] = liveColor
            }
        }
    }

    /// One-texel hollow square on the same footprint as a filled cell, so a
    /// live cell underneath shows through the middle.
    @inline(__always)
    private func strokeCell(x: Int, y: Int) {
        let left = x * style.texelsPerCell
        let top = y * style.texelsPerCell
        let last = style.litSize - 1

        let topRow = top * pixelWidth + left
        let bottomRow = (top + last) * pixelWidth + left
        for column in 0..<style.litSize {
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
