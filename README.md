# LoRAForge

A native macOS and iPadOS application for generating, curating, and captioning character-LoRA training datasets.

<!-- ![LoRAForge hero screenshot](screenshots/hero.png) -->

## Overview

LoRAForge provides a complete workflow for building high-quality LoRA training datasets. It connects to a [Draw Things](https://drawthings.ai) server for image generation and optionally to [Ollama](https://ollama.com) for AI-powered captioning, letting you go from prompt to export-ready dataset in a single app.

Images are generated from configurable prompts, ranked through a four-tier curation system, then tagged and captioned using a structured category-based tagging system that renders captions automatically. Finished datasets export as image + sidecar-text pairs ready for LoRA training.

Projects are stored as `.loraforge` bundles in a managed library. The app autosaves continuously, and generation results route to the correct project automatically — even if it is not the one currently selected.

## Features

- **Draw Things integration** — Generate images via a Draw Things gRPC server with full configuration control, including LoRAs, ControlNets, samplers, and more
- **Four-tier image ranking** — Curate generated images through candidate, shortlisted, final, and discarded tiers
- **Structured tagging system** — Category-based tag library with automatic caption rendering, prefix support, and separator control
- **Manual and AI-powered captioning** — Edit captions directly or auto-caption via Ollama; lock captions to freeze them and track drift
- **Reference image management** — Import reference images and attach them to prompts for img2img or ControlNet workflows
- **Prompt templates** — Save and load prompt sets as reusable templates across projects
- **Configuration presets** — Per-prompt configuration overrides with a full JSON editor
- **Dataset export** — Export image + caption (.txt) pairs with optional resizing, filename prefixes, and rank filtering
- **Dataset auditing** — Tag coverage analysis across your dataset to identify gaps before training
- **Legacy import** — Import v1 projects (`.lforge`) into the new `.loraforge` format

## Screenshots

<!-- Replace these placeholders with actual screenshots -->

| Dataset Builder | Caption Editor |
|:---:|:---:|
| <!-- ![Dataset Builder](screenshots/dataset-builder.png) --> *Dataset Builder — generate, rank, and curate images* | <!-- ![Caption Editor](screenshots/caption-editor.png) --> *Caption Editor — structured tagging with live preview* |

| Tag Library | Reference Library |
|:---:|:---:|
| <!-- ![Tag Library](screenshots/tag-library.png) --> *Tag Library — manage categories and tags across all projects* | <!-- ![Reference Library](screenshots/reference-library.png) --> *Reference Library — organize source images for generation* |

## Requirements

- macOS 15.0 or later / iPadOS 18.0 or later
- [Draw Things](https://drawthings.ai) running with gRPC server enabled (for image generation)
- [Ollama](https://ollama.com) running locally (optional, for AI-powered captioning)
- Xcode 16 or later (to build from source)

## Getting started

1. Clone this repository and open `LoRAForge.xcodeproj` in Xcode.
2. Let Swift Package Manager resolve dependencies.
3. Build and run.
4. Connect to a Draw Things server running with gRPC enabled.
5. Create a project from the sidebar and start adding prompts.

## How it works

1. **Create a project** — Projects live in the app's managed library. Each is a self-contained `.loraforge` bundle.
2. **Add prompts** — Write prompt text, attach reference images, and configure generation settings. Use templates to reuse prompt sets across projects.
3. **Generate images** — Send prompts to a Draw Things server. Results arrive asynchronously and are stored in the project bundle automatically.
4. **Curate** — Review generated images and rank them: promote good candidates through shortlisted to final, discard the rest.
5. **Tag and caption** — Assign tags from the structured tag library. Captions render automatically from your tags, or write them manually. Use Ollama for AI-assisted captioning.
6. **Audit** — Check tag coverage across your final images to ensure consistent representation before training.
7. **Export** — Export final images with their caption sidecars as training-ready pairs.

## Dependencies

- [DrawThingsQueue](https://github.com/euphoriacyberware-ai/DrawThingsQueue) — FIFO queue management for Draw Things image generation
- [DTConfigEditorKit](https://github.com/euphoriacyberware-ai/DTConfigEditorKit) — JSON editor for Draw Things generation configurations

## License

Copyright Euphoria Cyberware AI. All rights reserved.
