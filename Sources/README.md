# Sources

Swift source for Cribble, organized as a Swift Package (see [`Package.swift`](../Package.swift)).

| Target | Kind | What it is |
| --- | --- | --- |
| [`Cribble`](Cribble) | Executable | The macOS app — UI, reading engine, AI/intelligence services, and stores. |
| [`CribbleBundleRedirect`](CribbleBundleRedirect) | C library | A small shim that fixes SPM `Bundle.module` resolution inside the packaged `.app`. |

Start in [`Cribble/`](Cribble) for the application architecture.
