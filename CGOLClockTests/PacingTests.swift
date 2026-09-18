import Foundation
import Testing
@testable import CGOLClock

@Suite("Generation pacing")
@MainActor
struct PacingTests {
    let model = ClockViewModel()

    @Test("The rate ramps up, peaks, then decays")
    func rateCurveShape() {
        let justAfterHold = model.rate(at: 3.0)
        let midRamp = model.rate(at: 6.0)
        let atPeak = model.rate(at: 9.0)
        let endOfMinute = model.rate(at: 60.0)

        #expect(justAfterHold < midRamp)
        #expect(midRamp < atPeak)
        #expect(endOfMinute < atPeak)
        // Opens at a middle pace: brisk enough not to read as stalled, but
        // well short of the peak so the bars visibly come apart.
        #expect(justAfterHold >= 4)
        #expect(justAfterHold <= 6)
        #expect(justAfterHold < atPeak * 0.7)
        #expect(endOfMinute <= 2)
        #expect(atPeak <= 12)
    }

    @Test("The ramp eases in rather than lurching")
    func rampEasesIn() {
        // Smoothstep: the first second of ramp adds less than a linear share.
        let start = model.rate(at: 3.0)
        let afterOneSecond = model.rate(at: 4.0)
        let atPeak = model.rate(at: 9.0)

        let gained = afterOneSecond - start
        let linearShare = (atPeak - start) / 6
        #expect(gained < linearShare)
    }

    @Test("The rate never stalls or runs away")
    func rateStaysInBounds() {
        for tenths in 30...600 {
            let rate = model.rate(at: Double(tenths) / 10)
            #expect(rate >= 1, "stalled at \(Double(tenths) / 10)s")
            #expect(rate <= 12, "ran away at \(Double(tenths) / 10)s")
        }
    }

    @Test("The rate is monotonic within each phase")
    func rateIsMonotonic() {
        func sample(_ range: ClosedRange<Int>) -> [Double] {
            range.map { model.rate(at: Double($0) / 10) }
        }
        let ramp = sample(30...90)
        let decay = sample(90...600)

        #expect(zip(ramp, ramp.dropFirst()).allSatisfy { $0 <= $1 }, "ramp should never dip")
        #expect(zip(decay, decay.dropFirst()).allSatisfy { $0 >= $1 }, "decay should never rise")
    }

    /// Integrating the curve gives the generations per minute. Enough to reach
    /// a settled field, few enough that the decay is watchable.
    @Test("A minute yields a few hundred generations")
    func generationsPerMinute() {
        var total = 0.0
        var elapsed = 3.0
        while elapsed < 60 {
            let step = 1 / model.rate(at: elapsed)
            elapsed += step
            total += 1
        }
        #expect(total > 150)
        #expect(total < 400)
    }
}
