# LidFold

A macOS menu bar app that folds your desktop as you close your MacBook.

It reads the hinge angle from your MacBook's built-in lid angle sensor and, as
the lid drops past ~75°, splits what's on screen at the horizontal midline and
pivots the top half backwards about the crease — so the desktop behaves like the
two halves of a folding screen while the real lid closes over it.

## Requirements

- Apple silicon MacBook with a lid angle sensor
- macOS 14 Sonoma or later
- Xcode Command Line Tools (full Xcode is *not* required)

Built and tested on a MacBook Pro (Mac17,2, M5) running macOS 26.5.

## Build

```bash
./Scripts/build-app.sh
open LidFold.app
```

Grant Screen Recording access when prompted — the effect works by capturing the
screen, so it does nothing without it.

Note that `build-app.sh` signs the bundle ad-hoc. macOS ties Screen Recording
consent to the code signature, so **every rebuild will re-prompt** for access.
That's expected, not a bug.

## Check your Mac has the sensor

```bash
swift build && ./.build/debug/LidFold --angle 10
```

Prints ten live angle readings. If it reports that no sensor was found, this app
can't work on your machine.

## Settings

Menu bar icon → Settings. Three styles weight the effects differently:

| Style | Perspective | Blur | Shadow |
| ----- | ----------- | ---- | ------ |
| Silk  | 1.00        | 0.60 | 0.45   |
| Shade | 0.70        | 0.20 | 1.00   |
| Frost | 0.35        | 1.00 | 0.30   |

The three sliders scale on top of whichever style is active.

## How it works

**Sensor** — the lid angle sensor is a HID device on the Sensor usage page
(`0x20`, usage `0x8A`). Feature report `1` returns three bytes: a report ID and
the angle as a little-endian 9-bit value in degrees. The element for that report
is usage `0x047F` with a logical range of 0...360. None of this is documented by
Apple; it was found by walking the device's HID element tree (see
`LidAngleSensor.swift`).

The reading jitters by about a degree at rest, so it's run through an exponential
smoother before driving anything visual — raw values make the overlay shimmer
while the lid is held still.

**Effect** — a borderless click-through window sits just below the shielding
window level. ScreenCaptureKit streams the display into two `CALayer` panels;
the top one has its anchor point on its bottom edge, so rotating it about the X
axis pivots it around the crease. Perspective is set as `m34` on the *container's*
`sublayerTransform` rather than per panel — applied per panel, the halves get
different vanishing points and the crease visibly tears.

The overlay excludes itself from the capture filter by `CGWindowID`. Without
that, it captures its own output and the image recurses.

Capture only runs while the lid is actually closing, and is torn down once it
reopens, so an idle machine isn't paying for a 60fps screen capture.

## Status

Working and verified:

- Sensor discovery and angle decoding, confirmed against live hardware
- Builds clean; launches and runs as a menu bar app
- Capture lifecycle, settings persistence, permission preflight

Not yet verified on hardware:

- **The fold visual during an actual lid close.** Every piece is wired up, but
  watching it happen means closing the lid, which is awkward to observe. Expect
  to tune `maxFoldRadians` and `eyeDistance` in `FoldView.swift` by eye.
- **Angle tracking across large travel.** Readings were confirmed live at
  113–114°, including real sensor noise, but not swept through the full range.
- **60fps sustained performance.** Full-screen capture plus a per-frame
  `CGImage` conversion is the likely bottleneck. If it drags, the fix is
  rendering the `CVPixelBuffer` through a `CAMetalLayer` instead of converting
  on the CPU each frame.

## License

MIT — see [LICENSE](LICENSE).
