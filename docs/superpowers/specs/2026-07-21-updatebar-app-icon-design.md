# UpdateBar App Icon Design

## Goal

Give the packaged macOS menu bar app a distinctive UpdateBar icon that follows
Apple's current app-icon guidance while remaining compatible with the app's
macOS 13 deployment target and hand-built SwiftPM app bundle.

## Approved Visual Direction

The icon uses one bold upward arrow above a separate horizontal bar. The arrow
keeps the approved broad head, thick stem, and shallow centered V-shaped cut in
its tail. The bar remains a quiet secondary element. No other symbol, letter,
word, or decorative object is added.

The background moves from near-black graphite into dark forest green. The arrow
uses a fresh mint-to-chartreuse transition, and the bar uses a quieter frosted
mint. The treatment suggests safe progress and a newly current state without
using the generic blue palette from the earlier concepts.

## Apple Platform Rules

The master composition uses a 1024-by-1024 square canvas. Primary artwork stays
centered with generous breathing room. Source layers do not include a rounded
rectangle mask because macOS applies the final enclosure mask. Thin strokes,
small details, text, and sharp micro-features are excluded so the mark remains
clear at 16 pixels.

The artwork is divided into three logical layers: background, arrow, and bar.
The master geometry stays flat and controllable. Material is restrained: a
thin highlight on upper-facing edges, shallow refraction, low translucency,
light frost, and minimal chromatic shadow. Neon halos, inflated bevels, heavy
static shadows, and pillow-like glass are explicitly out of scope.

## Source And Shipping Assets

The repository stores a deterministic 1024-by-1024 vector master under
`Assets/AppIcon/` and a generated `UpdateBar.icns` beside it. The approved
Imagegen concept is a visual reference, not the shipping raster source.

The vector master preserves full-square, unmasked artwork and the three logical
layers so it can be imported into Icon Composer later without redrawing. The
checked-in `.icns` contains the standard macOS 1x and 2x representations for
16, 32, 128, 256, and 512 point sizes, including the 1024-pixel representation.
It is the compatibility-safe shipping artifact for the existing macOS 13+
manual bundle.

Adding an Xcode project or making Icon Composer/Xcode 26 a release-build
dependency is outside this change. Dynamic `.icon` delivery can be evaluated
separately after the app adopts an asset-catalog build path. On macOS 26, the
system can still apply its current enclosure and edge treatment to the supplied
flattened icon.

## Packaging

`Scripts/package-app.sh` copies `UpdateBar.icns` into
`UpdateBar.app/Contents/Resources` and declares it with `CFBundleIconFile` in
the generated `Info.plist`. The icon is copied before code signing so the
signature covers the final bundle contents.

Packaging fails clearly if the checked-in icon is missing. Existing signing,
notarization, launch-smoke, and archive behavior otherwise remains unchanged.

## Verification

- A focused packaging test proves that the icon is copied and the plist points
  to it.
- The packaged app's plist passes `plutil -lint` and the `.icns` passes
  `iconutil` inspection on macOS.
- The standard package, archive, signing, and quality-gate tests remain green.
- Manual review checks the icon in Finder, the Dock, Spotlight, and Get Info at
  both normal and small sizes on light and dark desktops.
- Manual review confirms the arrow, V-tail, and bar remain recognizable at 16,
  32, 128, and 1024 pixels without clipped content or a visible premade corner
  mask.
