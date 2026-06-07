---
aliases: [team extension kit, plugin kit, extension workflow, team plugins]
keywords: [extensions, plugins, team workflow, manifest, review, remote runner, importer, renderer]
tags: [demo, extensions, team]
---
# Team Extension Kit

Use this note when a team wants Cribble to carry shared conventions with the
folder itself. Start with declarations, review them like documentation, and only
graduate to executable automation after trust and sandboxing are ready.

## The folder contract

Put project-specific extensions in the same repository or shared folder as the
notes they support:

```text
Team Notes/
  README.md
  Research/
  Meetings/
  .cribble/
    extensions/
      research-review/
        cribble-extension.json
      team-runner/
        cribble-extension.json
      diagram-aliases/
        cribble-extension.json
```

Cribble gives project-local extensions precedence over user-level extensions, so
teams can keep the current folder's rules close to the current folder's work.

In **Settings → Extensions**, use **Create Project Example** to write one of
these starter manifests into the active folder. After editing the JSON, click
**Check Again** to reload it and copy the extension details when someone needs
to review the manifest in a pull request or team chat.

## Start with four lanes

| Lane | Good first use | Permission posture |
| --- | --- | --- |
| Quick action | Repeatable review prompt in the Chat HUD | Exactly `read-current-note` |
| Intelligence provider | Shared OpenAI-compatible runner profile | Exactly `network-openai-compatible` |
| Renderer | Custom fence names like `workflow` or `decision-map` | No file access needed |
| Importer | Chat exports, research bundles, meeting transcripts | Declare formats first |

Everything in API v1 is declarative. If a manifest asks for executable runtime,
Cribble rejects it until a signed, sandboxed trust model exists. Cribble also
rejects project-wide read permissions and proposed file-change permissions in
API v1; those need explicit consent, preview, and revocation design first.

## Review checklist

Before enabling an extension for a shared folder, answer these questions in the
pull request or handoff note:

- Does the `id` use a stable reverse-DNS name?
- Does the summary explain what people will see in Cribble?
- Are permissions limited to the smallest useful set?
- If it uses a remote runner, who controls the endpoint?
- Does the manifest avoid secrets, tokens, and private keys?
- Would a quick action still be useful with only the current note and explicit
  attachments?
- Is the source URL or signing identity filled in when known?
- Did someone paste the copied extension details into the review thread?
- Did someone attach a copied diagnostic report when debugging install,
  validation, enabled-state, or remote-runner issues? It includes extension
  counts, warnings, permissions, and contribution titles without copying
  Keychain secrets.
- Can a non-technical reader understand why this exists?

Open `docs/extensions.md` before proposing a new extension surface. First PRs
should prove value with a declarative manifest, native SwiftUI affordance, or
validation improvement before any runtime work.

## Idea first, runtime later

When proposing a new plugin or extension, start with the idea rather than code:

- who would use it;
- which repeated folder workflow it improves;
- what the first read-only version would show in Cribble;
- what it needs to read, write, or send over the network;
- which native SwiftUI surface people review before anything changes.

Good ideas can be ambitious. The first version should still be small enough to
disable cleanly, inspect in Settings, and explain to a non-technical reader.

In **Settings → Extensions**, use **Copy Proposal** to copy this shape into a
GitHub issue, Discussion, or team thread before anyone writes implementation
code.

Use this proposal shape before writing code:

```markdown
## Extension idea
Audience:
Workflow:
Why Cribble:

## First read-only version
Manifest kind:
What appears in Cribble:
What user reviews before anything changes:

## Data contract
Reads:
Writes:
Network:
Secrets:
Disable behavior:

## Native Mac surface
SwiftUI surface:
System controls/SF Symbols:
Settings or command entry point:
Non-native UI needed? If yes, explain maintainer approval:

## Later, not first PR
What would need executable code:
What would need project-wide reads:
What would need source-note writes:
```

## Remote runner policy

Remote intelligence can be excellent when it is intentional. Use it for a large
model, a private VPS, a team GPU box, or a hosted runner your organization
controls. Avoid it for casual notes unless the person using Cribble understands
what context may leave the Mac.

Recommended manifest fields:

```json
{
  "apiVersion": 1,
  "id": "com.example.cribble.team-runner",
  "name": "Team Runner",
  "version": "0.1.0",
  "kind": "intelligence-provider",
  "summary": "Adds the team's approved OpenAI-compatible runner.",
  "permissions": ["network-openai-compatible"],
  "runtime": "declarative",
  "trust": {
    "developerName": "Example Research Team",
    "signingIdentifier": "com.example.cribble.team-runner",
    "teamIdentifier": "ABCDE12345",
    "sourceURL": "https://example.com/cribble/team-runner"
  },
  "intelligenceProviders": [
    {
      "id": "research-gpu",
      "title": "Research GPU",
      "baseURL": "https://ai.example.com/v1",
      "modelID": "qwen3-32b",
      "embeddingModelID": "text-embedding-3-small",
      "trustLabel": "Team-controlled VPS"
    }
  ]
}
```

Put API keys in Cribble's Intelligence HUD and store them in Keychain. Never put
secrets in `cribble-extension.json`. For non-loopback extension runner profiles,
Cribble asks each user to approve the runner before using it, and it keys that
approval to the extension source, endpoint, and model. Changing any of those
should trigger another review.

## A useful first quick action

This is a good starter for research, support, product, and legal review folders:

```json
{
  "apiVersion": 1,
  "id": "com.example.cribble.review-actions",
  "name": "Review Actions",
  "version": "0.1.0",
  "kind": "quick-action",
  "summary": "Adds shared review prompts for the current note.",
  "permissions": ["read-current-note"],
  "runtime": "declarative",
  "quickActions": [
    {
      "id": "risk-questions",
      "title": "Find review questions",
      "icon": "checklist",
      "prompt": "Read the current note and list the unanswered questions, risks, and assumptions a reviewer should check before acting on it."
    }
  ]
}
```

Once this is enabled, open **Command J**, type `/`, and choose the team action.

## When to stop

Stop at declarative manifests when the extension only needs to add prompts,
runner profiles, renderer aliases, or import lanes. Ask for a deeper design only
when the extension needs to execute code, transform files, call external
services automatically, or store durable state.

← Back to [[Workflow Playbook]] · [[Extensions and Remote Intelligence]] · [[Research Review]]
