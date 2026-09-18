import CoreGraphics
import Foundation
import Testing
@testable import CGOLClock

@Suite("Resolution modes")
struct ResolutionTests {
    /// iPhone 17 Pro landscape.
    let size = CGSize(width: 874, height: 402)

    @Test("Matrix resolution is independent of display scale")
    func matrixIgnoresDisplayScale() {
        let one = GridLayout(viewSize: size, displayScale: 1, resolution: .matrix)
        let three = GridLayout(viewSize: size, displayScale: 3, resolution: .matrix)
        #expect(one == three)
        #expect(one.columns == 2 * GlyphMetrics.baseBlockWidth)
        #expect(one.glyphScale == 1)
    }

    @Test("Pixel resolution gives one cell per device pixel")
    func pixelMatchesDeviceResolution() {
        let layout = GridLayout(viewSize: size, displayScale: 3, resolution: .pixel)
        #expect(layout.columns == 2622)
        #expect(layout.rows == 1206)
        #expect(layout.cellCount == 2622 * 1206)
    }

    /// The whole point of the glyph scale: the clock has to look the same size
    /// on screen in both modes, even though one grid is thirty times finer.
    @Test(
        "The clock stays half the screen width in both modes",
        arguments: [
            CGSize(width: 874, height: 402),
            CGSize(width: 1376, height: 1032),
            CGSize(width: 402, height: 874),
        ]
    )
    func clockWidthIsStableAcrossModes(size: CGSize) {
        for resolution in Resolution.allCases {
            let layout = GridLayout(viewSize: size, displayScale: 3, resolution: resolution)
            let blockCells = layout.metrics.blockWidth
            let fraction = Double(blockCells) / Double(layout.columns)
            #expect(
                abs(fraction - 0.5) < 0.03,
                "\(resolution) at \(size) puts the clock at \(fraction) of the width"
            )
        }
    }

    @Test("A scaled glyph is the base glyph blown up")
    func scaledGlyphsMatchBaseGlyphs() {
        let scale = 7
        let metrics = GlyphMetrics.standard.scaled(to: scale)
        let renderer = DigitRenderer(metrics: metrics, face: .round)
        let columns = metrics.blockWidth * 2
        let rows = metrics.digitHeight * 3
        let centre = CellPoint(x: columns / 2, y: rows / 2)

        let bitmap = renderer.seed(text: "4", columns: columns, rows: rows, centre: centre)
        let bounds = try! #require(litBounds(bitmap))
        let cells = glyphCells(4)

        var glyphMinX = DigitFont.width, glyphMinY = DigitFont.height
        for y in 0..<DigitFont.height {
            for x in 0..<DigitFont.width where cells[y][x] {
                glyphMinX = min(glyphMinX, x); glyphMinY = min(glyphMinY, y)
            }
        }
        // Every cell of the scaled rendering matches the font cell it came from.
        for y in 0..<DigitFont.height {
            for x in 0..<DigitFont.width {
                let originX = bounds.minX + (x - glyphMinX) * scale
                let originY = bounds.minY + (y - glyphMinY) * scale
                for dy in 0..<scale {
                    for dx in 0..<scale {
                        #expect(
                            bitmap[originX + dx, originY + dy] == cells[y][x],
                            "font cell \(x),\(y) sub-cell \(dx),\(dy)"
                        )
                    }
                }
            }
        }
    }

    @Test("Glyph scale never collapses to zero on a tiny screen")
    func glyphScaleHasAFloor() {
        let layout = GridLayout(viewSize: CGSize(width: 1, height: 1), displayScale: 1, resolution: .pixel)
        #expect(layout.glyphScale >= 1)
        #expect(layout.columns >= 2 * GlyphMetrics.baseBlockWidth)
    }
}

@Suite("Pixel-resolution rendering")
struct PixelRenderingTests {
    let columns = 16
    let rows = 10

    private func render(live liveCells: [CellPoint], ghost ghostCells: [CellPoint], palette: Palette) -> RenderedFrame {
        let grid = LifeGrid(width: columns, height: rows)
        for cell in liveCells { grid[cell.x, cell.y] = true }

        var ghost = CellBitmap(width: columns, height: rows)
        for cell in ghostCells { ghost[cell.x, cell.y] = true }

        let rasterizer = FrameRasterizer(columns: columns, rows: rows, palette: palette, style: .pixel)
        rasterizer.setGhost(ghost)
        return RenderedFrame(rasterizer.image(for: grid)!)
    }

