---
aliases: [ai, cribble ai, chat, assistant, local llm]
keywords: [ai, chat, llm, on-device, gemma, qwen, claude, codex, wiki link, synthesis, q&a, pathfinder, private]
tags: [demo, feature, ai]
---
# Cribble AI

A private assistant that reads your notes and runs **on your Mac** — no cloud, no account, nothing leaves your machine. Open it three ways:

- Press **C**
- Click the **✦ icon in the menu bar** (top-right of your screen)
- Toolbar → **Cribble AI**

> **Note:**
> First time? Pick a model from the chip at the bottom of the chat. **On-device** models (Gemma, Qwen) download once — tap the ↓ to grab one. **Cloud** models (Claude, Codex) use the sessions you're already logged into in your Terminal.

## The four things it does

### 1. Answer questions about what you're reading
Open any note, then press **C** and ask. The model automatically sees the note you have open.

> **Try it**
> Stay on this note, open the chat, and ask: *"summarize this note in three bullets"* or *"what are the four things Cribble AI does?"*

### 2. Auto-link your notes
Tag notes with **@** in the chat, then ask to connect them. Cribble shows the suggested `[[Wiki Links]]` as a **safe diff preview** — nothing is written until you approve.

> **Try it**
> Type: *"link @Getting Started and @Feature Tour where they relate"* and review the diff.

### 3. Create a new note from many
Ask it to synthesize, index, or summarize notes into a fresh file. It proposes the new note as a preview before saving.

> **Try it**
> Type: *"create an index note for @README @Getting Started @Feature Tour"* — Cribble offers to create the file.

### 4. Explain how two notes connect
This is **Pathfinder** — drag one note onto another in the sidebar, then choose **Explain the connection** → an on-device model. More in [[Feature Tour]].

## Tag notes with @

Inside the chat, type **@** and start a note's name. Pick from the list to attach it as context — its contents are sent to the model so answers are grounded in *your* notes, never invented.

## Move it out of the way

| Control | What it does |
| :--- | :--- |
| **^** (in the chat header) | Tuck the chat into the menu bar |
| Menu-bar icon | Pop it back open to type |
| **v** (in the menu-bar popover) | Expand back to the floating window |
| New chat / ✕ | Start over · close |

## Private by design

On-device models do all their thinking on your Apple Silicon GPU. Your notes are never uploaded. Every change the AI proposes — a link, an edit, a new file — is shown as a preview first, so you're always in control.

← Back to [[README|Home]] · Next: [[Feature Tour]]
