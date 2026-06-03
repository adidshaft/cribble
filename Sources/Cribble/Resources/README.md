# Resources

Bundled assets shipped inside the app (`Bundle.module`).

| Path | What it is |
| --- | --- |
| [`DemoNotes/`](DemoNotes) | The removable sample library shown on a fresh install — a living tutorial of every feature. |
| [`Mermaid/`](Mermaid) | The bundled Mermaid runtime used to render diagram fences offline. |

> Resource bundling is verified at release time — the packaging script fails
> loudly if `Bundle.module` is missing (see the root README's Release section).
