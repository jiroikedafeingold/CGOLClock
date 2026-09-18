import SwiftUI
import os
#if canImport(UIKit)
import UIKit
#endif

/// Full-bleed Game of Life clock.
///
/// The grid image is rendered at one texel block per cell and scaled up with
/// nearest-neighbour filtering, so the pixels stay square and hard-edged at any
/// size. In pixel resolution the image is already at device scale and is shown
/// one-to-one.
///
/// The geometry reader deliberately does *not* ignore the safe area — it needs
/// the real insets to centre the digits on the visible area. The grid itself is
/// then expanded back out to the full screen so Life runs edge to edge.
struct ClockView: View {
    @State private var model = ClockViewModel()
    @State private var settings = ClockSettings()
    @State private var showsControls = false
    @State private var showsSettings = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale

    /// How long the settings button lingers after a tap. Long enough to
    /// notice it and reach for it; short enough not to sit over the clock.
    private let controlLinger = Duration.seconds(8)

    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let fullSize = CGSize(
                width: proxy.size.width + insets.leading + insets.trailing,
                height: proxy.size.height + insets.top + insets.bottom
            )
            let configuration = ClockViewModel.DisplayConfiguration(
                viewSize: fullSize,
                safeRect: CGRect(
                    origin: CGPoint(x: insets.leading, y: insets.top),
                    size: proxy.size
                ),
                displayScale: displayScale,
                palette: settings.palette,
                resolution: settings.resolution,
                face: settings.face
            )

            ZStack {
                Color(settings.palette.background)
                if let frame = model.frame {
                    Image(decorative: frame, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: fullSize.width, height: fullSize.height)
            .offset(x: -insets.leading, y: -insets.top)
            .contentShape(.rect)
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.2)) { showsControls = true }
            }
            .onChange(of: configuration, initial: true) { _, configuration in
                model.apply(configuration)
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
        .overlay(alignment: .topTrailing) { settingsButton }
        .background(Color(settings.palette.background).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsSettings) {
            SettingsView(settings: settings)
        }
        // Fades the button back out, unless the sheet is up or another tap
        // restarts the wait.
        .task(id: TimerKey(visible: showsControls, presenting: showsSettings)) {
            guard showsControls, !showsSettings else { return }
            try? await Task.sleep(for: controlLinger)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) { showsControls = false }
        }
    }

    @ViewBuilder
    private var settingsButton: some View {
        if showsControls {
            Button {
                showsSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .padding(10)
                    .background(.ultraThinMaterial, in: .circle)
            }
            .tint(.primary)
            .padding(20)
            .transition(.opacity)
            .accessibilityLabel("Display settings")
        }
    }

    /// Restarts the auto-hide countdown when either input changes.
    private struct TimerKey: Equatable {
        let visible: Bool
        let presenting: Bool
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

#Preview {
    ClockView()
}
