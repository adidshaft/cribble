# Tests

The Cribble test suite. Run everything with:

```sh
swift test
```

| Target | What it covers |
| --- | --- |
| [`CribbleTests/`](CribbleTests) | Unit + logic tests for scanning, parsing, link resolution, rendering prep, reading state, AI/diff handling, and intelligence jobs. |

Tests favor pure logic over UI: most of `Services/`, `Stores/`, and `Support/`
is exercised directly. New behavior should land with a test in the matching file
(e.g. wiki-link changes → `WikiLinkParserTests`).
