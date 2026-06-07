# Contributing to Cribble

Thanks for wanting to help. Cribble is a local-first macOS Markdown reader, and
the contribution model is intentionally welcoming but owner-led: bug fixes,
docs, tests, accessibility improvements, rendering fixes, and agreed-upon
integration work are very welcome; product direction and roadmap decisions stay
with the maintainer.

## Good contribution lanes

Direct pull requests are a good fit for:

- reproducible bug fixes
- Markdown rendering, link-resolution, and accessibility improvements
- tests and focused test fixtures
- docs, release notes, and support copy
- diagnostics improvements
- provider/integration work that has already been discussed

Please open an issue or GitHub Discussion before working on:

- new product features or major UX changes
- AI behavior, storage/write policy, monetization, or distribution changes
- new extension surfaces beyond declarative manifest contributions
- roadmap changes
- large refactors or module extraction
- anything that changes Cribble's local-first or preview-before-mutation model

This avoids asking contributors to spend time on work that does not fit the
current product direction.

## Local setup

Cribble is a Swift Package based macOS app.

```sh
./script/build_and_run.sh
swift test
```

You can also open `Cribble.xcworkspace` in Xcode.

Release packaging and notarization require maintainer-owned signing
credentials. Do not include certificates, private keys, provisioning profiles,
API tokens, or notary credentials in pull requests.

## Pull request expectations

- Keep changes focused and explain the user-facing behavior.
- Link the related issue or Discussion when one exists.
- Include tests for behavioral changes when practical.
- Mention any manual testing you performed.
- Do not rewrite unrelated files or generated assets.
- Do not change product direction without prior maintainer agreement.

Cribble is maintained by a small team. Review may be slower than in a company
project, especially for broad or product-shaping changes.

## DCO signoff

Cribble uses the Developer Certificate of Origin (DCO) for contributor
provenance. Add a signoff line to every commit:

```sh
git commit -s
```

The signoff means you certify that you wrote the contribution or have the right
to submit it, and that it can be redistributed under this repository's license.

The commit message should include a line like:

```text
Signed-off-by: Your Name <you@example.com>
```

## Product principles

Changes should preserve these defaults unless there is explicit maintainer
agreement:

- **Local first:** Cribble does not upload or sync documents by itself.
- **Reader first:** editing belongs in the user's chosen editor.
- **Plain files stay plain:** generated structure should remain ordinary
  Markdown.
- **Preview before mutation:** AI or generated changes must be reviewable before
  touching source files.
- **Native Mac feel:** prefer system-native patterns over heavy custom chrome.

## Extension contributions

Extension work has an extra safety bar. Start with read-only, declarative
manifest behavior; request the least note access possible; avoid source-note
writes unless they go through an explicit preview; and keep extension UI native
SwiftUI with system controls, menus, settings, sheets, commands, and SF Symbols.

See `docs/extensions.md` for the full extension contribution checklist,
including read-only-first, least-reading, least-writing, no hidden execution,
Keychain-only secrets, and native SwiftUI expectations.

For new extension ideas, start with the **Extension proposal** issue template.
It asks for the first read-only version, data contract, native Mac surface, and
"later, not first PR" scope before anyone writes code.

## Security and conduct

Please report security issues privately using `SECURITY.md`. Conduct concerns
are covered by `CODE_OF_CONDUCT.md`.
