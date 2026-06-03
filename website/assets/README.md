# website/assets

Static images served by [the website](../index.html).

| File(s) | Use |
| --- | --- |
| `icon.png` | Site favicon / logo. |
| `shot-01.png` … `shot-04.png` | Product screenshots in the page. |
| `cribble-link-preview.jpg` / `.png` | Open Graph / Twitter link preview (1200×630). |
| `cribble-mac-store-artwork.png` | Mac App Store artwork. |

When updating the link preview, bump the `?v=` query in `index.html`'s OG tags so
social platforms re-fetch it. Keep images optimized — this is a no-build static site.
