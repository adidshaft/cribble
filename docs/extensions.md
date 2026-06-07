# Cribble Extensions

Cribble extensions are currently declarative. They let users and teams describe
safe contributions in `cribble-extension.json` files, and Cribble validates those
manifests before showing their capabilities in the app.

API v1 does not execute extension code. Executable plugins will require a
separate trust model before they are supported.

## Where Extensions Live

User extensions live in:

```text
~/Library/Application Support/Cribble/Extensions/
```

Project extensions live inside an opened note folder:

```text
Your Notes/
  .cribble/
    extensions/
      your-extension/
        cribble-extension.json
```

Project extensions win over user extensions with the same id. This lets a folder
carry its own conventions without permanently changing the user's global setup.

## Manifest Shape

Every extension folder needs a `cribble-extension.json` file:

```json
{
  "apiVersion": 1,
  "id": "com.example.cribble.research-actions",
  "name": "Research Actions",
  "version": "0.1.0",
  "kind": "quick-action",
  "summary": "Adds research-oriented prompts.",
  "runtime": "declarative",
  "permissions": ["read-current-note"],
  "quickActions": [
    {
      "id": "extract-claims",
      "title": "Extract claims",
      "icon": "checklist",
      "prompt": "Extract the factual claims from the current note and list what evidence each claim needs."
    }
  ]
}
```

Required fields:

- `apiVersion`: currently `1`.
- `id`: reverse-DNS style id with at least three parts, such as `com.example.cribble.tool`.
- `name`: human-readable name shown in Settings.
- `version`: extension version string.
- `kind`: one of `quick-action`, `intelligence-provider`, `renderer`, or `importer`.
- `summary`: short user-facing explanation.
- `runtime`: use `declarative`.

Optional fields:

- `homepage`: `http` or `https` URL.
- `permissions`: typed permission strings.

`entrypoint` is intentionally unused for API v1. Manifests that request
`"runtime": "executable"` are rejected.

## Kinds

### Quick Action

Quick actions add prompts to the Chat HUD empty state and slash-command palette.

```json
{
  "apiVersion": 1,
  "id": "com.example.cribble.research-actions",
  "name": "Research Actions",
  "version": "0.1.0",
  "kind": "quick-action",
  "summary": "Adds research-oriented prompts.",
  "runtime": "declarative",
  "permissions": ["read-current-note"],
  "quickActions": [
    {
      "id": "extract-claims",
      "title": "Extract claims",
      "icon": "checklist",
      "prompt": "Extract the factual claims from the current note and list what evidence each claim needs."
    }
  ]
}
```

### Intelligence Provider

Provider profiles add OpenAI-compatible runner presets to the Intelligence HUD.
They can point to local runners or trusted remote machines.

Never put API keys in a manifest. Users enter keys in the Intelligence HUD and
can store them in Keychain.

```json
{
  "apiVersion": 1,
  "id": "com.example.cribble.team-runner",
  "name": "Team Runner",
  "version": "0.1.0",
  "kind": "intelligence-provider",
  "summary": "Adds a team-controlled OpenAI-compatible runner.",
  "runtime": "declarative",
  "permissions": ["network-openai-compatible"],
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

### Renderer

Renderer extensions map extra fenced-code languages onto existing built-in
renderers. For example, a team can make `workflow` fences render through the
bundled Mermaid renderer.

```json
{
  "apiVersion": 1,
  "id": "com.example.cribble.diagram-aliases",
  "name": "Diagram Aliases",
  "version": "0.1.0",
  "kind": "renderer",
  "summary": "Maps team diagram fences to built-in renderers.",
  "runtime": "declarative",
  "renderers": [
    {
      "id": "workflow-diagrams",
      "title": "Workflow Diagrams",
      "languages": ["workflow", "flowchart"],
      "builtInRenderer": "mermaid"
    }
  ]
}
```

Supported built-in renderer ids:

- `mermaid`
- `graphviz`
- `chart`
- `math`
- `markdown`

### Importer

Importer extensions declare file types a future converter intends to turn into
Markdown. Today they appear as import lanes in Settings so teams can agree on
formats before converter execution exists.

```json
{
  "apiVersion": 1,
  "id": "com.example.cribble.chat-importers",
  "name": "Chat Importers",
  "version": "0.1.0",
  "kind": "importer",
  "summary": "Declares chat export import lanes.",
  "runtime": "declarative",
  "importers": [
    {
      "id": "chat-export",
      "title": "Chat Export",
      "fileExtensions": ["json", "txt"],
      "outputFormat": "markdown"
    }
  ]
}
```

## Permissions

Known permission strings:

- `read-current-note`
- `read-project-notes`
- `propose-file-changes`
- `network-openai-compatible`

Permissions are shown to users in Settings. They are not a bypass: API v1 still
routes every contribution through Cribble's existing safe surfaces.

## Validation Rules

Cribble rejects manifests that:

- use an unsupported `apiVersion`;
- use an id that is not reverse-DNS shaped;
- request `"runtime": "executable"`;
- use a non-HTTP homepage;
- point `entrypoint` outside the extension folder;
- declare contributions under the wrong `kind`;
- duplicate contribution ids within a manifest;
- use unsafe language, importer, or contribution tokens.

## Designing A Good Extension

Good Cribble extensions should be:

- inspectable: a user can understand the manifest without reading code;
- reversible: disabling the extension removes its contributions;
- local-first: secrets stay out of manifests and source notes stay under user control;
- narrow: one extension kind per manifest;
- helpful immediately: provide a clear title, summary, and practical contribution.

For an interactive tour, open the bundled DemoNotes library and read
`Extensions and Remote Intelligence.md`.
