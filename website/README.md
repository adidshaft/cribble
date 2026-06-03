# website

The public marketing + download site for Cribble:
**[cribble.kyokasuigetsu.xyz](https://cribble.kyokasuigetsu.xyz)**.

A single, dependency-free static page — no build step.

| Path | What it is |
| --- | --- |
| `index.html` | The whole site: markup + inline CSS (design tokens at the top). |
| `assets/` | Icon, screenshots, and social/link-preview images. |
| `vercel.json` | Deploy + headers config for Vercel hosting. |

## Edit & preview

```sh
open website/index.html          # quick local preview
```

Edit `index.html` directly. Design tokens (colors, shadows, fonts) live in the
`:root` block — change those rather than hard-coding values inline.

## Deploy

Hosting is on Vercel (see [`vercel.json`](vercel.json) and the repo-root
[`vercel.json`](../vercel.json)). Keep download links pointed at the
`stable` release tag so the site always offers the current build.
