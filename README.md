# CGOLClock

A digital clock for iPhone and iPad whose pixels are cells in Conway's Game of Life.

Every minute the current time is drawn onto the grid. The digits hold for a second so you
can read them, and then those lit pixels become the seed for Conway's Game of Life. The strokes come apart, throw off gliders, and settle into
still lifes over the rest of the minute. A subtle teal ghost marks the cells the digits
started from, so the time is still readable long after the amber cells have scattered. At
the next minute the grid is reseeded with the new time.

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

### Rendering

The grid is rasterised into a `CGImage`. In LED Matrix resolution that is one `8x8` texel
block per cell with a `6x6` square inside it — the leftover row and column are the dark
gutter — and the view scales it up with `.interpolation(.none)`, so the GPU does the
magnification and the pixels stay hard-edged. In Pixel resolution it is one texel per cell
and is displayed one-to-one.

Each frame draws in three passes: background, then live cells as filled squares, then the
ghost. The ghost marks **the cells the digits started from** and goes **last**, so it is
never painted over — which is why it can't be baked into a static template. Where a cell
is big enough the ghost is a hollow ring, so a live cell reads as a square inside a frame
and a dead one as an empty frame; at one texel per cell it blends instead.

Live cells are found by walking set bits with `trailingZeroBitCount` rather than scanning
all 64 columns per word.

Measured per generation on an iPhone 17 Pro simulator, optimised build:

| | Life step | Raster | Cells |
|---|---|---|---|
| LED Matrix | ~40 µs | ~0.3 ms | 3.4 k |
| Pixel | ~0.3 ms | ~5 ms | 3.2 M |

At the peak rate of 10 generations a second even pixel resolution is around 6% of the
main thread, which is why none of this needs to leave the main actor. A `#if DEBUG`
logger reports the numbers rather than leaving it to assumption.

Debug builds are compiled with `-O` rather than the usual `-Onone`. At `-Onone` these
paths are 4–20x slower — pixel resolution measures ~3 ms step and ~20 ms raster, enough to
feel sluggish — because the scattered per-cell writes lose their inlining, not because of
any memory-bandwidth wall. The trade is that stepping through this code in the debugger is
less pleasant; flip `SWIFT_OPTIMIZATION_LEVEL` back if you need that.

### Settings

Tap the screen to reveal a gear in the upper right; it fades after eight seconds. The
sheet sets the cell colour, the time colour, the typeface, and the resolution. Changing a
colour or a typeface redraws in place rather than restarting the simulation.

| Resolution | Grid (iPhone 17 Pro landscape) | Cell | Glyph scale |
|---|---|---|---|
| LED Matrix | 86 x 39 = 3,354 cells | 10.2 pt | 1 |
| Pixel | 2622 x 1206 = 3,162,132 cells | 1 device pixel | 30 |

Pixel resolution puts one cell on every device pixel, and scales the font up by the same
factor so the clock stays exactly half the screen width. The digits therefore look the
same size in both modes — they just erode a grain at a time instead of a block at a time,
because a stroke that was 2 cells thick is now 60.

At one texel per cell there is no room to draw a ghost ring around a live square, so a
cell that is both takes a **blended colour** instead — an even mix of the two, which
lands on a hue belonging to neither. During the three-second hold every seed cell is both
live and ghost, so the whole clock shows in that mixed colour and then resolves towards
the time colour as Life eats the interiors.

### Layout

The grid is always **86 columns**. That is not arbitrary: an `HH:MM` block is 43 cells
wide with the standard glyph metrics (four 8-wide digits, a 3-wide colon, four 2-wide
gaps), so 86 columns puts the clock at exactly half the screen width. Cell size then falls
out of the view width, which means a larger screen gets physically larger cells rather
than more of them — the chunky look survives the jump from iPhone to iPad.

| Device | Grid | Cell size |
|---|---|---|
| iPhone 17 Pro, landscape | 86 x 39 | 10.2 pt |
| iPad Pro 13", landscape | 86 x 64 | 16.0 pt |

Digits are centred on the **safe area**, not the raw screen, so the home indicator and
Dynamic Island don't push them off-centre. They are also centred on their *drawn extent*
rather than a fixed five-slot block — otherwise a single-digit hour like `9:45` sits
visibly to the right.

Digit slots are a fixed width, so a narrow glyph like `1` doesn't get re-centred inside
its slot. That keeps every other digit in the same place as the time changes, which
matters when the teal ghost is a fixed record of the seed.

### The typefaces

Two faces, **Round** and **Block**, each realised two ways depending on how big a cell is.

