import CoreGraphics
import Foundation
import Observation
import os

/// Drives the clock: seeds the grid from the current time, advances Life until
/// the minute rolls over, and publishes each generation as a `CGImage`.
///
/// The generation rate eases from `fastRate` at the top of the minute down to
/// `slowRate` at the end, so the field is churning while the digits are still
/// recognisable and has slowed to a crawl by the time it has settled. The loop
/// sleeps for exactly one inter-generation interval rather than running on a
/// display link — nothing on screen changes between generations, so there is
/// no reason to wake up for frames that would be identical.
@Observable
@MainActor
final class ClockViewModel {

    /// The current generation, ready to draw. `nil` before the first layout.
    private(set) var frame: CGImage?

    /// How long the untouched digits are held after the minute changes, before
    /// the first generation runs, so the time is legible before it decays.
    private let holdDuration = 3.0

    /// How long the rate takes to climb from `startRate` to `peakRate` once
    /// the hold ends.
    private let rampDuration = 6.0

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
            guard display.rasterizer.palette != configuration.palette else { return }
            recolour(display, palette: configuration.palette, style: style)
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
        let stepped = clock.measure {
            if minuteIndex(of: now) != seededMinute {
                reseed(display, at: now)
            } else if secondsIntoMinute(now) >= holdDuration {
                display.grid.step()
            }
            // Otherwise we're inside the hold: leave the seed untouched.
        }
        let rasterised = clock.measure {
            frame = display.rasterizer.image(for: display.grid)
        }
        record(step: stepped, raster: rasterised, generation: display.grid.generation)
    }

    private func reseed(_ display: Display, at date: Date) {
        // Glyphs are scaled to the grid, so the digits are the same size on
        // screen whether a cell is a chunky LED or a single device pixel.
        let renderer = DigitRenderer(metrics: display.layout.metrics)
        let seed = renderer.seed(
            text: ClockText.string(for: date),
            columns: display.layout.columns,
            rows: display.layout.rows,
            centre: clockCentre
        )
        display.grid.load(seed)
        // The ghost marks the seed cells themselves, so the digits stay
        // readable in place as Life eats them.
        display.rasterizer.setGhost(seed)
        currentSeed = seed
        seededMinute = minuteIndex(of: date)
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
    #endif

    /// Measures rather than assumes that a generation is cheap enough to run on
    /// the main actor. Logs an average every 100 generations in debug builds.
    private func record(step: Duration, raster: Duration, generation: Int) {
        #if DEBUG
        stepTotal += step
        rasterTotal += raster
        measuredGenerations += 1
        guard measuredGenerations == 100 else { return }

        func microseconds(_ total: Duration) -> Double {
            let components = (total / measuredGenerations).components
            return Double(components.seconds) * 1e6 + Double(components.attoseconds) / 1e12
        }
        Self.log.debug(
            "generation \(generation): step \(microseconds(self.stepTotal), format: .fixed(precision: 1))µs, raster \(microseconds(self.rasterTotal), format: .fixed(precision: 1))µs"
        )
        stepTotal = .zero
        rasterTotal = .zero
        measuredGenerations = 0
        #endif
    }
}
