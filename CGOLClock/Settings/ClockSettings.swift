import Foundation
import Observation

/// How finely the Life grid is divided.
nonisolated enum Resolution: String, CaseIterable, Identifiable, Sendable {
    /// Chunky LED-matrix cells, a few millimetres across, with a visible gutter.
    case matrix
    /// One cell per device pixel. The digits are scaled up to match, so they
    /// stay the same size on screen but erode grain by grain.
    case pixel

    var id: String { rawValue }

    var name: String {
        switch self {
        case .matrix: "LED Matrix"
        case .pixel: "Pixel"
        }
    }

    var detail: String {
        switch self {
        case .matrix: "Chunky cells with a visible grid, drawn from built-in pixel glyphs."
        case .pixel: "One cell per screen pixel, drawn with a real font. Millions of cells."
        }
    }
}

/// Which cells of the digits are handed to Life. The time itself is always
/// drawn filled — this only decides what comes alive.
nonisolated enum SeedStyle: String, CaseIterable, Identifiable, Sendable {
    /// The whole glyph. Solid interiors die immediately (eight neighbours),
    /// so this erodes inward from the edges.
    case filled
    /// Just the glyph outline, which leaves the strokes free to break up.
    case outline
    /// A random fraction of the glyph, closest to a classic Life soup.
    case scattered

    var id: String { rawValue }

    var name: String {
        switch self {
        case .filled: "Filled"
        case .outline: "Outline"
        case .scattered: "Scatter"
        }
    }
}

/// User-adjustable display settings, persisted across launches.
@Observable
@MainActor
final class ClockSettings {
    var live: RGB { didSet { save() } }
    var ghost: RGB { didSet { save() } }
    var timeOpacity: Double { didSet { save() } }
    var resolution: Resolution { didSet { save() } }
    var face: ClockFace { didSet { save() } }
    var seedStyle: SeedStyle { didSet { save() } }
    /// Fraction of the glyph kept when `seedStyle` is `.scattered`.
    var scatterDensity: Double { didSet { save() } }

    private let defaults: UserDefaults

    private enum Key {
        static let live = "display.liveColor"
        static let ghost = "display.ghostColor"
        static let opacity = "display.timeOpacity"
        static let resolution = "display.resolution"
        static let face = "display.face"
        static let seedStyle = "display.seedStyle"
        static let scatter = "display.scatterDensity"
    }

    /// White at 30% reads as a quiet backdrop the living cells sit on top of,
    /// rather than competing with them.
    static let defaultGhost = RGB(0xFF, 0xFF, 0xFF)
    static let defaultOpacity = 0.30
    static let defaultScatter = 0.20

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        live = defaults.rgb(forKey: Key.live) ?? Palette.amberLED.live
        ghost = defaults.rgb(forKey: Key.ghost) ?? Self.defaultGhost
        timeOpacity = defaults.object(forKey: Key.opacity) as? Double ?? Self.defaultOpacity
        resolution = defaults.string(forKey: Key.resolution)
            .flatMap(Resolution.init(rawValue:)) ?? .pixel
        face = defaults.string(forKey: Key.face)
            .flatMap(ClockFace.init(rawValue:)) ?? .round
        seedStyle = defaults.string(forKey: Key.seedStyle)
            .flatMap(SeedStyle.init(rawValue:)) ?? .scattered
        scatterDensity = defaults.object(forKey: Key.scatter) as? Double ?? Self.defaultScatter
    }

    /// The palette these settings describe. The background is not adjustable —
    /// a light one would defeat the whole effect.
    var palette: Palette {
        Palette(
            background: Palette.amberLED.background,
            live: live,
            ghost: ghost,
            ghostOpacity: timeOpacity
        )
    }

    /// Outlining needs a stroke many cells wide, which rules out the 8x14
    /// bitmap glyphs. Scatter works at any size.
    var outlineIsAvailable: Bool { resolution == .pixel }

    /// What the renderer will actually do, after falling back where a style
    /// isn't available.
    var effectiveSeedStyle: SeedStyle {
        seedStyle == .outline && !outlineIsAvailable ? .filled : seedStyle
    }

    func resetToDefaults() {
        live = Palette.amberLED.live
        ghost = Self.defaultGhost
        timeOpacity = Self.defaultOpacity
        resolution = .pixel
        face = .round
        seedStyle = .scattered
        scatterDensity = Self.defaultScatter
    }

    private func save() {
        defaults.set(live.packedRGB, forKey: Key.live)
        defaults.set(ghost.packedRGB, forKey: Key.ghost)
        defaults.set(timeOpacity, forKey: Key.opacity)
        defaults.set(resolution.rawValue, forKey: Key.resolution)
        defaults.set(face.rawValue, forKey: Key.face)
        defaults.set(seedStyle.rawValue, forKey: Key.seedStyle)
        defaults.set(scatterDensity, forKey: Key.scatter)
    }
}

private extension UserDefaults {
    func rgb(forKey key: String) -> RGB? {
        guard object(forKey: key) != nil else { return nil }
        return RGB(packedRGB: integer(forKey: key))
    }
}
