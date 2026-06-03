# Mermaid

The bundled [Mermaid](https://mermaid.js.org/) runtime (`mermaid.min.js`) used to
render ` ```mermaid ` diagram fences **offline**, inside the app's web view.

Bundling it locally keeps rendering fast and fully local-first — no CDN, no
network request. Generated diagrams are sanity-checked by
`MermaidRenderValidator` in [`Services/Intelligence`](../../Services/Intelligence).

To update: replace `mermaid.min.js` with a pinned release build and re-test the
Markdown showcase in the DemoNotes library.
