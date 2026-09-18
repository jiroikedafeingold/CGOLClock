import Foundation
import Testing
@testable import CGOLClock

@Suite("Generation pacing")
@MainActor
struct PacingTests {
    let model = ClockViewModel()

    @Test("The rate ramps up and then holds")
    func rateCurveShape() {
        let hold = model.holdDuration
        let justAfterHold = model.rate(at: hold)
        let midRamp = model.rate(at: hold + model.rampDuration / 2)
        let atPeak = model.rate(at: hold + model.rampDuration)
        let endOfMinute = model.rate(at: 60.0)

        #expect(justAfterHold < midRamp)
        #expect(midRamp < atPeak)
        // Opens at a middle pace: brisk enough not to read as stalled, but
        // well short of the peak so the strokes visibly come apart.
        #expect(justAfterHold >= 4)
        #expect(justAfterHold <= 6)
        #expect(justAfterHold < atPeak * 0.7)
        #expect(atPeak <= 12)
        // Once at speed it stays there rather than winding down.
        #expect(endOfMinute == atPeak)
    }

    @Test("The ramp eases in rather than lurching")
    func rampEasesIn() {
        // Smoothstep: the first second of ramp adds less than a linear share
        // of the total climb.
        let hold = model.holdDuration
        let ramp = model.rampDuration
        let start = model.rate(at: hold)
        let afterOneSecond = model.rate(at: hold + 1)
        let atPeak = model.rate(at: hold + ramp)

        let gained = afterOneSecond - start
        let linearShare = (atPeak - start) / ramp
        #expect(gained < linearShare, "gained \(gained) in the first second, linear would be \(linearShare)")
    }

    @Test("The rate never stalls or runs away")
    func rateStaysInBounds() {
        for tenths in Int(model.holdDuration * 10)...600 {
            let rate = model.rate(at: Double(tenths) / 10)
            #expect(rate >= 4, "stalled at \(Double(tenths) / 10)s")
            #expect(rate <= 12, "ran away at \(Double(tenths) / 10)s")
        }
    }

    @Test("The rate never decreases")
    func rateIsMonotonic() {
        let samples = (Int(model.holdDuration * 10)...600).map { model.rate(at: Double($0) / 10) }
        #expect(
            zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 + 1e-9 },
            "the rate should only ever climb or hold"
        )
    }

    /// Integrating the curve gives the generations per minute.
    @Test("A minute yields several hundred generations")
    func generationsPerMinute() {
        var total = 0.0
        var elapsed = model.holdDuration
        while elapsed < 60 {
            elapsed += 1 / model.rate(at: elapsed)
            total += 1
        }
        #expect(total > 400)
        #expect(total < 700)
    }
}
