import SwiftUI

struct SettingsView: View {
    @Bindable var settings: ClockSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Colours") {
                    ColorPicker("Living cells", selection: $settings.live.color, supportsOpacity: false)
                    ColorPicker("Time", selection: $settings.ghost.color, supportsOpacity: false)
                    opacitySlider
                    swatch
                }

                Section {
                    Picker("Typeface", selection: $settings.face) {
                        ForEach(ClockFace.allCases) { face in
                            Text(face.name).tag(face)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Typeface")
                } footer: {
                    Text(typefaceFooter)
                }

                Section {
                    Picker("Cells from", selection: $settings.seedStyle) {
                        ForEach(SeedStyle.allCases) { style in
                            Text(style.name).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)

                    if settings.seedStyle == .scattered {
                        scatterSlider
                    }
                } header: {
                    Text("What comes alive")
                } footer: {
                    Text(seedFooter)
                }

                Section {
                    Picker("Resolution", selection: $settings.resolution) {
                        ForEach(Resolution.allCases) { resolution in
                            Text(resolution.name).tag(resolution)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(settings.resolution.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Resolution")
                }

                Section {
                    Button("Reset to Defaults", role: .destructive) {
                        settings.resetToDefaults()
                    }
                }
            }
            .navigationTitle("Display")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var typefaceFooter: String {
        settings.outlineIsAvailable
            ? "Drawn with a real font at full screen resolution."
            : """
                Matrix resolution draws from built-in pixel glyphs — Round and Block differ \
                there, the rest borrow the closest.
                """
    }

    /// The time is always drawn filled; this only picks the Life seed.
    private var seedFooter: String {
        switch settings.effectiveSeedStyle {
        case .filled:
            let unavailable = settings.seedStyle == .outline
                ? " Outline needs Pixel resolution, where a stroke is many cells wide."
                : ""
            return "The whole of each digit comes alive, eroding inward from the edges."
                + unavailable
        case .outline:
            return "Only the outline comes alive. The time itself stays filled."
        case .scattered:
            return """
                A random \(settings.scatterDensity.formatted(.percent.precision(.fractionLength(0)))) \
                of each digit comes alive — closest to a classic Life soup. The time itself \
                stays filled.
                """
        }
    }

    private var scatterSlider: some View {
        VStack(alignment: .leading, spacing: 2) {
            LabeledContent("Density") {
                Text(settings.scatterDensity.formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $settings.scatterDensity, in: 0.05...1) {
                Text("Scatter density")
            }
        }
    }

    private var opacitySlider: some View {
        VStack(alignment: .leading, spacing: 2) {
            LabeledContent("Time opacity") {
                Text(settings.timeOpacity.formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $settings.timeOpacity, in: 0.05...1) {
                Text("Time opacity")
            }
        }
    }

    /// Shows the colours the display actually uses, including the mixed one —
    /// which is otherwise hard to predict from the two you picked.
    private var swatch: some View {
        let palette = settings.palette
        return LabeledContent("Preview") {
            HStack(spacing: 6) {
                chip(palette.live, label: "cell")
                chip(palette.ghostOverBackground, label: "time")
                if settings.resolution == .pixel {
                    chip(palette.overlap, label: "both")
                }
            }
        }
    }

    private func chip(_ rgb: RGB, label: String) -> some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(rgb))
                .frame(width: 30, height: 18)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.separator))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) colour")
    }
}

extension Color {
    init(_ rgb: RGB) {
        self.init(
            .sRGB,
            red: Double(rgb.red) / 255,
            green: Double(rgb.green) / 255,
            blue: Double(rgb.blue) / 255
        )
    }
}

extension RGB {
    /// Bridges to SwiftUI's `Color` so `ColorPicker` can bind straight to the
    /// stored value. Resolving back out goes through the sRGB components.
    var color: Color {
        get { Color(self) }
        set {
            let resolved = newValue.resolve(in: EnvironmentValues())
            func byte(_ value: Float) -> UInt8 {
                UInt8((min(max(value, 0), 1) * 255).rounded())
            }
            self = RGB(byte(resolved.red), byte(resolved.green), byte(resolved.blue))
        }
    }
}

#Preview {
    SettingsView(settings: ClockSettings(defaults: UserDefaults(suiteName: "preview")!))
}
