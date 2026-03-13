# LoRAForge

A native macOS application for building LoRA training datasets. LoRAForge connects to [Draw Things](https://drawthings.ai) for image generation and [Ollama](https://ollama.com) for AI-powered captioning, providing a streamlined workflow from prompt creation to export-ready datasets.

## Features

- **Image Generation** — Generate images via Draw Things gRPC server with full configuration control (73+ parameters including LoRAs, ControlNets, samplers, and more)
- **Source Image Management** — Import reference images and attach them to prompts for img2img or ControlNet workflows
- **Prompt Templates** — Save and load prompt sets as reusable templates across projects
- **Image Curation** — Rank generated images through a four-tier system: candidate, shortlisted, final, discarded
- **AI Captioning** — Single or bulk auto-captioning via Ollama with configurable model and prompt
- **Lightbox Viewer** — Full-size image preview with keyboard navigation and inline rank/caption editing
- **Trash & Undo** — Soft-delete with restore capability; prompt deletion supports undo (Cmd+Z)
- **Flexible Export** — Export image + caption (.txt) pairs with optional resizing and filename prefixes

## Requirements

- macOS 15.0 or later
- Xcode 16+ (to build from source)
- [Draw Things](https://drawthings.ai) running with gRPC server enabled (for image generation)
- [Ollama](https://ollama.com) running locally (for auto-captioning)

## Getting Started

1. **Build and run** the project in Xcode
2. **Configure servers** — Open **Project > Address Book** to add your Draw Things and Ollama server connections
3. **Create a project** — A new `.lforge` document opens automatically; save it to begin importing images

## Workflow

1. **Import source images** — Add reference images from the sidebar for use in img2img or ControlNet prompts
2. **Create prompts** — Add prompts in the sidebar, attach source images, and set generation count
3. **Configure generation** — Select a Draw Things server from the toolbar; optionally set per-prompt configuration overrides via the JSON editor
4. **Generate** — Click **Run** to generate for prompts without a final image, or **Run All** to regenerate everything
5. **Curate** — Review generated images in the grid or lightbox; promote (candidate → shortlisted → final) or discard
6. **Caption** — Edit captions manually per image, or use **Auto-caption** to bulk-caption all uncaptioned images via Ollama
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

## License

Copyright Euphoria Cyberware AI. All rights reserved.
