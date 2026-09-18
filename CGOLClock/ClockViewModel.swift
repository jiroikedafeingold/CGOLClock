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

    /// Generations per second at the start and end of the evolving part of the
    /// minute. The curve between them is exponential, which works out to
    /// roughly 590 generations after the hold.
    private let fastRate = 30.0
    private let slowRate = 2.0

    private let renderer = SevenSegmentRenderer()
    private var display: Display?
    private var seededMinute: Int?
    /// Where the digits are centred, in grid coordinates.
    private var clockCentre = CellPoint(x: 0, y: 0)

    /// The three pieces that have to be resized together.
    private struct Display {
        let layout: GridLayout
        let grid: LifeGrid
        let rasterizer: FrameRasterizer
    }

    // MARK: - Layout

    /// Rebuilds the grid for a new view size. Cheap and idempotent when the
    /// size resolves to the same layout, so it is safe to call on every pass.
    ///
    /// The grid always covers the whole screen — Life runs edge to edge, under
    /// the notch and home indicator — but the digits are centred on `safeRect`
    /// so they read as centred to the eye.
    func resize(to viewSize: CGSize, safeRect: CGRect) {
        let layout = GridLayout(viewSize: viewSize)
        let centre = layout.cell(at: CGPoint(x: safeRect.midX, y: safeRect.midY))
        guard display?.layout != layout || clockCentre != centre else { return }
        clockCentre = centre

        let display = Display(
            layout: layout,
            grid: LifeGrid(width: layout.columns, height: layout.rows),
            rasterizer: FrameRasterizer(columns: layout.columns, rows: layout.rows)
        )
        self.display = display
        // Seed straight away so a resize never shows a blank frame.
        reseed(display, at: Date())
        frame = display.rasterizer.image(for: display.grid)

        #if DEBUG
        Self.log.debug(
            """
            view \(viewSize.width, format: .fixed(precision: 1))x\(viewSize.height, format: .fixed(precision: 1)) \
            -> \(layout.columns)x\(layout.rows) cells at \(layout.cellSize, format: .fixed(precision: 2))pt; \
            safe \(safeRect.minX, format: .fixed(precision: 1)),\(safeRect.minY, format: .fixed(precision: 1)) \
            \(safeRect.width, format: .fixed(precision: 1))x\(safeRect.height, format: .fixed(precision: 1)) \
            mid \(safeRect.midX, format: .fixed(precision: 1)),\(safeRect.midY, format: .fixed(precision: 1)); \
            centre cell \(centre.x),\(centre.y) of \(layout.columns)x\(layout.rows)
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
        let seed = renderer.seed(
            text: ClockText.string(for: date),
            columns: display.layout.columns,
            rows: display.layout.rows,
            centre: clockCentre
        )
        display.grid.load(seed)
        display.rasterizer.setOutline(seed.outline())
        seededMinute = minuteIndex(of: date)
    }

    /// Seconds to wait before the next generation. During the hold this is the
    /// whole remainder of the hold, so the untouched digits are rasterised once
    /// and the loop sleeps straight through to the first generation.
    private func interval(at date: Date) -> Double {
        let elapsed = secondsIntoMinute(date)
        guard elapsed >= holdDuration else { return holdDuration - elapsed }

        let progress = min(max((elapsed - holdDuration) / (60 - holdDuration), 0), 1)
        let rate = fastRate * pow(slowRate / fastRate, progress)
        return 1 / rate
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
