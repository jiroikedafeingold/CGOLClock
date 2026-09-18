import CoreGraphics
import Foundation
import Observation
import os

/// Drives the clock: seeds the grid from the current time, advances Life until
/// the minute rolls over, and publishes each generation as a `CGImage`.
///
/// The digits are held briefly, then the generation rate eases up to its peak
/// and stays there. The loop sleeps for exactly one inter-generation interval
/// rather than running on a display link — nothing on screen changes between
/// generations, so there is no reason to wake up for frames that would be
/// identical.
@Observable
@MainActor
final class ClockViewModel {

    /// The current generation, ready to draw. `nil` before the first layout.
    private(set) var frame: CGImage?

    /// How long the untouched digits are held after the minute changes, before
    /// the first generation runs, so the time is legible before it decays.
    let holdDuration = 1.0

    /// How long the rate takes to climb from `startRate` to `peakRate` once
    /// the hold ends.
    let rampDuration = 6.0

    /// Generations per second through the minute. The rate eases up from
    /// `startRate` to `peakRate` across `rampDuration` and then stays there —
    /// the field usually settles into still lifes and blinkers well before the
    /// minute is out, and holding the pace looks better than watching a frozen
    /// grid tick over slowly. Works out to roughly 550 generations a minute.
    ///
    /// `startRate` is a middle pace rather than a crawl: the first few
    /// generations are where the strokes come apart, which is worth seeing,
    /// but one frame every two-thirds of a second reads as stalled.
    private let startRate = 5.0
    private let peakRate = 10.0

    private var display: Display?
    private var seededMinute: Int?
    private var configuration: DisplayConfiguration?
    /// Where the digits are centred, in grid coordinates.
    private var clockCentre = CellPoint(x: 0, y: 0)
    /// Kept so the ghost can be restored when only the palette changes.
    private var currentSeed: CellBitmap?

    /// Everything the display depends on. The view recomputes this from its
    /// geometry and the user's settings and hands it over.
    nonisolated struct DisplayConfiguration: Equatable {
        var viewSize: CGSize
        var safeRect: CGRect
        var displayScale: CGFloat
        var palette: Palette
        var resolution: Resolution
        var face: ClockFace
        var seedStyle: SeedStyle
        var scatterDensity: Double
    }

    /// The pieces that have to be rebuilt together.
    private struct Display {
        let layout: GridLayout
        let grid: LifeGrid
        var rasterizer: FrameRasterizer
    }

    // MARK: - Configuration

    /// Applies a new geometry or palette. Cheap and idempotent when nothing
    /// has changed, so it is safe to call on every pass.
    ///
    /// The grid always covers the whole screen — Life runs edge to edge, under
    /// the notch and home indicator — but the digits are centred on the safe
    /// area so they read as centred to the eye.
    ///
    /// A palette-only change rebuilds the rasteriser but keeps the grid, so
    /// picking a colour doesn't restart the simulation mid-minute.
    func apply(_ configuration: DisplayConfiguration) {
        guard configuration != self.configuration else { return }
        let previous = self.configuration
        self.configuration = configuration

        let layout = GridLayout(
            viewSize: configuration.viewSize,
            displayScale: configuration.displayScale,
            resolution: configuration.resolution
        )
        let centre = layout.cell(
            at: CGPoint(x: configuration.safeRect.midX, y: configuration.safeRect.midY)
        )
        let style = RenderStyle.forResolution(configuration.resolution)

        if let display, display.layout == layout, clockCentre == centre,
           display.rasterizer.style == style {
            if previous?.face != configuration.face
                || previous?.seedStyle != configuration.seedStyle
                || previous?.scatterDensity != configuration.scatterDensity {
                // Same grid, different letterforms: redraw the seed in place
                // rather than tearing the simulation down.
                reseed(display, at: Date())
            }
            if display.rasterizer.palette != configuration.palette {
                recolour(display, palette: configuration.palette, style: style)
            } else {
                frame = display.rasterizer.image(for: display.grid)
            }
            return
        }

        clockCentre = centre
        let display = Display(
            layout: layout,
            grid: LifeGrid(width: layout.columns, height: layout.rows),
            rasterizer: FrameRasterizer(
                columns: layout.columns,
                rows: layout.rows,
                palette: configuration.palette,
                style: style
            )
        )
        self.display = display
        logLayout(layout, configuration: configuration, centre: centre, rebuiltFrom: previous)
        // Seed straight away so a change never shows a blank frame.
        reseed(display, at: Date())
        frame = display.rasterizer.image(for: display.grid)
    }

