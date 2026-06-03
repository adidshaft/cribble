# Cribble_App_Icons

Source artwork and built icon assets for the Cribble app icon, in both
reference-light and dark-mode variants.

| Path | What it is |
| --- | --- |
| `*.icon/` | Xcode 16 `.icon` (Icon Composer) source documents. |
| `*.iconset/` | macOS iconset folders (all sizes) for `iconutil`. |
| `*.icns` | Compiled icon files used by the app. |
| `*.png` | Flat previews / source renders. |

## Rebuild an `.icns`

```sh
iconutil -c icns Cribble_App_Icons/cribble-icon-reference-light.iconset
```

> Do not add stray files inside `.iconset/` or `.icon/` folders — `iconutil`
> and Icon Composer treat their contents as a strict, named set.

These are brand assets and are **not** covered by the source license. See
[TRADEMARK.md](../TRADEMARK.md).
