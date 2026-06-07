---
aliases: [ai, cribble ai, chat, assistant, local llm]
keywords: [ai, chat, llm, on-device, gemma, qwen, claude, codex, wiki link, synthesis, q&a, pathfinder, private]
tags: [demo, feature, ai]
---
# Cribble AI

A local-first assistant that reads your notes and prefers **on-your-Mac** models. You can also choose Claude or Codex through command-line sessions you are already signed into; Cribble labels that data boundary before you send note context. Open it three ways:

- Press **Command J**
- Click the **✦ icon in the menu bar** (top-right of your screen)
- Toolbar → **Cribble AI**

> **Note:**
> First time? Pick a model from the chip at the bottom of the chat. **On-device** models (Gemma, Qwen) download once and keep notes on this Mac. **Cloud** models (Claude, Codex) send note context through the sessions you're already logged into in Terminal. The chooser and model picker show this data boundary on every option.

## The four things it does

### 1. Answer questions about what you're reading
Open any note, then press **Command J** and ask. The model automatically sees the note you have open.
For the most common case, choose **AI → Summarize Current Note** and Cribble
opens the chat with the reviewed summary prompt ready to run.
Choose **AI → Explain Current Note Simply** when you want a beginner-friendly
version without thinking about prompt wording.

> **Try it**
> Stay on this note, open the chat, and ask: *"summarize this note in three bullets"* or *"what are the four things Cribble AI does?"*

### 2. Auto-link your notes
Tag notes with **@** in the chat, then ask to connect them. Cribble shows the suggested `[[Wiki Links]]` as a **safe diff preview** — nothing is written until you approve.

> **Try it**
> Type: *"link @Getting Started and @Feature Tour where they relate"* and review the diff.

### 3. Create a new note from many
Ask it to synthesize, index, or summarize notes into a fresh file. It proposes the new note as a preview before saving.
For a quick folder map, choose **AI → Create Index Note**. Cribble opens the
chat with a reviewed `index.md` proposal prompt.

> **Try it**
> Type: *"create an index note for @README @Getting Started @Feature Tour"* — Cribble offers to create the file.

### 4. Explain how two notes connect
This is **Pathfinder** — drag one note onto another in the sidebar, then choose **Explain the connection** → an on-device model. More in [[Feature Tour]].

## Tag notes with @

Inside the chat, type **@** and start a note's name. Pick from the list to attach it as context — its contents are sent to the model so answers are grounded in *your* notes, never invented.

## Find the next thing to read

Choose **AI → Find Related Notes** to open Cribble AI with a prompt that looks
for useful connections from the note in front of you. It is handy when you are
new to a folder and do not know the local vocabulary yet.

## Move it out of the way

| Control | What it does |
| :--- | :--- |
| **^** (in the chat header) | Tuck the chat into the menu bar |
| Menu-bar icon | Pop it back open to type |
| **v** (in the menu-bar popover) | Expand back to the floating window |
| New chat / ✕ | Start over · close |

## Private by design

On-device models do all their thinking on your Apple Silicon GPU. Cloud CLI models are opt-in and clearly labeled because note context leaves the Mac through your signed-in command-line tool. Every change the AI proposes — a link, an edit, a new file — is shown as a preview first, so you're always in control.

← Back to [[README|Home]] · Next: [[Feature Tour]]