**At LED-matrix sizes** a digit is 8x14 cells and the face uses hand-drawn bitmap glyphs,
kept as ASCII art in `ClockFace.swift`. This isn't nostalgia — a real font thresholded at
14 cells tall comes out with one-cell strokes, and a one-cell stroke has too few
neighbours to survive its first generation. Measured: Helvetica Bold at 16px gives a
thinnest stroke of 2 cells, Black and Heavy give 1. The hand-drawn glyphs are two cells
thick everywhere, and a test enforces that no cell has fewer than two neighbours.

The shapes also deliberately avoid the trap the original seven-segment renderer fell into:
those glyphs were all built from the same seven axis-aligned bars, so every digit was
near-symmetric and they all decayed alike. Round mixes closed bowls (0, 6, 8), long
diagonals (1, 2, 4, 7) and open tails (3, 5, 9); Block is all right angles. Tests assert
the set isn't mirror- or flip-symmetric and that every pair of digits differs by at least
six cells.

**At pixel resolution** there is no reason to blow an 8x14 bitmap up thirty times, so the
face names a real font — Avenir Next Heavy for Round, Menlo Bold for Block — and
`TypeRenderer` rasterises the time with Core Text at the grid's own resolution and
thresholds it. The digits get genuine curves, and Life erodes a smooth shape rather than a
staircase. The renderer measures the string at a reference size and scales to the
requested cell width, so the clock stays half the screen wide whichever face is picked.

### Pacing

```
0s ─ 1s ──────────── 7s ─────────────────────────────────── 60s
 hold    ramp up           hold at speed
         5 → 10 gen/s      10 gen/s
```

Roughly 560 generations a minute. The rate eases in so the first few generations — where
the strokes come apart — are watchable, then holds; the field usually settles into still
lifes and blinkers well before the minute is out, and holding the pace looks better than
watching a frozen grid tick over slowly. The run loop sleeps for exactly one
inter-generation interval rather than running on a display link — nothing on screen
changes between generations, so there is no reason to wake up for frames that would be
identical.

The display is kept awake while the clock is on screen (`isIdleTimerDisabled`), released
whenever the scene stops being active.

## Structure

```
CGOLClock/
  Life/
    CellBitmap.swift      bit-per-cell grid, shared layout with LifeGrid
    LifeGrid.swift        SWAR bitboard, toroidal wrap, the step
    ClockFace.swift       the two typefaces: bitmap glyphs and font names
    DigitFont.swift       bitmap metrics, digit stamping, time formatting
    TypeRenderer.swift    Core Text rasterisation for pixel resolution
    GridLayout.swift      cell size, grid dimensions, safe-area centring
  Render/
    Palette.swift         amber on black, teal ghost
    FrameRasterizer.swift pixel buffer -> CGImage
  Settings/
    ClockSettings.swift   persisted colours and resolution
    SettingsView.swift    the settings sheet
  ClockViewModel.swift    @Observable; the run loop, reseeding, pacing
  ClockView.swift         GeometryReader + Image, tap-to-reveal settings
```

Nothing below `ClockView` imports SwiftUI.

## Tests

116 tests, Swift Testing. The ones worth knowing about:

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
- **Rasterising**, by reading texels back out of the rendered `CGImage`: that a ghost cell
  is a hollow ring with a dark centre, and that the ring stays teal while the interior
  turns amber when a live cell shares the cell.
- **Resolution and settings**: that the clock stays half the screen width in both modes
  despite a 30x difference in grid fineness, that a scaled glyph is exactly the base glyph
  blown up, that a live-and-ghost cell takes the combined colour, and that choices survive
  a relaunch.
- **The bitmap faces**, since they're hand-drawn data that's easy to get subtly wrong —
  every check runs against both. Every glyph is the declared size and doesn't spill past
  it, all ten are pairwise distinct by at least six cells, no cell is isolated enough to
  evaporate in one generation, and the set isn't mirror- or flip-symmetric. The
  neighbour-count check caught a one-cell spur on Block's `1` before it shipped.
- **The Core Text path**, by asserting what distinguishes it from a scaled bitmap: stroke
  widths take many distinct values rather than multiples of a scale factor, and a round
  glyph's left edge wanders instead of stepping.

### Running them

The test bundle is hosted by the app, and the `CGOLClockTests` scheme does not rebuild the
app target. **Always build the `CGOLClock` scheme first**, for the same destination — the
tests run inside the app binary, so a stale one silently exercises old code rather than
failing to link.

```
xcodebuild -scheme CGOLClock     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -scheme CGOLClockTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## Requirements

iOS 27, Xcode 27. No third-party dependencies.
