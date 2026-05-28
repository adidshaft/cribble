---
aliases: [diagram zoom, math zoom, zoom overlay]
keywords: [mermaid, math, zoom, overlay, diagram, equation]
tags: [demo, feature, visual]
---
# Mermaid/Math Zoom Overlays

Cribble can open Mermaid diagrams and block equations in a focused zoom overlay. Hover a rendered diagram or equation, then use the scale control to inspect dense content.

```mermaid
flowchart LR
    A[Markdown note] --> B{Rendered block}
    B -->|Mermaid| C[Interactive diagram]
    B -->|Math| D[Equation preview]
    C --> E[Zoom overlay]
    D --> E
    E --> F[Pan, zoom, reset]
```

The same overlay works for equations:

$$
\operatorname{score}(q, d) =
\frac{q \cdot d}{\lVert q \rVert \lVert d \rVert}
$$

This cosine similarity formula also gives semantic search something meaningful to index.

Next: [[Reading Trails]]
