# UpdateBar App Icon Refresh

## Goal

Refresh the UpdateBar macOS app icon so it shares SwitchTab's premium layered-glass and luminous gradient language while keeping UpdateBar's recognizable upward-arrow and progress-bar symbol.

## Chosen direction

- Keep the existing three semantic layers: `background`, `arrow`, and `bar`.
- Use a deep navy/emerald rounded-square base with a subtle translucent glass highlight.
- Keep any perimeter highlight extremely subtle so the standard macOS mask and shadow define the silhouette.
- Use a lime-to-mint arrow and translucent mint progress bar with restrained inner highlights.
- Keep the symbol centered, text-free, and legible at the smallest macOS representation.

## Implementation

The source of truth will be the approved generated PNG, checked into `Assets/AppIcon/UpdateBar.png`. A deterministic packaging script will derive the required macOS iconset representations and `.icns` from that raster source. SVG will not be used for the final artwork.

## Verification

- `Scripts/build-app-icon.sh` (PNG source → all iconset sizes → `.icns`)
- `Scripts/app-icon-test.sh`
- `Scripts/package-app.sh` smoke path
- `swift test`
