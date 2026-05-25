# Cribble

Cribble is a native macOS Markdown reader for folder-based note libraries. It is
for people who already write in plain `.md` files, but want a calmer, richer,
more connected reading surface than Finder, a code editor, or a full writing
app.

The product idea is simple: keep Markdown editing outside Cribble, and make
Cribble the best place to read, browse, connect, and understand a local folder
of notes.

## Product Idea

Cribble treats every folder as a small knowledge space. Folders become shelves,
`README.md` files become folder landing pages, and Markdown files become readable
documents with native navigation. The app should feel like a Mac-native library:
quiet, fast, legible, and deeply respectful of the files on disk.

The app has three core jobs:

- **Read beautifully:** render Markdown with strong typography, rich code
  blocks, tables, task states, images, links, and math without turning the app
  into an editor.
- **Navigate locally:** preserve folder structure, open folder `README.md`
  pages, resolve wiki links, and make cross-file reading feel natural.
- **Connect notes safely:** use a local installed AI tool to suggest links
  between files, then show a patch preview before anything is written.

## Product Principles

- **Local first:** Cribble reads folders in place and does not upload or sync
  documents by itself.
- **Reader only:** Markdown is edited in the user's chosen editor. Cribble
  should never become an accidental writing surface.
- **Plain files stay plain:** generated structure should be ordinary Markdown,
  especially folder-level `README.md` files.
- **Preview before mutation:** AI can suggest changes, but the user reviews and
  applies patches.
- **System native:** the interface should follow macOS defaults, system theme,
  sidebar behavior, toolbars, settings, and Liquid Glass-era materials.

## Target Workflows

- Open several Markdown folders and keep them available across launches.
- Click a folder to read its `README.md` as a landing page.
- Read rich notes with tables, checkboxes, code, images, math, and internal
  links.
- Sort files inside folders by name, created date, or last updated date.
- Adjust reader text size from very compact to presentation-friendly.
- Open the current file in a configured external editor.
- Ask Codex or Claude to analyze the local folder and suggest sparse wiki links
  between existing files.

## Future Ideas

- Back/forward navigation history for reading paths.
- Outline/table-of-contents navigation for the current document.
- Per-folder reading preferences and sort defaults.
- Better unresolved-link views with suggested target files.
- Optional graph view for local file relationships.
- Export a connected reading bundle without changing source files.
- Quick Look extension for Markdown previews.
- AppleScript or URL-scheme hooks so other tools can open a note at a heading.

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
- Keeps folder opening, refresh, and file sorting in the sidebar where the library lives.
- Includes XXS-to-XXL reader text sizing and light/dark app icons that follow system appearance.
- Opens the selected file in a configured external editor.
- Offers a preview-first AI linking workflow using local Codex or Claude CLIs.
