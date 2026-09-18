import Foundation

nonisolated struct RGB: Equatable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    init(_ red: UInt8, _ green: UInt8, _ blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Packed for a `byteOrder32Little` + `noneSkipFirst` bitmap context.
    var packed: UInt32 {
        0xFF00_0000 | UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue)
    }

    func blended(over base: RGB, alpha: Double) -> RGB {
        func mix(_ top: UInt8, _ bottom: UInt8) -> UInt8 {
            UInt8((Double(top) * alpha + Double(bottom) * (1 - alpha)).rounded())
        }
        return RGB(mix(red, base.red), mix(green, base.green), mix(blue, base.blue))
    }
}

/// Colours for the display. Amber cells on near-black, with a teal ghost of the
/// original digits so the time stays readable as the field decays.
nonisolated struct Palette {
    let background: RGB
    let live: RGB
    let ghost: RGB
    let ghostOpacity: Double

    static let amberLED = Palette(
        background: RGB(0x0A, 0x08, 0x06),
        live: RGB(0xFF, 0xB0, 0x00),
        ghost: RGB(0x34, 0xD3, 0xC8),
        ghostOpacity: 0.42
    )

    /// The ghost already composited over the background, so the rasteriser
    /// writes opaque texels and never has to blend per frame.
    ///
    /// The opacity is tuned for a one-texel stroke, which reads far lighter
    /// than a filled square would at the same value — and it has to stay
    /// legible where it crosses a lit cell, not just the background.
    var ghostOverBackground: RGB {
        ghost.blended(over: background, alpha: ghostOpacity)
    }
}
