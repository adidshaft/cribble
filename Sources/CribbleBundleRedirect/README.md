# CribbleBundleRedirect

A tiny Objective-C shim that fixes Swift Package Manager's `Bundle.module`
resolution when Cribble runs as a packaged `.app` rather than from `swift run`.

SPM generates a `Bundle.module` accessor that looks for the resource bundle in
locations that don't match the layout inside a signed `.app`. This target
redirects that lookup so bundled resources (app icon, DemoNotes, Mermaid) load
correctly in the shipped build. It pairs with
[`SPMBundleAccessorFix.swift`](../Cribble/Support/SPMBundleAccessorFix.swift).

| File | Responsibility |
| --- | --- |
| `CribbleBundleRedirect.m` | The redirect implementation. |
| [`include/`](include) | Public header exposed to the Swift target. |

> If bundled resources go missing in a release build, start here.
