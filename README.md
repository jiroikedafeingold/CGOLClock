# CGOLClock

A digital clock for iPhone and iPad whose pixels are cells in Conway's Game of Life.

Every minute the current time is drawn as chunky seven-segment digits on an LED-matrix
grid. The digits hold for three seconds so you can read them, and then those lit pixels
become the seed for Conway's Game of Life. The bars come apart, throw off gliders, and
settle into still lifes over the rest of the minute. A subtle teal ghost of the original
digits stays behind, so the time is still readable long after the amber cells have
scattered. At the next minute the grid is reseeded with the new time.

Landscape, full-bleed, iPhone and iPad.

## How it works

### The Life step is bit-parallel

`LifeGrid` stores one bit per cell in an array of `UInt64`, and advances all 64 cells in
a word together using bit-sliced arithmetic — no per-cell loop.

The eight neighbour masks (three from the row above, two from the current row, three from
the row below) are summed with bitwise half and full adders into four bit-planes `n0…n3`
that hold the neighbour count in binary, 64 lanes at a time:

```swift
let (aLow, aHigh) = add3(aWest, aCentre, aEast)   // row above,  0...3
let (cLow, cHigh) = add3(cWest, cCentre, cEast)   // row below,  0...3
let bLow  = bWest ^ bEast                          // same row,   0...2
let bHigh = bWest & bEast
```

Those partials combine into `n0…n3`, and then the whole survival rule is three operations:

```swift
let twoOrThree = n1 & ~(n2 | n3)
next = twoOrThree & (n0 | bCentre)   // born on 3, survive on 2 or 3
```

That works out to about 30 integer operations per 64 cells. Rows whose three-row
neighbourhood is entirely empty are skipped wholesale, which is most of the grid for most
of a minute.

Both axes wrap. Vertical wrap is modular row indexing; horizontal wrap is a rotate across
the row's word array, which has to account for `width` not being a multiple of 64. That
last part is where the bodies are buried, so it is tested directly.

### Rendering is a memcpy plus one write per live cell

The grid is rasterised into a small `CGImage` — one `4x4` texel block per cell, with a
`3x3` lit square inside it. The leftover row and column are the dark gutter that gives the
LED-matrix look. The view then scales that image up with `.interpolation(.none)`, so the
GPU does the magnification and the pixels stay hard-edged.

The background and the static teal outline are baked into a template buffer once per
minute. Rendering a generation is a `memcpy` of that template followed by one small write
per live cell, found by walking set bits with `trailingZeroBitCount` rather than scanning
columns.

Measured on an iPhone 17 Pro simulator in a Debug (`-Onone`) build: **~40µs** for the Life
step and **~250µs** for the raster, per generation. At the peak rate of 10 generations a
second that is well under 1% of the main thread, which is why none of this needs to leave
the main actor. A `#if DEBUG` logger reports those numbers rather than leaving it to
assumption.

### Layout

The grid is always **76 columns**. That is not arbitrary: an `HH:MM` block is 38 cells
wide with the standard glyph metrics, so 76 columns puts the clock at exactly half the
screen width. Cell size then falls out of the view width, which means a larger screen gets
physically larger cells rather than more of them — the chunky look survives the jump from
iPhone to iPad.

| Device | Grid | Cell size |
|---|---|---|
| iPhone 17 Pro, landscape | 76 x 34 | 11.5 pt |
| iPad Pro 13", landscape | 76 x 57 | 18.1 pt |

Digits are centred on the **safe area**, not the raw screen, so the home indicator and
Dynamic Island don't push them off-centre. They are also centred on their *drawn extent*
rather than a fixed five-slot block — otherwise a single-digit hour like `9:45` sits
visibly to the right.

Digit slots are a fixed width, so a `1` — which lights only segments b and c — sits
against the right of its slot rather than being re-centred. That keeps every other digit
in the same place as the time changes, which matters when the teal outline is a fixed
ghost of the seed.

### Pacing

```
0s ─────── 3s ──────────── 9s ─────────────────────────────── 60s
   hold        ramp up          exponential decay
   (digits)    5 → 10 gen/s     10 → 1.5 gen/s
```

Roughly 270 generations a minute. The run loop sleeps for exactly one inter-generation
interval rather than running on a display link — nothing on screen changes between
generations, so there is no reason to wake up for frames that would be identical.

Stroke thickness is two cells, deliberately. A one-cell-thick bar has too few neighbours
to survive and evaporates in a single generation; at two cells thick the bars die back
unevenly, shed gliders, and leave still-life blocks behind.

## Structure

```
CGOLClock/
  Life/
    CellBitmap.swift      bit-per-cell grid; seeds and the outline dilation
    LifeGrid.swift        SWAR bitboard, toroidal wrap, the step
    SevenSegment.swift    parametric digit stamping, time formatting
    GridLayout.swift      cell size, grid dimensions, safe-area centring
  Render/
    Palette.swift         amber on black, teal ghost
    FrameRasterizer.swift pixel buffer -> CGImage
  ClockViewModel.swift    @Observable; the run loop, reseeding, pacing
  ClockView.swift         GeometryReader + Image
```

Nothing below `ClockView` imports SwiftUI.

## Tests

58 tests, Swift Testing. The ones worth knowing about:

- **Cross-check against a naive implementation.** A dense pseudorandom soup is run for 30
  generations at widths 37, 64, 65, 76, 128 and 130 and compared cell-for-cell against a
  straightforward per-cell toroidal Life. This is the test that actually proves the SWAR
  step, and the widths are chosen to exercise exact, partial and multi-word rows.
- **Word-boundary cases.** A blinker straddling bit 63/64; a glider crossing the boundary;
  a blinker at the last column of a partial word; and a check that no bits ever survive
  past the declared width.
- **Wrapping.** Blinkers spanning each edge, and a glider that leaves the bottom-right
  corner and reappears at the top-left.
- **Centring and pacing**, including that the rate is monotonic within each phase and
  never stalls or runs away.

### Running them

The test bundle is hosted by the app, and the `CGOLClockTests` scheme does not rebuild the
app target. Build the `CGOLClock` scheme first, then run tests from `CGOLClockTests`:

```
xcodebuild -scheme CGOLClock     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -scheme CGOLClockTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## Requirements

iOS 27, Xcode 27. No third-party dependencies.
