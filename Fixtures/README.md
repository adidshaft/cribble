# Fixtures

Test and packaging fixtures.

| Path | What it is |
| --- | --- |
| `DemoNotes/` | Sample Markdown library used by tests (and mirrored as the in-app demo). |
| `Cribble.storekit` | StoreKit configuration for testing the Local AI in-app purchase locally. |

These are inputs for `swift test` and local StoreKit testing — not shipped app
resources. The shipped demo library lives in
[`Sources/Cribble/Resources/DemoNotes`](../Sources/Cribble/Resources/DemoNotes).
