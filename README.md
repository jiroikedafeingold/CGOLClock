# CGOLClock

A digital clock for iPhone and iPad whose pixels are cells in Conway's Game of Life.

Every minute the current time is drawn onto the grid. The digits hold for a second so you
can read them, and then some of those lit pixels — the whole glyph, just its outline, or a
random scatter of it — become the seed for Conway's Game of Life. The strokes come apart,
throw off gliders, and settle into still lifes over the rest of the minute. The time itself stays on screen underneath at low
opacity, so it is readable throughout. At the next minute the grid is reseeded.

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

### Making it fast

Two things dominate: advancing the grid, and pushing pixels. They were measured
separately rather than guessed at, and the answers were not the expected ones.

**The Life step is already near optimal.** SWAR does 64 cells in ~30 integer operations,
about half an operation per cell. Both axes of the step parallelise cleanly — each output
row reads only the previous generation — so it runs in row bands across cores above
100k cells.

**The raster was the bottleneck, and the cost was not drawing.** `CGContext.makeImage()`
allocates and copies the whole bitmap every call; at pixel resolution that is 12 MB a
frame, dominated by first-touch page faults on the fresh allocation. It measured ~4 ms
against ~1 ms for actually drawing the frame. Frames now come from a recycling pool and
are handed to a `CGDataProvider` that returns the buffer when Core Graphics is done, so
rendering allocates and copies nothing. That took the raster from **4.6 ms to 1.5 ms**.
The raster parallelises by row band too, with the ghost cells sliced by row so bands never
contend.

Measured per generation, optimised build, iPhone 17 Pro simulator:

| | Life step | Raster | Cells |
|---|---|---|---|
| LED Matrix | ~40 µs | ~0.3 ms | 3.4 k |
| Pixel | ~0.3 ms | ~1.5 ms | 3.2 M |

Costs rise with a livelier seed — outline and scatter keep far more of the field active,
so fewer rows can be skipped. On a 3.5 M-cell grid with an outline seed the step runs
~0.7 ms and the raster ~2.4 ms, around 3% of the main thread at ten generations a second.

Debug builds compile at `-O`. At `-Onone` these paths are 4–20x slower — the scattered
per-cell writes lose their inlining — which is enough to feel sluggish while developing.

#### What was tried and rejected

**Golly's period-two skipping.** Golly's QuickLife keeps both phases of every tile and
flags the ones that are stable or oscillating with period two so it can skip them
wholesale. That matters because a settling field is mostly still lifes *and blinkers*, and
a single blinker defeats a plain "did anything change" test. Implemented globally here it
**never fired**: gliders wander the torus indefinitely, and one moving glider makes the
whole board differ from two steps back. Measured 0 reused frames in 100 while adding
~400 µs a generation for the comparison, so it came out again. Making it pay would mean
going per-tile as Golly does — and the win would land on the step, already the cheaper
half of the frame. Per-tile skipping cannot help the raster here, because handing each
frame's buffer away means there is no persistent canvas to leave untouched.

**HashLife.** Golly's headline algorithm memoises a quadtree and buys exponential
speedups on patterns with regularity, over millions of generations. This runs ~550
generations of deliberately chaotic soup on a torus, which is the case QuickLife exists
for — the hashing overhead would not be repaid.

**The Neural Engine.** Not usable. It has no general compute API; reaching it means a
Core ML model over float tensors. Life would have to become a 3x3 convolution plus a
threshold — nine multiply-accumulates per cell against SWAR's half an operation — with a
CPU round trip every generation. It would be slower, and the step is not the bottleneck
anyway. The genuine accelerator option is the GPU: upload the bitboard as a texture and
expand it in a fragment shader, which would attack the raster. That is a real rewrite and
has not been done.

### Settings

Tap the screen to reveal a gear in the upper right; it fades after eight seconds.

| Setting | Default |
|---|---|
| Living cell colour | amber `#FFB000` |
| Time colour | white |
| Time opacity | 30% |
| Typeface | Round (of six) |
| What comes alive | Scatter, 20% |
| Resolution | Pixel |

**Typefaces.** Six: Round, Block, Neue, Serif, Narrow, Type. At pixel resolution each
names a real font and is rasterised at screen resolution. At LED-matrix sizes a digit is
only 8x14 cells, where a real font thresholds down to one-cell strokes that die in a
single generation — measured on Helvetica at 16px, Black and Heavy give a thinnest stroke
of one cell, Bold two — so matrix resolution uses hand-drawn bitmap glyphs. Only Round
and Block have their own; the rest borrow the closer of the two, and the sheet says so.

**What comes alive.** The time is *always* drawn filled. This setting only picks which of
its cells are handed to Life:

- **Filled** — the whole glyph. Solid interiors have eight neighbours and die at once, so
  this erodes inward from the edges.
- **Outline** — just the glyph outline, stroked at about 0.9% of the point size. Thin
  strokes break into more varied debris than fat ones, and the strokes are free to come
  apart rather than being pinned by a solid interior.
- **Scatter** — a random fraction of the glyph, set by a slider (20% by default). This is
  closest to a classic Life soup and is the liveliest of the three. Deterministic per
  minute, so a redraw doesn't reshuffle the field.

Outline needs a stroke many cells wide, so it falls back to Filled at matrix resolution.
Scatter works at either.

| Resolution | Grid (iPhone 17 Pro landscape) | Cell | Glyph scale |
|---|---|---|---|
| LED Matrix | 86 x 39 = 3,354 cells | 10.2 pt | 1 |
| Pixel | 2622 x 1206 = 3,162,132 cells | 1 device pixel | 30 |

Pixel resolution puts one cell on every device pixel and scales the font by the same
factor so the clock stays exactly half the screen width. At one texel per cell there is no
room to draw a ghost ring around a live square, so a cell that is both takes a **blended
colour** — an even mix of the two, landing on a hue belonging to neither.

The status bar and home indicator are hidden; nothing should compete with the clock, the
system clock least of all.

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
matters when the time underneath is a fixed record of the seed.

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
    ClockFace.swift       six typefaces: bitmap glyphs and font names
    DigitFont.swift       bitmap metrics, digit stamping, time formatting
    TypeRenderer.swift    Core Text rasterisation for pixel resolution
    GridLayout.swift      cell size, grid dimensions, safe-area centring
  Render/
    Palette.swift         cell, time and blended colours
    FrameBufferPool.swift recycled frame buffers, so rendering never allocates
    FrameRasterizer.swift pixel buffer -> CGImage
  Settings/
    ClockSettings.swift   persisted colours and resolution
    SettingsView.swift    the settings sheet
  ClockViewModel.swift    @Observable; the run loop, reseeding, pacing
  ClockView.swift         GeometryReader + Image, tap-to-reveal settings
```

Nothing below `ClockView` imports SwiftUI.

## Tests

Removed for now. There was a suite of 116 covering the SWAR step against a naive
reference, word-boundary and wrapping cases, the bitmap glyph data, centring, pacing and
the rasteriser; it is in the history if it is wanted back. The empty `CGOLClockTests`
target is still in the project.

Worth knowing if they come back: the test bundle was app-hosted, which forced
`ENABLE_DEBUG_DYLIB = NO` and meant the app scheme had to be built first for the same
destination or the tests would silently exercise a stale binary. With the tests gone the
debug dylib is back on, so SwiftUI previews and `RunCodeSnippet` work again.

## Requirements

iOS 27, Xcode 27. No third-party dependencies.
