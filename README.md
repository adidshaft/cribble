# Cribble

Cribble is a native macOS Markdown reader for folder-based note libraries.

## Run

```sh
./script/build_and_run.sh
```

The same command is wired into the Codex app Run action. You can also open
`Cribble.xcworkspace` in Xcode; the workspace contains the Swift package.

## Features

- Opens a local folder in place and shows only folders plus `.md` files.
- Keeps opened folders in a persistent library.
- Creates a `README.md` for every imported folder that does not already have one.
- Renders rich Markdown with Textual, Roobert body text, and Monaco code.
- Supports wiki links such as `[[Home]]`, `[[Note#Heading]]`, and `[[Note|Label]]`.
- Supports relative images, tables, richer task markers, and LaTeX math via Textual.
- Includes toolbar controls for file sorting and reader text size.
- Opens the selected file in a configured external editor.
- Offers a preview-first AI linking workflow using local Codex or Claude CLIs.
