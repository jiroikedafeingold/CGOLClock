import Foundation

/// A bit-per-cell rectangular grid.
///
/// One `UInt64` word covers 64 columns: column `x` of row `y` is bit `x % 64`
/// of word `y * wordsPerRow + x / 64`. `LifeGrid` uses the identical layout, so
/// a bitmap can be copied straight into it without any per-cell work.
///
/// Bits past `width` in a row's last word are always zero.
nonisolated struct CellBitmap: Equatable {
    let width: Int
    let height: Int
    let wordsPerRow: Int
    private(set) var words: [UInt64]

    init(width: Int, height: Int) {
        precondition(width > 0 && height > 0, "grid must be non-empty")
        self.width = width
        self.height = height
        self.wordsPerRow = (width + 63) / 64
        self.words = [UInt64](repeating: 0, count: ((width + 63) / 64) * height)
    }

    /// Out-of-bounds reads return `false` and out-of-bounds writes are dropped,
    /// so callers stamping shapes near an edge don't need to clip first.
    subscript(x: Int, y: Int) -> Bool {
        get {
            guard x >= 0, x < width, y >= 0, y < height else { return false }
            return words[y * wordsPerRow + (x >> 6)] & (UInt64(1) << UInt64(x & 63)) != 0
        }
        set {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            let index = y * wordsPerRow + (x >> 6)
            let bit = UInt64(1) << UInt64(x & 63)
            if newValue {
                words[index] |= bit
            } else {
                words[index] &= ~bit
            }
        }
    }

    mutating func fill(x: Int, y: Int, width fillWidth: Int, height fillHeight: Int) {
        guard fillWidth > 0, fillHeight > 0 else { return }
        for row in y..<(y + fillHeight) {
            for column in x..<(x + fillWidth) {
                self[column, row] = true
            }
        }
    }

    var populationCount: Int {
        words.reduce(0) { $0 + $1.nonzeroBitCount }
    }

    /// The one-cell ring hugging the outside of the live shape: cells that touch
    /// a live cell in the 8-neighbourhood but are not live themselves.
    ///
    /// Deliberately unwrapped — this is a static overlay tracing the seed, and
    /// the clock block never sits against the grid edge. Runs once per minute.
    func outline() -> CellBitmap {
        var result = CellBitmap(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width where !self[x, y] {
                if touchesLiveCell(x: x, y: y) {
                    result[x, y] = true
                }
            }
        }
        return result
    }

    private func touchesLiveCell(x: Int, y: Int) -> Bool {
        for dy in -1...1 {
            for dx in -1...1 where !(dx == 0 && dy == 0) {
                if self[x + dx, y + dy] { return true }
            }
        }
        return false
    }
}
