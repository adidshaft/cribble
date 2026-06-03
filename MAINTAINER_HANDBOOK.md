# Cribble Maintainer Handbook

This handbook is for running Cribble as an owner-led open-source product. The
goal is to welcome useful contributions without letting the roadmap drift away
from the product you want to build.

## Product posture

Cribble is a calm, local-first Markdown reader for macOS that turns plain `.md`
folders into a rich, connected reading workspace.

Public website: https://cribble.kyokasuigetsu.xyz

Keep these boundaries firm:

- You own product direction, roadmap, releases, monetization, and official
  branding.
- Contributors are welcome in focused lanes: bugs, docs, tests, accessibility,
  rendering fixes, diagnostics, and discussed provider/integration work.
- Feature, UX, AI behavior, write-policy, roadmap, and monetization changes
  should start in GitHub Discussions or an issue before anyone codes.
- Official releases are only the builds you publish through GitHub Releases,
  the website, Sparkle, or the App Store.

## Contribution workflow

Triage incoming work in this order:

1. **Security reports:** keep private, reproduce quickly, patch quietly, then
   disclose when safe.
2. **Crashes and data-safety issues:** prioritize over polish and feature work.
3. **Regressions in current stable:** prioritize if the bug affects the public
   release.
4. **Docs/tests/accessibility/rendering fixes:** usually good PR lanes.
5. **Feature proposals:** move to Discussions unless they are already accepted.

Use labels consistently:

- `needs-triage` for anything not yet classified.
- `bug`, `docs`, `markdown`, `reader`, `ai`, `provider`, or `security` for area.
- `product-discussion` for direction-setting work.
- `good first issue` only when the scope is clear and small.
- `help wanted` only when you are comfortable with an outside implementation.

When reviewing PRs:

- Check whether the PR has DCO signoff.
- Ask for an issue or Discussion link for product-shaping work.
- Prefer small, mergeable improvements over broad rewrites.
- Keep "reader first", "local first", and "preview before mutation" as review
  criteria, not just slogans.
- Say no quickly when work does not fit. It is kinder than slow ambiguity.

## Tests and checks

Swift tests are not needed for docs-only changes like community files, README
copy, issue templates, labels, or website text.

Use this lightweight check set for docs/community changes:

```sh
git diff --check
```

For app-code changes, run:

```sh
swift test
./script/build_and_run.sh
```

For release candidates, also run:

```sh
./script/validate_release.sh <version>
```

Add targeted manual checks for anything involving:

- folder permissions and security-scoped bookmarks;
- AI providers or generated diff application;
- Markdown/Mermaid/math rendering;
- Sparkle updates;
- packaging, signing, notarization, or App Store distribution.

## Release model

Use a simple owner-led release train:

1. Decide the release scope and version.
2. Update `VERSION`, `CHANGELOG.md`, `README.md`, website copy, and any App Store
   metadata that changed.
3. Run tests and release validation.
4. Package and notarize the DMG.
5. Publish a GitHub release with the DMG, checksum, and Sparkle `appcast.xml`.
6. Promote the release to the `stable` tag/release.
7. Update the website at https://cribble.kyokasuigetsu.xyz if download links,
   version, feature positioning, privacy copy, or support copy changed.
8. Announce with a short release note focused on user-visible value.

Suggested versioning:

- Patch releases fix crashes, regressions, packaging, docs, or small reliability
  issues.
- Minor releases add user-visible workflows or meaningful app capabilities.
- Major releases are for compatibility or product-contract breaks.

Keep release notes user-centered:

- what changed;
- why users should care;
- upgrade notes;
- known limitations, if any.

## Website operations

The website is the public trust surface for Cribble:

https://cribble.kyokasuigetsu.xyz

Keep it aligned with the latest stable release:

- primary download link points to the current stable DMG;
- release notes link points to the current release;
- privacy/support copy matches the app's actual behavior;
- one-line description stays consistent:
  "Cribble is a calm, local-first Markdown reader for macOS that turns plain
  `.md` folders into a rich, connected reading workspace."

The Vercel root config maps the domain root to `website/index.html` and assets
to `website/assets`. After deployment, verify:

```sh
curl -I https://cribble.kyokasuigetsu.xyz/
curl -I https://cribble.kyokasuigetsu.xyz/assets/icon.png
```

Expected result: HTTP `200`.

## Project management

Keep three lanes separate:

- **Issues:** reproducible bugs, accepted tasks, docs fixes, and implementation
  work.
- **Discussions:** ideas, roadmap proposals, product questions, and early design
  exploration.
- **Docs:** durable decisions, release notes, architecture notes, and maintainer
  runbooks.

Recommended weekly habit:

- Triage new issues and Discussions.
- Convert accepted ideas into small issues.
- Close or redirect proposals that do not fit.
- Mark one or two genuinely small issues as `good first issue`.
- Keep `ROADMAP.md` honest rather than exhaustive.

Recommended milestone habit:

- Make one milestone per release candidate.
- Include only work you are willing to ship.
- Move unfinished work out before tagging the release.
- Do not let external requests silently become commitments.

## Open-source sustainability

Be explicit about the exchange:

- Users get source availability, transparency, forkability, and a real path to
  contribute.
- You retain direction over the official product, app identity, release
  channels, and business model.

Healthy defaults:

- prefer Discussions before feature PRs;
- avoid accepting broad rewrites from new contributors;
- document decisions once, then link back to them;
- keep official branding protected;
- keep paid distribution and source licensing explained plainly;
- never promise support or review timelines you cannot sustain.

## Security and trust

Cribble handles private note libraries, local AI prompts, generated diffs, and
file access. Treat trust as a product feature.

Maintain these rules:

- no secret material in the repo;
- no analytics without explicit docs and user consent;
- no AI mutation without preview;
- no release without signing/notarization checks;
- no public handling of private security reports.

If a vulnerability affects released builds, prepare:

- a private fix branch;
- a patched release;
- concise user-facing notes;
- a GitHub advisory if appropriate.