    @Test("Pixel style is exactly one texel per cell")
    func oneTexelPerCell() {
        let frame = render(live: [], ghost: [], palette: .amberLED)
        #expect(frame.width == columns)
        #expect(frame.height == rows)
    }

    /// At one texel per cell there is no room for a ring, so an overlap has to
    /// become a third colour.
    @Test("A live cell over a ghost cell takes the combined colour")
    func overlapBlends() {
        let palette = Palette.amberLED
        let both = CellPoint(x: 5, y: 4)
        let liveOnly = CellPoint(x: 2, y: 2)
        let ghostOnly = CellPoint(x: 9, y: 7)

        let frame = render(live: [both, liveOnly], ghost: [both, ghostOnly], palette: palette)

        #expect(frame[liveOnly.x, liveOnly.y] == palette.live.packed & 0x00FF_FFFF)
        #expect(frame[ghostOnly.x, ghostOnly.y] == palette.ghostOverBackground.packed & 0x00FF_FFFF)
        #expect(frame[both.x, both.y] == palette.overlap.packed & 0x00FF_FFFF)

        // The combined colour is genuinely a third colour, not one of the two.
        #expect(palette.overlap != palette.live)
        #expect(palette.overlap != palette.ghost)
        #expect(palette.overlap != palette.ghostOverBackground)
    }

    @Test("The combined colour sits between its two inputs on every channel")
    func overlapIsAMidpoint() {
        let palette = Palette.amberLED
        let overlap = palette.overlap
        func between(_ value: UInt8, _ a: UInt8, _ b: UInt8) -> Bool {
            value >= min(a, b) && value <= max(a, b)
        }
        #expect(between(overlap.red, palette.live.red, palette.ghost.red))
        #expect(between(overlap.green, palette.live.green, palette.ghost.green))
        #expect(between(overlap.blue, palette.live.blue, palette.ghost.blue))
    }

    @Test("Custom colours reach the rendered frame")
    func customColoursAreUsed() {
        let palette = Palette(
            background: RGB(0, 0, 0),
            live: RGB(0xFF, 0x00, 0x00),
            ghost: RGB(0x00, 0x00, 0xFF),
            ghostOpacity: 1
        )
        let cell = CellPoint(x: 3, y: 3)
        let frame = render(live: [cell], ghost: [], palette: palette)
        #expect(frame[cell.x, cell.y] == 0xFF0000)
        #expect(frame[0, 0] == 0x000000)
    }
}

@Suite("Settings persistence")
@MainActor
struct SettingsPersistenceTests {

    private func freshDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Defaults match the built-in palette")
    func startsAtDefaults() {
        let settings = ClockSettings(defaults: freshDefaults("settings.defaults"))
        #expect(settings.live == Palette.amberLED.live)
        #expect(settings.ghost == Palette.amberLED.ghost)
        #expect(settings.resolution == .matrix)
        #expect(settings.face == .round)
    }

    @Test("Choices survive a relaunch")
    func choicesRoundTrip() {
        let name = "settings.roundtrip"
        let defaults = freshDefaults(name)

        let first = ClockSettings(defaults: defaults)
        first.live = RGB(0x12, 0x34, 0x56)
        first.ghost = RGB(0xAB, 0xCD, 0xEF)
        first.resolution = .pixel
        first.face = .block

        let second = ClockSettings(defaults: defaults)
        #expect(second.live == RGB(0x12, 0x34, 0x56))
        #expect(second.ghost == RGB(0xAB, 0xCD, 0xEF))
        #expect(second.resolution == .pixel)
        #expect(second.face == .block)
    }

    @Test("Resetting restores the defaults")
    func resetRestoresDefaults() {
        let settings = ClockSettings(defaults: freshDefaults("settings.reset"))
        settings.live = RGB(1, 2, 3)
        settings.resolution = .pixel
        settings.face = .block
        settings.resetToDefaults()

        #expect(settings.live == Palette.amberLED.live)
        #expect(settings.resolution == .matrix)
        #expect(settings.face == .round)
    }

    @Test("A colour survives the round trip through packed storage", arguments: [
        RGB(0, 0, 0), RGB(255, 255, 255), RGB(0xFF, 0xB0, 0x00), RGB(0x34, 0xD3, 0xC8), RGB(1, 128, 254),
    ])
    func packedColoursRoundTrip(colour: RGB) {
        #expect(RGB(packedRGB: colour.packedRGB) == colour)
    }
}
