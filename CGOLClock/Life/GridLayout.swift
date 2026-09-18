import CoreGraphics

/// A position in grid coordinates.
nonisolated struct CellPoint: Equatable {
    let x: Int
    let y: Int
}

/// Works out how many cells fit on screen and how big each one is.
///
/// The column count is fixed by the requirement that the `HH:MM` block occupy
/// `clockWidthFraction` of the width — with the standard metrics that is 38
/// cells out of 76. Cell size then falls out of the view width, so a larger
/// screen gets physically larger pixels rather than more of them, and the
/// chunky LED-matrix look survives the jump from iPhone to iPad.
nonisolated struct GridLayout: Equatable {
    let columns: Int
    let rows: Int
    let cellSize: CGFloat

    init(viewSize: CGSize, metrics: GlyphMetrics = .standard, clockWidthFraction: CGFloat = 0.5) {
        let wanted = CGFloat(metrics.blockWidth) / clockWidthFraction
        // Two spare columns so the clock never touches the wrapping edge.
        columns = max(metrics.blockWidth + 2, Int(wanted.rounded()))

        let width = max(viewSize.width, 1)
        let height = max(viewSize.height, 1)
        cellSize = width / CGFloat(columns)
        // Two spare rows for the same reason.
        rows = max(metrics.blockHeight + 2, Int((height / cellSize).rounded(.down)))
    }

    var pixelSize: CGSize {
        CGSize(width: CGFloat(columns) * cellSize, height: CGFloat(rows) * cellSize)
    }

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
