import CoreGraphics
import CoreText

/// A typeface for the clock, realised differently depending on how big a cell is.
///
/// At pixel resolution a digit is hundreds of pixels tall, so the face names a
/// real font and `TypeRenderer` rasterises it at the screen's own resolution.
///
/// At LED-matrix sizes a digit is only 8x14 cells. A real font thresholded that
/// small comes out with one-cell strokes that evaporate in a single generation
/// — measured on Helvetica at 16px: Black and Heavy give a thinnest stroke of
/// one cell, Bold two — so matrix resolution uses hand-drawn bitmap glyphs.
/// Only `round` and `block` have their own; the rest borrow whichever is
/// closest, which the settings sheet says out loud.
nonisolated enum ClockFace: String, CaseIterable, Identifiable, Sendable {
    case round
    case block
    case grotesque
    case serif
    case condensed
    case typewriter

    var id: String { rawValue }

    var name: String {
        switch self {
        case .round: "Round"
        case .block: "Block"
        case .grotesque: "Neue"
        case .serif: "Serif"
        case .condensed: "Narrow"
        case .typewriter: "Type"
        }
    }

    /// Concrete families rather than the system font, so the faces stay
    /// visibly different and don't drift with the OS.
    private var fontName: String {
        switch self {
        case .round: "AvenirNext-Heavy"
        case .block: "Menlo-Bold"
        case .grotesque: "HelveticaNeue-Bold"
        case .serif: "Georgia-Bold"
        case .condensed: "AvenirNextCondensed-Heavy"
        case .typewriter: "Courier-Bold"
        }
    }

    func font(ofSize size: CGFloat) -> CTFont {
        CTFontCreateWithName(fontName as CFString, size, nil)
    }

    /// Whether this face has bitmap glyphs of its own, or borrows them.
    var hasOwnBitmap: Bool {
        switch self {
        case .round, .block: true
        default: false
        }
    }

    /// The face whose bitmap glyphs stand in at LED-matrix sizes.
    var bitmapSource: ClockFace {
        switch self {
        case .round, .grotesque, .serif: .round
        case .block, .condensed, .typewriter: .block
        }
    }

    /// Row bitmasks per digit, bit 0 being the leftmost column.
    var glyphs: [[UInt8]] {
        switch bitmapSource {
        case .block: Self.blockGlyphs
        default: Self.roundGlyphs
        }
    }

    // MARK: - Bitmaps

    private static let roundGlyphs = DigitFont.parse(roundPatterns)
    private static let blockGlyphs = DigitFont.parse(blockPatterns)

    /// Mixes closed bowls (0, 6, 8), long diagonals (1, 2, 4, 7) and open tails
    /// (3, 5, 9), so each digit decays under Life differently.
    private static let roundPatterns: [[String]] = [
        [
            "..####..", ".##..##.", "##....##", "##....##", "##....##", "##....##", "##....##",
            "##....##", "##....##", "##....##", "##....##", "##....##", ".##..##.", "..####..",
        ],
        [
            "...##...", "..###...", ".####...", "...##...", "...##...", "...##...", "...##...",
            "...##...", "...##...", "...##...", "...##...", "...##...", ".######.", ".######.",
        ],
        [
            ".######.", "##....##", "##....##", "......##", "......##", ".....##.", "....##..",
            "...##...", "..##....", ".##.....", "##......", "##......", "########", "########",
        ],
        [
            ".######.", "##....##", "......##", "......##", "......##", "..#####.", "..#####.",
            "......##", "......##", "......##", "......##", "##....##", "##....##", ".######.",
        ],
        [
            ".....##.", "....###.", "...####.", "..##.##.", ".##..##.", "##...##.", "##...##.",
            "########", "########", ".....##.", ".....##.", ".....##.", ".....##.", ".....##.",
        ],
        [
            "########", "########", "##......", "##......", "##......", "######..", ".######.",
            "......##", "......##", "......##", "......##", "##....##", "##....##", ".######.",
        ],
        [
            "..####..", ".##..##.", "##......", "##......", "##......", "######..", "#######.",
            "##....##", "##....##", "##....##", "##....##", "##....##", ".##..##.", "..####..",
        ],
        [
            "########", "########", "......##", ".....##.", ".....##.", "....##..", "....##..",
            "...##...", "...##...", "..##....", "..##....", ".##.....", ".##.....", "##......",
        ],
        [
            "..####..", ".##..##.", "##....##", "##....##", ".##..##.", "..####..", "..####..",
            ".##..##.", "##....##", "##....##", "##....##", "##....##", ".##..##.", "..####..",
        ],
        [
            "..####..", ".##..##.", "##....##", "##....##", "##....##", "##....##", ".#######",
            "..#####.", "......##", "......##", "......##", "......##", "......##", "......##",
        ],
    ]

    /// Square corners throughout. Strokes meet at right angles, which erode
    /// into neat rectangular still lifes rather than scattering.
    private static let blockPatterns: [[String]] = [
        [
            "########", "########", "##....##", "##....##", "##....##", "##....##", "##....##",
            "##....##", "##....##", "##....##", "##....##", "##....##", "########", "########",
        ],
        [
            // The flag and the stem are both two cells thick; a stepped flag
            // leaves a one-cell spur at the left end that dies immediately.
            "..######", "..######", "....##..", "....##..", "....##..", "....##..", "....##..",
            "....##..", "....##..", "....##..", "....##..", "....##..", "########", "########",
        ],
        [
            "########", "########", "......##", "......##", "......##", "########", "########",
            "##......", "##......", "##......", "##......", "##......", "########", "########",
        ],
        [
            "########", "########", "......##", "......##", "......##", "..######", "..######",
            "......##", "......##", "......##", "......##", "......##", "########", "########",
        ],
        [
            "##....##", "##....##", "##....##", "##....##", "##....##", "##....##", "########",
            "########", "......##", "......##", "......##", "......##", "......##", "......##",
        ],
        [
            "########", "########", "##......", "##......", "##......", "########", "########",
            "......##", "......##", "......##", "......##", "......##", "########", "########",
        ],
        [
            "########", "########", "##......", "##......", "##......", "########", "########",
            "##....##", "##....##", "##....##", "##....##", "##....##", "########", "########",
        ],
        [
            "########", "########", "......##", "......##", "......##", "......##", "......##",
            "......##", "......##", "......##", "......##", "......##", "......##", "......##",
        ],
        [
            "########", "########", "##....##", "##....##", "##....##", "########", "########",
            "##....##", "##....##", "##....##", "##....##", "##....##", "########", "########",
        ],
        [
            "########", "########", "##....##", "##....##", "##....##", "########", "########",
            "......##", "......##", "......##", "......##", "......##", "########", "########",
        ],
    ]
}
