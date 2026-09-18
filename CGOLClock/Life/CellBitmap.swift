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

    /// Keeps each live cell with probability `density`, dropping the rest.
    ///
    /// A solid glyph mostly dies on contact with Life — its interior cells all
    /// have eight neighbours. Thinning it to a sparse scatter gives something
    /// much closer to the classic random soup, which is where the interesting
    /// structures come from.
    ///
    /// Deterministic in `seed` so the same minute always scatters the same way
    /// and a re-render doesn't reshuffle the field.
    func scattered(density: Double, seed: UInt64) -> CellBitmap {
        guard density < 1 else { return self }
        guard density > 0 else { return CellBitmap(width: width, height: height) }

        var result = CellBitmap(width: width, height: height)
        // xorshift64; seeded away from zero, which is a fixed point.
        var state = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        if state == 0 { state = 0x2545_F491_4F6C_DD1D }
        let threshold = UInt64(density * Double(UInt64.max))

        for index in words.indices {
            var word = words[index]
            var kept: UInt64 = 0
            while word != 0 {
                let bit = word.trailingZeroBitCount
                word &= word - 1
                state ^= state << 13
                state ^= state >> 7
                state ^= state << 17
                if state < threshold { kept |= UInt64(1) << UInt64(bit) }
            }
            result.words[index] = kept
        }
        return result
    }

}
