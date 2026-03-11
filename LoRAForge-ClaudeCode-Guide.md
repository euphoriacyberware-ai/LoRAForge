# LoRAForge — Claude Code Onboarding Guide

This document is intended to be read by Claude Code at the start of a session.
Refer to `LoRAForge-Specification.md` for the full data model, UI structure, and implementation details.

---

## Project Overview

**LoRAForge** is a native macOS SwiftUI application that connects to a Draw Things gRPC server to generate images for LoRA training datasets. Users supply reference images and a list of prompts; the app iterates through prompts generating images, allows curation via a rank system, supports AI-assisted captioning via Ollama, and exports final image+caption pairs in standard LoRA training format.

---

## Key Technical Facts

| Item | Value |
|------|-------|
| Platform | macOS (native) |
| UI Framework | SwiftUI |
| Document Architecture | NSDocument subclass |
| Document format | Folder package (`.lforge` directory) |
| Bundle ID | `euphoria-ai.LoRAForge` |
| Document UTI | `com.euphoria-ai.lforge` |
| Main Swift Package dependency | `https://github.com/euphoriacyberware-ai/DT-gRPC-Swift-Client` |
| App Support storage | `~/Library/Application Support/LoRAForge/` |
| Image resize library | Core Image (`CILanczosScaleTransform`) |
| Caption API | Ollama HTTP REST (`/api/generate`) |

---

## How to Start a Session with Claude Code

Paste the following prompt to begin a new phase, replacing `[N]` and `[description]`:

> I am building a macOS app called LoRAForge. The full specification is in `LoRAForge-Specification.md` in this project.
> Please implement **Phase [N]: [description]** as described in the spec.
> Build on the existing code already in the project without breaking previous phases.

---

## Phase Checklist

Use this to track progress. Hand to Claude Code at the start of each session.

- [ ] **Phase 1** — Xcode project scaffold, NSDocument subclass, `.lforge` UTI registration, document package folder creation, app icon placeholder
- [ ] **Phase 2** — All Codable data model structs, `project.json` read/write, package subfolder management (`sources/`, `generated/`, `trash/`)
- [ ] **Phase 3** — App-level persistence: `connections.json` and `templates.json` in Application Support; manager classes
- [ ] **Phase 4** — Address Book UI: list, add/edit/delete connections, Test Connection button, Ollama caption prompt field
- [ ] **Phase 5** — Main window shell: `NavigationSplitView`, sidebar scaffold, toolbar with placeholder buttons
- [ ] **Phase 6** — Source image import: `NSOpenPanel` multi-select, copy to `sources/`, thumbnail display, inline label editing, remove
- [ ] **Phase 7** — Prompt list and detail: add/remove/reorder, detail view, source slot picker, generate count stepper
- [ ] **Phase 8** — Template save/load sheet: save current prompts as template, load (with append/replace choice), delete
- [ ] **Phase 9** — Config JSON editor: base config raw text editor, per-prompt override toggle + raw JSON editor, JSON validation feedback
- [ ] **Phase 10** — gRPC generation task: wire `DrawThingsClient`, sequential task runner, progress UI, PNG file writing, `project.json` persistence after each prompt
- [ ] **Phase 11** — Image grid + rank system: thumbnail grid, color-coded rank badge overlays, right-click context menus (promote/demote/discard/reveal)
- [ ] **Phase 12** — Lightbox: full-size image overlay, rank controls, caption editor, ← → navigation between images
- [ ] **Phase 13** — Inline captions: caption text field per image cell, single-image Ollama auto-caption (✨) button with spinner
- [ ] **Phase 14** — Bulk auto-caption: sequential Ollama captioning for all uncaptioned non-discarded images, toolbar progress indicator
- [ ] **Phase 15** — Trash bin: toggle view, restore to candidate, Empty Trash (permanent deletion of files and records)
- [ ] **Phase 16** — Export: export sheet UI, rank filter, Core Image resizing, filename pattern, paired `.txt` sidecar files, caption fallback options

---

## Architectural Decisions (Do Not Deviate)

1. **NSDocument subclass** — The document must be folder-based. Implement `read(from:ofType:)` and `write(to:ofType:)` operating on a directory URL. Set `LSTypeIsPackage = YES` in `Info.plist`.

2. **Configuration struct** — Do **not** redefine `Configuration`. It is provided by the `DrawThingsClient` Swift package. Import and use it directly.

3. **File moves, not copies** — When discarding (to trash) or restoring (from trash), use `FileManager.moveItem(at:to:)`, not copy+delete.

4. **Sequential generation** — Prompts are processed one at a time. Only one gRPC connection is active at a time. Do not parallelize generation requests.

5. **JSON editors are raw text** — The Draw Things configuration editor is a plain monospaced `TextEditor` where users paste JSON directly. Do not build a form-based UI for configuration fields.

6. **Ollama via URLSession** — The Ollama captioning API is a plain HTTP POST to `/api/generate`. Use `URLSession` directly; no third-party HTTP library.

7. **Export image format** — PNG output only. Resize using `CILanczosScaleTransform` for quality downscaling.

---

## Rank System Quick Reference

```
candidate   →  (promote)  →  shortlisted  →  (promote)  →  final_
final_      →  (demote)   →  shortlisted  →  (demote)   →  candidate
any rank    →  (discard)  →  discarded    (file moved to trash/)
discarded   →  (restore)  →  candidate   (file moved back to generated/)
```

Generation runs **skip** prompts that have at least one `final_` image (unless "Run All" is used).

---

## Ollama API Reference

```
POST http://{host}:{port}/api/generate
Content-Type: application/json

{
  "model": "llava",
  "prompt": "Describe this image in detail for LoRA training captioning:",
  "images": ["<base64-encoded-PNG>"],
  "stream": false
}

Response:
{
  "response": "A photograph of ...",
  ...
}
```

Use `response["response"]` as the caption string.

---

## Export Output Format

```
ExportFolder/
  {prefix}_001.png    ←  image file (resized if requested)
  {prefix}_001.txt    ←  caption text (one file per image)
  {prefix}_002.png
  {prefix}_002.txt
  ...
```

This is the standard format expected by LoRA training tools (kohya_ss, etc.).
