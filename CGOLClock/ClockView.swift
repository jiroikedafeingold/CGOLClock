import SwiftUI
import os
#if canImport(UIKit)
import UIKit
#endif

/// Full-bleed Game of Life clock.
///
/// The grid image is rendered at one texel block per cell and scaled up with
/// nearest-neighbour filtering, so the pixels stay square and hard-edged at any
/// size. The grid is always 76 columns wide, which means an iPad shows the same
/// layout as an iPhone with physically larger cells rather than more of them.
///
/// The geometry reader deliberately does *not* ignore the safe area — it needs
/// the real insets to centre the digits on the visible area. The grid itself is
/// then expanded back out to the full screen so Life runs edge to edge.
struct ClockView: View {
    @State private var model = ClockViewModel()
    @Environment(\.scenePhase) private var scenePhase

    private let palette = Palette.amberLED

    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let fullSize = CGSize(
                width: proxy.size.width + insets.leading + insets.trailing,
                height: proxy.size.height + insets.top + insets.bottom
            )
            let safeRect = CGRect(
                origin: CGPoint(x: insets.leading, y: insets.top),
                size: proxy.size
            )

            ZStack {
                Color(palette.background)
                if let frame = model.frame {
                    Image(decorative: frame, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: fullSize.width, height: fullSize.height)
            .offset(x: -insets.leading, y: -insets.top)
            .onChange(of: safeRect, initial: true) { _, rect in
                model.resize(to: fullSize, safeRect: rect)
            }
            // Restarts on scene phase changes; idle while backgrounded so an
            // inactive window isn't stepping the grid ten times a second.
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                // `run()` returns when the task is cancelled, so the display
                // assertion is always released on the way out.
                keepDisplayAwake(true)
                defer { keepDisplayAwake(false) }
                await model.run()
            }
        }
        .background(Color(palette.background).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

/// Stops the display dimming while the clock is on screen.
///
/// Apple's guidance is to leave the idle timer alone unless the app needs to
/// keep showing content with minimal interaction — which is precisely a clock
/// you glance at from across the room. There is no SwiftUI equivalent, so this
/// reaches for `UIApplication`; it is a no-op where UIKit isn't available.
@MainActor
private func keepDisplayAwake(_ awake: Bool) {
    #if canImport(UIKit)
    UIApplication.shared.isIdleTimerDisabled = awake
    #if DEBUG
    // Read back rather than assume the assertion took.
    Logger(subsystem: "com.feingold5.CGOLClock", category: "display")
        .debug("idle timer disabled: \(UIApplication.shared.isIdleTimerDisabled)")
    #endif
    #endif
}

private extension Color {
    init(_ rgb: RGB) {
        self.init(
            .sRGB,
            red: Double(rgb.red) / 255,
            green: Double(rgb.green) / 255,
            blue: Double(rgb.blue) / 255
        )
    }
}

#Preview {
    ClockView()
}
