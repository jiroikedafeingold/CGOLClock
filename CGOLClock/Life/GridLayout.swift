import CoreGraphics

/// A position in grid coordinates.
nonisolated struct CellPoint: Equatable {
    let x: Int
    let y: Int
}

/// Works out how many cells fit on screen, how big each one is, and how far
/// the font has to be scaled up to keep the clock at the same size.
///
/// In `.matrix` the column count is fixed by the requirement that an `HH:MM`
/// block occupy `clockWidthFraction` of the width — 43 cells out of 86. Cell
/// size then falls out of the view width, so a larger screen gets physically
/// larger cells rather than more of them.
///
/// In `.pixel` there is one cell per device pixel, and the glyph scale takes
/// up the slack so the digits still fill half the width — they just erode a
/// grain at a time instead of a block at a time.
nonisolated struct GridLayout: Equatable {
    let columns: Int
    let rows: Int
    let cellSize: CGFloat
    /// Grid cells per font cell, for the bitmap faces.
    let glyphScale: Int
    /// How wide the clock should be, in cells.
    let clockWidth: Int

    init(
        viewSize: CGSize,
        displayScale: CGFloat = 1,
        resolution: Resolution = .matrix,
        clockWidthFraction: CGFloat = 0.5
    ) {
        let base = GlyphMetrics.baseBlockWidth
        let matrixColumns = max(base + 2, Int((CGFloat(base) / clockWidthFraction).rounded()))

        let width = max(viewSize.width, 1)
        let height = max(viewSize.height, 1)

        switch resolution {
        case .matrix:
            columns = matrixColumns
        case .pixel:
            columns = max(matrixColumns, Int((width * max(displayScale, 1)).rounded()))
        }

        cellSize = width / CGFloat(columns)
        rows = max(DigitFont.height + 2, Int((height / cellSize).rounded(.down)))
        // Largest whole scale whose block still fits the requested fraction.
        clockWidth = max(1, Int(CGFloat(columns) * clockWidthFraction))
        glyphScale = max(1, clockWidth / base)
    }

    var pixelSize: CGSize {
        CGSize(width: CGFloat(columns) * cellSize, height: CGFloat(rows) * cellSize)
    }

    var metrics: GlyphMetrics {
        GlyphMetrics.standard.scaled(to: glyphScale)
    }

    var cellCount: Int { columns * rows }

    /// The cell containing `point`, which is in view coordinates. Used to place
    /// the clock at the centre of the safe area rather than the centre of the
    /// screen, so the notch and home indicator don't push it off-centre.
    func cell(at point: CGPoint) -> CellPoint {
        CellPoint(
            x: min(max(Int(point.x / cellSize), 0), columns - 1),
            y: min(max(Int(point.y / cellSize), 0), rows - 1)
        )
    }
}
