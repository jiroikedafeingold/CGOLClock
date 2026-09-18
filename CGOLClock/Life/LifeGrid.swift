import Foundation

/// Conway's Game of Life on a toroidal board, stored one bit per cell.
///
/// The step is bit-parallel (SWAR): every cell in a 64-bit word advances in the
/// same handful of integer instructions, so a generation costs roughly 30 ops
/// per 64 cells instead of per cell. Neighbour counting is done with bit-sliced
/// half/full adders — the eight neighbour masks are summed into four bit-planes
/// `n0...n3` holding the binary neighbour count, then the survival rule is a
/// couple of ANDs.
///
/// Both edges wrap. Vertical wrap is just modular row indexing; horizontal wrap
/// is a rotate across the row's word array, which has to account for `width`
/// not being a multiple of 64. That last part is the subtle bit and is covered
/// directly by tests.
///
/// Bit layout matches `CellBitmap`.
nonisolated final class LifeGrid {
    let width: Int
    let height: Int
    let wordsPerRow: Int

    /// Valid bits in the last word of a row, 1...64.
    private let tailBits: Int
    private let lastWord: Int
    /// Clears the unused high bits of a row's last word.
    private let tailMask: UInt64
    private let wordCount: Int

    private var front: UnsafeMutablePointer<UInt64>
    private var back: UnsafeMutablePointer<UInt64>
    /// OR of every word in a row. Lets an all-empty row triple skip the
    /// arithmetic entirely, which is most of a tall grid for most of a minute.
    private var frontRowOr: UnsafeMutablePointer<UInt64>
    private var backRowOr: UnsafeMutablePointer<UInt64>

    private(set) var generation = 0

    init(width: Int, height: Int) {
        precondition(width > 0 && height > 0, "grid must be non-empty")
        self.width = width
        self.height = height
        self.wordsPerRow = (width + 63) / 64
        self.tailBits = width % 64 == 0 ? 64 : width % 64
        self.lastWord = (width + 63) / 64 - 1
        self.tailMask = width % 64 == 0 ? ~0 : (UInt64(1) << UInt64(width % 64)) - 1
        self.wordCount = ((width + 63) / 64) * height

        front = .allocate(capacity: wordCount)
        back = .allocate(capacity: wordCount)
        frontRowOr = .allocate(capacity: height)
        backRowOr = .allocate(capacity: height)
        front.initialize(repeating: 0, count: wordCount)
        back.initialize(repeating: 0, count: wordCount)
        frontRowOr.initialize(repeating: 0, count: height)
        backRowOr.initialize(repeating: 0, count: height)
    }

    deinit {
        front.deallocate()
        back.deallocate()
        frontRowOr.deallocate()
        backRowOr.deallocate()
    }

    // MARK: - Contents

    func clear() {
        front.update(repeating: 0, count: wordCount)
        frontRowOr.update(repeating: 0, count: height)
        generation = 0
    }

    /// Replaces the board with `bitmap`, which must be the same size.
    func load(_ bitmap: CellBitmap) {
        precondition(bitmap.width == width && bitmap.height == height, "size mismatch")
        bitmap.words.withUnsafeBufferPointer { source in
            front.update(from: source.baseAddress!, count: wordCount)
        }
        for y in 0..<height {
            var accumulator: UInt64 = 0
            for j in 0..<wordsPerRow {
                accumulator |= front[y * wordsPerRow + j]
            }
            frontRowOr[y] = accumulator
        }
        generation = 0
    }

    subscript(x: Int, y: Int) -> Bool {
        get {
            guard x >= 0, x < width, y >= 0, y < height else { return false }
            return front[y * wordsPerRow + (x >> 6)] & (UInt64(1) << UInt64(x & 63)) != 0
        }
        set {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            let index = y * wordsPerRow + (x >> 6)
            let bit = UInt64(1) << UInt64(x & 63)
            if newValue {
                front[index] |= bit
                frontRowOr[y] |= bit
            } else {
                front[index] &= ~bit
                var accumulator: UInt64 = 0
                for j in 0..<wordsPerRow {
                    accumulator |= front[y * wordsPerRow + j]
                }
                frontRowOr[y] = accumulator
            }
        }
    }

    var populationCount: Int {
        var total = 0
        for i in 0..<wordCount { total += front[i].nonzeroBitCount }
        return total
    }

    /// The live-cell words, row-major, `wordsPerRow` words per row. The buffer
    /// is only valid for the duration of the call.
    func withWords<R>(_ body: (UnsafeBufferPointer<UInt64>) -> R) -> R {
        body(UnsafeBufferPointer(start: front, count: wordCount))
    }

    // MARK: - Step

    func step() {
        let w = wordsPerRow

        for y in 0..<height {
            let above = y == 0 ? height - 1 : y - 1
            let below = y == height - 1 ? 0 : y + 1
            let destination = back + y * w

            // Nothing within reach of this row, so the whole row stays empty.
            if frontRowOr[above] | frontRowOr[y] | frontRowOr[below] == 0 {
                destination.update(repeating: 0, count: w)
                backRowOr[y] = 0
                continue
            }

            let a = front + above * w
            let b = front + y * w
            let c = front + below * w
            var rowAccumulator: UInt64 = 0

            for j in 0..<w {
                let aCentre = a[j], bCentre = b[j], cCentre = c[j]
                let aWest = west(a, j), aEast = east(a, j)
                let bWest = west(b, j), bEast = east(b, j)
                let cWest = west(c, j), cEast = east(c, j)

                // Partial sums: 0...3 for each of the outer rows, 0...2 for the
                // middle row (the centre cell is excluded from its own count).
                let (aLow, aHigh) = Self.add3(aWest, aCentre, aEast)
                let (cLow, cHigh) = Self.add3(cWest, cCentre, cEast)
                let bLow = bWest ^ bEast
                let bHigh = bWest & bEast

                // Combine into a four-bit-plane neighbour count, 0...8.
                let (n0, lowCarry) = Self.add3(aLow, cLow, bLow)
                let (highSum, highCarry) = Self.add3(aHigh, cHigh, bHigh)
                let n1 = highSum ^ lowCarry
                let carry2 = highSum & lowCarry
                let n2 = highCarry ^ carry2
                let n3 = highCarry & carry2

                // Born on exactly 3, survive on exactly 2 or 3.
                let twoOrThree = n1 & ~(n2 | n3)
                var next = twoOrThree & (n0 | bCentre)
                if j == lastWord { next &= tailMask }

                destination[j] = next
                rowAccumulator |= next
            }

            backRowOr[y] = rowAccumulator
        }

        swap(&front, &back)
        swap(&frontRowOr, &backRowOr)
        generation += 1
    }

    /// Bit-sliced full adder: returns the two-bit sum of three one-bit inputs,
    /// computed for all 64 lanes at once.
    @inline(__always)
    private static func add3(_ a: UInt64, _ b: UInt64, _ c: UInt64) -> (low: UInt64, high: UInt64) {
        let aXorB = a ^ b
        return (aXorB ^ c, (a & b) | (aXorB & c))
    }

    /// Row shifted one column east: bit `x` holds the cell from column `x - 1`.
    /// Bit 0 of word 0 wraps in from the row's last valid column.
    @inline(__always)
    private func west(_ row: UnsafePointer<UInt64>, _ j: Int) -> UInt64 {
        let carry = j == 0
            ? (row[lastWord] >> UInt64(tailBits - 1)) & 1
            : row[j - 1] >> 63
        return (row[j] << 1) | carry
    }

    /// Row shifted one column west: bit `x` holds the cell from column `x + 1`.
    /// The row's last valid column wraps in from column 0.
    @inline(__always)
    private func east(_ row: UnsafePointer<UInt64>, _ j: Int) -> UInt64 {
        if j == lastWord {
            return (row[j] >> 1) | ((row[0] & 1) << UInt64(tailBits - 1))
        }
        return (row[j] >> 1) | ((row[j + 1] & 1) << 63)
    }
}
