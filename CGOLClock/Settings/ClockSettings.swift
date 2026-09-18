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
        case .matrix: "Chunky cells with a visible grid."
        case .pixel: "One cell per screen pixel. Millions of cells; the digits dissolve into grain."
        }
    }
}

/// User-adjustable display settings, persisted across launches.
@Observable
@MainActor
final class ClockSettings {
    var live: RGB { didSet { save() } }
    var ghost: RGB { didSet { save() } }
    var resolution: Resolution { didSet { save() } }
    var face: ClockFace { didSet { save() } }

    private let defaults: UserDefaults

    private enum Key {
        static let live = "display.liveColor"
        static let ghost = "display.ghostColor"
        static let resolution = "display.resolution"
        static let face = "display.face"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let fallback = Palette.amberLED
        live = defaults.rgb(forKey: Key.live) ?? fallback.live
        ghost = defaults.rgb(forKey: Key.ghost) ?? fallback.ghost
        resolution = defaults.string(forKey: Key.resolution)
            .flatMap(Resolution.init(rawValue:)) ?? .matrix
        face = defaults.string(forKey: Key.face)
            .flatMap(ClockFace.init(rawValue:)) ?? .round
    }

    /// The palette these settings describe. Background and ghost opacity are
    /// not adjustable — a light background would defeat the point.
    var palette: Palette {
        Palette(
            background: Palette.amberLED.background,
            live: live,
            ghost: ghost,
            ghostOpacity: Palette.amberLED.ghostOpacity
        )
    }

    func resetToDefaults() {
        live = Palette.amberLED.live
        ghost = Palette.amberLED.ghost
        resolution = .matrix
        face = .round
    }

    private func save() {
        defaults.set(live.packedRGB, forKey: Key.live)
        defaults.set(ghost.packedRGB, forKey: Key.ghost)
        defaults.set(resolution.rawValue, forKey: Key.resolution)
        defaults.set(face.rawValue, forKey: Key.face)
    }
}

private extension UserDefaults {
    func rgb(forKey key: String) -> RGB? {
        guard object(forKey: key) != nil else { return nil }
        return RGB(packedRGB: integer(forKey: key))
    }
}