    /// Swaps in a rasteriser with new colours, leaving the simulation running.
    private func recolour(_ display: Display, palette: Palette, style: RenderStyle) {
        var updated = display
        updated.rasterizer = FrameRasterizer(
            columns: display.layout.columns,
            rows: display.layout.rows,
            palette: palette,
            style: style
        )
        if let currentSeed { updated.rasterizer.setGhost(currentSeed) }
        self.display = updated
        frame = updated.rasterizer.image(for: updated.grid)
    }

    private func logLayout(
        _ layout: GridLayout,
        configuration: DisplayConfiguration,
        centre: CellPoint,
        rebuiltFrom previous: DisplayConfiguration?
    ) {
        #if DEBUG
        let size = configuration.viewSize
        Self.log.debug(
            """
            \(configuration.resolution.rawValue, privacy: .public) \
            view \(size.width, format: .fixed(precision: 1))x\(size.height, format: .fixed(precision: 1)) \
            @\(configuration.displayScale, format: .fixed(precision: 0))x \
            -> \(layout.columns)x\(layout.rows) cells \
            (\(layout.cellCount) total) at \(layout.cellSize, format: .fixed(precision: 2))pt, \
            glyph scale \(layout.glyphScale); \
            centre cell \(centre.x),\(centre.y); \
            first layout: \(previous == nil, privacy: .public)
            """
        )
        #endif
    }

    // MARK: - Run loop

    func run() async {
        while !Task.isCancelled {
            let now = Date()
            advance(at: now)
            do {
                try await Task.sleep(for: .seconds(interval(at: now)), tolerance: .milliseconds(4))
            } catch {
                return  // cancelled
            }
        }
    }

    private func advance(at now: Date) {
        guard let display else { return }

        let clock = ContinuousClock()
        var needsRedraw = true

        let stepped = clock.measure {
            if minuteIndex(of: now) != seededMinute {
                reseed(display, at: now)
            } else if secondsIntoMinute(now) >= holdDuration {
                display.grid.step()
                // A settled field produces an identical frame, so there is
                // nothing to draw. Late in the minute this is most of them.
                needsRedraw = display.grid.changedLastStep
            } else {
                // Inside the hold: the seed is already on screen.
                needsRedraw = false
            }
        }

        guard needsRedraw else {
            record(step: stepped, raster: .zero, generation: display.grid.generation)
            return
        }

        let rasterised = clock.measure {
            frame = display.rasterizer.image(for: display.grid)
        }
        record(step: stepped, raster: rasterised, generation: display.grid.generation)
    }

    private func reseed(_ display: Display, at date: Date) {
        let text = ClockText.string(for: date)

        // The ghost is always the filled digits; the seed style only decides
        // which of those cells come alive.
        let filled = seedBitmap(for: text, display: display, outlined: false)
        let living: CellBitmap
        switch effectiveSeedStyle {
        case .filled:
            living = filled
        case .outline:
            living = seedBitmap(for: text, display: display, outlined: true)
        case .scattered:
            living = filled.scattered(
                density: configuration?.scatterDensity ?? 0.2,
                seed: UInt64(bitPattern: Int64(minuteIndex(of: date)))
            )
        }

        display.grid.load(living)
        display.rasterizer.setGhost(filled)
        currentSeed = filled
        seededMinute = minuteIndex(of: date)
    }

