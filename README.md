# hammerspoon-quick-capture

A global hotkey + modal for capturing thoughts into a folder. Built for [Obsidian](https://obsidian.md) inboxes but works for any directory of Markdown files.

Press **Option+Space** anywhere on macOS → modal with Title and Body fields → hit Save (or `Cmd+Enter`) → a timestamped Markdown file with YAML frontmatter lands in your inbox folder.

## Why

Replaces Todoist quick-add (or any other capture app) when your "second brain" is just a folder of Markdown files. No app to keep open, no service to subscribe to, no database — just write files and let your editor's sync (Obsidian Sync, iCloud, Dropbox, Syncthing) carry them across machines.

## Requires

- macOS
- [Hammerspoon](https://www.hammerspoon.org) — `brew install --cask hammerspoon`
- Accessibility permission granted to Hammerspoon (System Settings → Privacy & Security → Accessibility)
- A target folder for captures (default: `~/second-brain-mk1/_inbox/` — edit the `INBOX` constant near the top of `init.lua` to change)

## Install

```sh
# 1. Install Hammerspoon if you haven't
brew install --cask hammerspoon

# 2. Clone this repo
git clone https://github.com/shake-k/hammerspoon-quick-capture.git ~/pers-projects/hammerspoon-quick-capture

# 3. Symlink the config into ~/.hammerspoon/
# (Back up your existing ~/.hammerspoon/init.lua first if you have one)
ln -s ~/pers-projects/hammerspoon-quick-capture/init.lua ~/.hammerspoon/init.lua

# 4. Launch Hammerspoon, grant Accessibility permission when prompted
# 5. Click Hammerspoon menu bar icon → Reload Config

# Test: press Option+Space
```

## What you get

Each capture writes a file like `2026-05-12-144057-my-note-title.md` containing:

```yaml
---
type: knowledge
summary: "My Note Title"
tags: [inbox]
status: draft
updated: 2026-05-12
---

The body content goes here. Multi-line is preserved.
```

Behavior:
- **Title + Body** — both optional. If both are empty, Save is a no-op.
- **Title only** — file written, frontmatter only.
- **Body only** — filename ends `-untitled.md`, summary becomes `"Quick capture HH:MM"`.
- **Special characters** — title slug strips non-alphanumeric (`hello-world`, no symbols). YAML `summary` field escapes `"` and `\`.
- **Filename collisions** — second capture in the same second gets `-2`, `-3`, etc.
- **Save failure** — modal stays open with your content; alert shows the error.
- **Escape** — cancel, no file, no alert.

## Configuration

Edit `init.lua`:

- **Hotkey:** Change `hs.hotkey.bind({"alt"}, "space", showCapture)` to your preferred chord.
- **Inbox path:** Change `local INBOX = os.getenv("HOME") .. "/second-brain-mk1/_inbox/"` to your folder.
- **Frontmatter:** Edit `buildFrontmatter()` to change `type`, default `tags`, etc.
- **Modal size / theme:** Edit the `rect` dimensions and the `<style>` block in the HTML constant.

## Why Hammerspoon

This started as a build session evaluating Apple Shortcuts, Stik, Collector, QuickAdd + Global Hotkeys, Raycast extensions, and Drafts. Hammerspoon won because:
- The spec (global hotkey + 2-field modal + custom YAML file write) fits its API exactly.
- Reliability bar is high: Lua process is single-purpose, low memory, atomic file writes. Failure mode is "hotkey doesn't fire" (visible) not "capture vanishes" (silent — the SuperWhisper failure mode).
- Maintenance is one file. No build pipeline, no app bundle, no notarization, no auto-update.
- ~80 lines covers the daily-driver feature.

## Built with

Shipped via the [`/ship-feature`](https://github.com/shake-k/) methodology — Frame → Research → Spike → Build → Verify → Deploy → Close. The 11-step Phase 3 spike caught one real bug (HTML `<input autofocus>` doesn't fire when the webview isn't the key window) before any production code was written. Fix: deferred `hs.window:focus()` after `:show()`.

## License

MIT
