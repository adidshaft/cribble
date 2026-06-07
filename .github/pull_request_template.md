## Summary


## Related issue or discussion
Link the issue or Discussion. Feature, UX, AI behavior, storage/write policy,
monetization, roadmap, and large refactor PRs should have maintainer agreement
before implementation.


## Testing
- [ ] Built Cribble locally, or this is a docs-only change
- [ ] Ran `swift test`, or explained why it was not needed
- [ ] Tested the affected flow, or this is a docs-only change

## Product direction
- [ ] This is a focused bug/docs/test/polish change, or it was discussed first.
- [ ] This preserves Cribble's local-first and preview-before-mutation model.

## Extension or plugin work
Complete this section for any extension manifest, plugin surface, importer,
renderer, runner, command, or Settings contribution.

- [ ] This starts read-only/declarative, or the maintainer approved a broader runtime change.
- [ ] Reads: describe exactly which note scope is accessed (`none`, `current note`, `selected files`, `project notes`, or other).
- [ ] Writes: describe every file or store this can change, and the preview/cancel path for user notes.
- [ ] Network: list endpoints or say `none`.
- [ ] Secrets: confirm no keys, tokens, passwords, certificates, or private endpoints are committed; app secrets use Keychain-backed flows.
- [ ] Disable behavior: explain what disappears when the extension is disabled.
- [ ] UI: confirm any UI is native SwiftUI using system controls, menus, settings, sheets, commands, focused values, and SF Symbols. No web views, custom chrome, Electron-style panels, or non-native UI unless a maintainer explicitly approved the exception before this PR.
- [ ] Tests/docs: link the focused tests or docs update proving validation, discovery, disabled-state filtering, or contribution routing.

See `docs/extensions.md` before opening extension PRs. Contributors are welcome
to propose ambitious ideas, but first merged steps should stay narrow,
inspectable, least-reading, least-writing, and Mac-native.

## DCO
- [ ] My commits include a DCO signoff (`git commit -s`).

## Notes
