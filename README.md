# LoRAForge

A native macOS application for building LoRA training datasets. LoRAForge connects to [Draw Things](https://drawthings.ai) for image generation and [Ollama](https://ollama.com) for AI-powered captioning, providing a streamlined workflow from prompt creation to export-ready datasets.

## Features

- **Image Generation** — Generate images via Draw Things gRPC server with full configuration control (73+ parameters including LoRAs, ControlNets, samplers, and more)
- **Per-Prompt Seed Override** — Pin a deterministic seed for any prompt; leave empty to use the configuration seed (or let the queue randomize)
- **Source Image Management** — Import reference images and attach them to prompts for img2img or ControlNet workflows; right-click any generated image to promote it back into the source-image pool
- **Prompt Duplication** — Clone an existing prompt's text, sources, batch size, configuration override, and seed override into a fresh sibling — from the Prompt Text toolbar or the sidebar context menu (⌘Z to undo)
- **Prompt Templates** — Save and load prompt sets as reusable templates across projects
- **Image Curation** — Rank generated images through a four-tier system: candidate, shortlisted, final, discarded
- **Image Inspector** — Selecting an image opens a side panel with its prompt text, seed, generation date, source-image thumbnails (with a "missing" placeholder + filename if a source has been removed), and an editable caption. All metadata fields are selectable for copy.
- **AI Captioning** — Single or bulk auto-captioning via Ollama with configurable model and prompt
- **Spell Checking** — Continuous spell checking in prompt and caption editors, plus the standard macOS **Edit › Spelling and Grammar** menu (Show Spelling and Grammar, Check Document Now, While Typing toggle)
- **Lightbox Viewer** — Full-size image preview with keyboard navigation, rank controls, and inline caption editing; remembers its size and position across openings
- **Trash & Undo** — Soft-delete with restore capability; prompt deletion and duplication support undo (⌘Z)
- **Flexible Export** — Export image + caption (.txt) pairs with optional resizing and filename prefixes

## Requirements

- macOS 15.0 or later
- [Draw Things](https://drawthings.ai) running with gRPC server enabled (for image generation)
- [Ollama](https://ollama.com) running locally (for auto-captioning)

## Installation

### Download (recommended)

1. Download the latest **`LoRAForge.dmg`** from the [Releases page](https://github.com/euphoriacyberware-ai/LoRAForge/releases).
2. Open the DMG and drag **LoRAForge** onto the **Applications** folder shortcut.
3. Launch LoRAForge from Applications. The build is signed and notarized, so Gatekeeper will allow it on first run.

### Build from source

Requires Xcode 16 or later.

1. Clone this repository and open `LoRAForge.xcodeproj`.
2. Let Swift Package Manager resolve dependencies.
3. Build and run.

## Getting Started

1. **Configure servers** — Open **Project › Address Book** to add your Draw Things and Ollama server connections
2. **Create a project** — A new `.lforge` document opens automatically; save it to begin importing images

## Workflow

1. **Import source images** — Add reference images from the sidebar for use in img2img or ControlNet prompts
2. **Create prompts** — Add prompts in the sidebar, attach source images, and set generation count. **Duplicate** an existing prompt from its toolbar or sidebar context menu to start from a known-good baseline.
3. **Configure generation** — Select a Draw Things server from the toolbar. Optionally set per-prompt configuration overrides via the JSON editor, or pin a deterministic seed in the prompt's **Seed Override** field.
4. **Generate** — Click **Run** to generate for prompts without a final image, or **Run All** to regenerate everything
5. **Curate** — Review generated images in the grid; click an image to open the inspector and review its prompt, seed, and source-image references; promote (candidate → shortlisted → final) or discard. Right-click any generated image to promote it back into the source-image pool for use in other prompts.
6. **Caption** — Edit captions in the inspector or lightbox (with spell checking), or use **Auto-caption** to bulk-caption all uncaptioned images via Ollama
7. **Export** — Click **Export** to write image + caption pairs to a folder, with options for filtering by rank, resizing, and caption fallback behavior

## Project Format

LoRAForge uses `.lforge` folder-based document packages:

```
MyProject.lforge/
  project.json          # Project metadata, prompts, and image records
  sources/              # Imported reference images
  generated/            # Generated images organized by prompt
    <prompt-uuid>/
      <image-uuid>.png
  trash/                # Discarded images (recoverable until emptied)
    <prompt-uuid>/
      <image-uuid>.png
```

Each generated image's record in `project.json` carries the prompt text, seed, and a snapshot of which source images contributed to it (id + filename + label) — so the inspector can render full provenance even after a source image has been removed from the project. Older `.lforge` files without these fields continue to load; their generated images simply show "—" for the missing data.

Server connections and templates are stored in `~/Library/Application Support/LoRAForge/`.

## Export Format

Exported datasets follow standard LoRA training conventions:

```
output/
  prefix_001.png
  prefix_001.txt    # Caption sidecar
  prefix_002.png
  prefix_002.txt
  ...
```

Export options include:
- **Source filter** — Finals only, shortlisted + finals, or all non-discarded
- **Resize** — None, fit longest edge, or exact dimensions (with presets for 512, 768, 1024)
- **Caption fallback** — Use prompt text, leave empty, or skip .txt file when no caption exists

## Dependencies

- [DrawThingsClient](https://github.com/euphoriacyberware-ai/DT-gRPC-Swift-Client) — Swift gRPC client for the Draw Things image generation API
- [DrawThingsQueue](https://github.com/euphoriacyberware-ai/DrawThingsQueue) — Swift API for queue functionality for the DrawThingsClient

## License

Copyright Euphoria Cyberware AI. All rights reserved.
