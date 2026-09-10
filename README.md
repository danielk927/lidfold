# LidFold

A macOS menu bar app that folds your desktop as you close your MacBook.

It reads the hinge angle from your MacBook's built-in lid angle sensor and, as
the lid drops past ~95°, counter-rotates what's on screen against the panel's
own rotation — so the desktop appears to hang still in space while the hardware
sweeps through it, frosting over and falling into the dark as the lid shuts.

## Requirements

- Apple silicon MacBook with a lid angle sensor
- macOS 14 Sonoma or later
- Xcode Command Line Tools (full Xcode is *not* required)

Built and tested on a MacBook Pro (Mac17,2, M5) running macOS 26.5.

## Install

```bash
git clone https://github.com/danielk927/lidfold.git
cd lidfold
./Scripts/install.sh
```

That builds it, puts it in `/Applications`, and launches it. Look for the
laptop icon in your menu bar, then close your lid.

macOS will ask for Screen Recording access the first time — the effect works by
capturing the screen, so it does nothing without it. Grant it, then quit LidFold
from the menu bar icon and open it again from `/Applications`: the permission
only takes effect on the next launch.

To build without installing, run `./Scripts/build-app.sh` and `open LidFold.app`.

macOS ties Screen Recording consent to the code signature. `build-app.sh` signs
with the first Developer ID or Apple Development identity it finds, which is
stable across rebuilds, so the grant is only needed once. Override it with
`CODESIGN_IDENTITY`. With no identity installed the script falls back to an
ad-hoc signature, which is keyed to the binary's own hash — every rebuild then
looks like a new app and macOS re-prompts.

## Check your Mac has the sensor

```bash
swift build && ./.build/debug/LidFold --angle 10
```

Prints ten live angle readings. If it reports that no sensor was found, this app
can't work on your machine.

## Using it

Close your lid. That's the whole interface.

The menu bar icon holds two things: a switch to stop the effect without quitting,
and Quit. There is nothing to configure — the look is fixed, deliberately.

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
window level, hosting an `MTKView`. ScreenCaptureKit's `CVPixelBuffer`s go
straight to the GPU through a `CVMetalTextureCache` (no per-frame `CGImage`
conversion), are blitted into a mipmapped texture, and a fragment shader does
the rest: for each pixel it works out where that pixel physically sits once the
panel has swung, casts from the eye through that point onto an upright screen
standing at the hinge, and samples wherever the ray lands — then reads the mip
chain on a golden-angle spiral for the frosted defocus. The hinge is the fixed
point of that mapping, which is what holds the bottom edge still while
everything above it sweeps. Doing it per pixel rather than by transforming
layers keeps the blur on the GPU, where a coarse mip costs what a fine one does.

The shader is compiled from source at startup. SwiftPM doesn't build `.metal`
files in a plain executable target, and a precompiled `.metallib` would need a
resource bundle that the `swift build` and `.app` paths resolve differently.

The overlay excludes itself from the capture filter by `CGWindowID`. Without
that, it captures its own output and the image recurses.

Capture is armed by downward movement, not by angle alone — people work at
angles well below where it arms, and arming on angle would leave a 60fps capture
running all day. Once engaged it is held until the lid is clearly open again, so
closing slowly or pausing halfway doesn't drop it.

## Status

Working and verified:

- Sensor discovery and angle decoding, confirmed against live hardware
- Builds clean; launches and runs as a menu bar app
- Capture lifecycle, settings persistence, permission preflight
- Overlay lifecycle — reveal, idempotent re-show, and full teardown even when
  interrupted mid-fade — driven from a harness against the real sources
- Engagement rules, run against scripted lid profiles: working at a normal
  angle, closing then holding, a slow close with pauses, and reopening
- The fold itself, rendered offscreen across the whole 0→1 range and inspected
  frame by frame against a synthetic desktop

Not yet verified on hardware:

- **How closely the illusion holds.** The geometry assumes where your eye is —
  mid-screen height, 5.5 panel heights back — and that the panel stands vertical
  at a lid angle of 90°. `counterRotation` and `eyeDistance` in
  `MetalFoldView.swift` are the constants to adjust if it drifts.
- **Angle tracking across large travel.** Readings were confirmed live at
  113–119°, including real sensor noise, but not swept through the full range.
- **60fps sustained performance.** Frames now reach the GPU without a per-frame
  `CGImage` conversion, but the mip chain is regenerated per frame and that
  hasn't been profiled under a real close.

## License

MIT — see [LICENSE](LICENSE).