    /// Outlining needs a stroke many cells wide, which rules out the 8x14
    /// bitmap glyphs; it falls back to filled there.
    private var effectiveSeedStyle: SeedStyle {
        guard let configuration else { return .filled }
        if configuration.seedStyle == .outline && configuration.resolution != .pixel {
            return .filled
        }
        return configuration.seedStyle
    }

    /// Picks the way the digits are drawn from how big a cell is.
    ///
    /// At pixel resolution the grid is fine enough to carry real letterforms,
    /// so the text is rasterised with an actual font at the screen's own
    /// resolution. At LED-matrix sizes a real font thresholds down to one-cell
    /// strokes that die immediately, so the hand-drawn bitmap is used instead
    /// and scaled to the grid.
    private func seedBitmap(for text: String, display: Display, outlined: Bool) -> CellBitmap {
        let layout = display.layout
        let face = configuration?.face ?? .round

        switch configuration?.resolution ?? .matrix {
        case .pixel:
            return TypeRenderer(face: face, outlined: outlined).seed(
                text: text,
                columns: layout.columns,
                rows: layout.rows,
                centre: clockCentre,
                targetWidth: layout.clockWidth
            )
        case .matrix:
            return DigitRenderer(metrics: layout.metrics, face: face).seed(
                text: text,
                columns: layout.columns,
                rows: layout.rows,
                centre: clockCentre
            )
        }
    }

    /// Seconds to wait before the next generation. During the hold this is the
    /// whole remainder of the hold, so the untouched digits are rasterised once
    /// and the loop sleeps straight through to the first generation.
    private func interval(at date: Date) -> Double {
        let elapsed = secondsIntoMinute(date)
        guard elapsed >= holdDuration else { return holdDuration - elapsed }
        return 1 / rate(at: elapsed)
    }

    /// Generations per second `elapsed` seconds into the minute.
    func rate(at elapsed: Double) -> Double {
        let sinceHold = elapsed - holdDuration
        guard sinceHold < rampDuration else { return peakRate }

        // Smoothstep, so the ramp starts gently rather than lurching.
        let progress = max(sinceHold / rampDuration, 0)
        let eased = progress * progress * (3 - 2 * progress)
        return startRate * pow(peakRate / startRate, eased)
    }

    private func secondsIntoMinute(_ date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60)
    }

    private func minuteIndex(of date: Date) -> Int {
        Int((date.timeIntervalSinceReferenceDate / 60).rounded(.down))
    }

    // MARK: - Timing

    #if DEBUG
    private static let log = Logger(subsystem: "com.feingold5.CGOLClock", category: "timing")
    private var stepTotal: Duration = .zero
    private var rasterTotal: Duration = .zero
    private var measuredGenerations = 0
    private var skippedRasters = 0
    #endif

    /// Measures rather than assumes that a generation is cheap enough to run on
    /// the main actor. Logs an average every 100 generations in debug builds.
    private func record(step: Duration, raster: Duration, generation: Int) {
        #if DEBUG
        stepTotal += step
        rasterTotal += raster
        measuredGenerations += 1
        if raster == .zero { skippedRasters += 1 }
        guard measuredGenerations == 100 else { return }

        func microseconds(_ total: Duration) -> Double {
            let components = (total / measuredGenerations).components
            return Double(components.seconds) * 1e6 + Double(components.attoseconds) / 1e12
        }
        Self.log.debug(
            "generation \(generation): step \(microseconds(self.stepTotal), format: .fixed(precision: 1))µs, raster \(microseconds(self.rasterTotal), format: .fixed(precision: 1))µs, \(self.skippedRasters) of 100 frames unchanged"
        )
        stepTotal = .zero
        rasterTotal = .zero
        measuredGenerations = 0
        skippedRasters = 0
        #endif
    }
}
