# LoRAForge — Full Implementation Specification

## Identity & Bundle

| Field | Value |
|-------|-------|
| App name | LoRAForge |
| Bundle ID | `euphoria-ai.LoRAForge` |
| Document type UTI | `com.euphoria-ai.lforge` |
| File extension | `.lforge` |
| Document type name | LoRAForge Project |
| Package format | Folder-based document (NSDocument subclass wrapping a directory) |

---

## Dependencies

- **DrawThingsClient** — `https://github.com/euphoriacyberware-ai/DT-gRPC-Swift-Client` (Swift Package, public)
- No other third-party dependencies; use Foundation, SwiftUI, AppKit, Core Graphics, Core Image as needed.

---

## Project Package Layout

```
MyProject.lforge/
  project.json
  sources/
    <uuid>.png   (or .jpg)
  generated/
    <prompt-uuid>/
      <image-uuid>.png
  trash/
    <prompt-uuid>/
      <image-uuid>.png
```

---

## Full Data Model

All structs are `Codable`. `project.json` is the root document file written inside the `.lforge` package.

```swift
// project.json root
struct Project: Codable {
    var id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date
    var generationConnectionID: UUID?     // Address Book → DrawThings
    var captionConnectionID: UUID?        // Address Book → Ollama
    var baseConfiguration: Configuration  // Draw Things JSON model (from DrawThingsClient package)
    var sourceImages: [SourceImage]
    var prompts: [Prompt]
}

struct SourceImage: Codable, Identifiable {
    var id: UUID
    var filename: String                  // relative path: sources/<uuid>.png
    var label: String?
}

struct Prompt: Codable, Identifiable {
    var id: UUID
    var order: Int
    var text: String
    var sourceImageIDs: [UUID]            // ordered references to SourceImage.id
    var generateCount: Int
    var configurationOverride: Configuration?   // nil = use project base config
    var generatedImages: [GeneratedImage]
}

struct GeneratedImage: Codable, Identifiable {
    var id: UUID
    var filename: String                  // relative path: generated/<prompt-uuid>/<image-uuid>.png
    var rank: ImageRank
    var caption: String?
    var generatedAt: Date
    var seed: Int?                        // if returned by gRPC; useful for reproducibility
}

enum ImageRank: String, Codable, CaseIterable {
    case candidate     // default — included in generation runs
    case shortlisted   // liked — still included in generation runs
    case final_        // definitive — skipped in generation runs
    case discarded     // hidden — moved to trash/, pending Empty Trash
}

// Stored in ~/Library/Application Support/LoRAForge/connections.json
struct ServerConnection: Codable, Identifiable {
    var id: UUID
    var name: String
    var type: ConnectionType
    var host: String
    var port: Int
    var modelName: String?               // Ollama only (e.g. "llava", "moondream")
    var captionPrompt: String?           // Ollama only — system prompt prefix for captioning
}

enum ConnectionType: String, Codable {
    case drawThings
    case ollama
}

// Stored in ~/Library/Application Support/LoRAForge/templates.json
struct Template: Codable, Identifiable {
    var id: UUID
    var name: String
    var createdAt: Date
    var prompts: [TemplatePrompt]
}

struct TemplatePrompt: Codable, Identifiable {
    var id: UUID
    var order: Int
    var text: String
    var sourceSlotIndex: Int?            // 0-based index into project's sourceImages array
    var generateCount: Int
}
```

---

## App-Level Persistent Storage

Stored in `~/Library/Application Support/LoRAForge/`:

```
connections.json    ←  [ServerConnection]
templates.json      ←  [Template]
```

---

## Rank System

### Rank Ladder

| Rank | Meaning | Included in generation runs? |
|------|---------|------------------------------|
| `candidate` | Default for all new generations | Yes |
| `shortlisted` | Liked, but want more options | Yes |
| `final_` | Definitive selection | No (skipped) |
| `discarded` | Hidden, moved to trash | No |

### Rank Transition Rules

| Action | Result |
|--------|--------|
| New generation | rank = `.candidate` |
| Promote candidate | → `.shortlisted` |
| Promote shortlisted | → `.final_` |
| Demote final | → `.shortlisted` (re-opens prompt to generation) |
| Demote shortlisted | → `.candidate` |
| Discard (any rank) | → `.discarded` + move file to `trash/<prompt-uuid>/` |
| Restore from trash | → `.candidate` + move file back to `generated/<prompt-uuid>/` |
| Empty Trash | Permanently delete all files in `trash/`, remove records from project.json |

---

## UI Structure

### Menu Bar

```
File
  New Project, Open, Close, Save, Duplicate
  Export...

Generation
  Run (prompts without a Final image)
  Run All (regenerate everything)
  Stop

Captions
  Auto-caption All Uncaptioned

Project
  Empty Trash
  Address Book
  Template Library
```

### Address Book (sheet)

- Segmented control: Draw Things | Ollama
- List of connections (name, host:port)
- Add / Edit / Delete buttons
- Test Connection button (ping gRPC or HTTP health check)
- Ollama-specific fields: model name, caption prompt text editor (multi-line)

### Template Library (sheet)

- List of saved templates (name, date, prompt count)
- Load into Project button — prompts user: Append or Replace
- Save Current Prompts as Template — prompts for a name
- Delete template

### Main Document Window

```
Toolbar
  Server picker         ← dropdown of DrawThings connections from Address Book
  ▶ Run Generation      ← prompts without a Final image
  ⟳ Run All            ← all prompts
  ⏹ Stop
  🗑 Toggle Trash View
  ✨ Auto-caption All
  Export...

NavigationSplitView
  ├── Left Sidebar
  │     ├── Section: Source Images
  │     │     ├── Thumbnail grid or list
  │     │     ├── Import button (NSOpenPanel, multi-select, images only)
  │     │     ├── Inline label editing
  │     │     └── Remove (only if not referenced by any prompt)
  │     │
  │     └── Section: Prompts
  │           ├── Reorderable list (drag handle)
  │           ├── Row shows: prompt text preview + Final badge if complete
  │           ├── + Add Prompt
  │           ├── Load from Template
  │           └── Save as Template
  │
  └── Content Area — Selected Prompt Detail
        ├── Prompt text editor (multiline TextEditor)
        ├── Source image slot picker
        │     └── Horizontal scroll list of slots
        │         Each slot: thumbnail or "None" placeholder
        │         Tap slot → sheet to pick from project source images
        ├── Generate count stepper (1–N, default 4)
        ├── Config override toggle
        │     └── When ON: raw JSON TextEditor (monospaced font, validates on change)
        ├── Generation progress (shown during active task for this prompt)
        │
        └── Generated Images Grid
              ├── Normal view: candidate + shortlisted + final images
              ├── Trash view (toolbar toggle): discarded images only
              │
              └── Each image cell:
                    ├── Thumbnail (square, consistent size)
                    ├── Rank badge overlay (color-coded corner badge)
                    ├── Caption text field (editable inline, below thumbnail)
                    ├── ✨ Auto-caption button (single image, calls Ollama)
                    │
                    └── Right-click context menu:
                          Promote Rank
                          Demote Rank
                          Discard
                          ─────────────
                          View Full Size
                          Reveal in Finder
                          ─────────────
                          (Trash view only:)
                          Restore
                          Delete Permanently

Lightbox (full-screen overlay on image click)
  ├── Full-size image
  ├── Rank controls (promote / demote / discard buttons)
  ├── Caption editor (multi-line text field)
  └── ← → navigation between images in current prompt
```

---

## Generation Task

```swift
func runGeneration(runAll: Bool) async {
    // 1. Determine which prompts to process
    let promptsToRun: [Prompt]
    if runAll {
        promptsToRun = project.prompts
    } else {
        promptsToRun = project.prompts.filter { prompt in
            !prompt.generatedImages.contains { $0.rank == .final_ }
        }
    }

    // 2. Iterate sequentially
    for prompt in promptsToRun {
        // a. Resolve configuration
        let config = prompt.configurationOverride ?? project.baseConfiguration

        // b. Load source image data
        let imageData: [Data] = prompt.sourceImageIDs.compactMap { id in
            guard let source = project.sourceImages.first(where: { $0.id == id }) else { return nil }
            let url = packageURL.appendingPathComponent("sources/\(source.filename)")
            return try? Data(contentsOf: url)
        }

        // c. Build and send gRPC request
        let request = buildDrawThingsRequest(prompt: prompt.text, config: config, images: imageData)
        let responses = try await drawThingsClient.generate(request)

        // d. Save each result
        for response in responses {
            let imageID = UUID()
            let filename = "\(imageID).png"
            let promptDir = packageURL
                .appendingPathComponent("generated")
                .appendingPathComponent(prompt.id.uuidString)
            try FileManager.default.createDirectory(at: promptDir, withIntermediateDirectories: true)
            try response.imageData.write(to: promptDir.appendingPathComponent(filename))

            let generated = GeneratedImage(
                id: imageID,
                filename: filename,
                rank: .candidate,
                caption: nil,
                generatedAt: Date(),
                seed: response.seed
            )
            // Append to prompt's generatedImages — update UI on main actor
            await MainActor.run { prompt.generatedImages.append(generated) }
        }

        // e. Persist after each prompt completes
        saveProject()
    }
}
```

---

## Ollama Auto-Caption

### API Call

```
POST http://{connection.host}:{connection.port}/api/generate
Content-Type: application/json

{
  "model": "{connection.modelName}",
  "prompt": "{connection.captionPrompt}",
  "images": ["{base64EncodedPNG}"],
  "stream": false
}
```

Response field to use: `response.response` (string)

### Single Image Caption

- Button (✨) on each image cell
- Calls Ollama, sets `generatedImage.caption` on response
- Shows spinner on button while in-flight

### Bulk Auto-Caption

- Toolbar action: "Auto-caption All Uncaptioned"
- Runs sequentially through all non-discarded images where `caption == nil`
- Progress shown in toolbar (e.g. "Captioning 3 / 47")

---

## Export

### Export Sheet Options

| Setting | Options |
|---------|---------|
| Source | Finals only / Shortlisted + Finals / All non-discarded |
| Resize | None / Fit longest edge (px) / Exact size (W × H) |
| Size presets | 512 / 768 / 1024 / Custom |
| Filename prefix | Text field (default: project name) |
| Caption fallback | Leave .txt empty / Use prompt text / Skip .txt file entirely |
| Output folder | NSOpenPanel (folder picker) |

### Output Structure

```
ExportFolder/
  {prefix}_001.png
  {prefix}_001.txt    ← caption text (or empty, or omitted per fallback setting)
  {prefix}_002.png
  {prefix}_002.txt
  ...
```

### Resizing

Use `CILanczosScaleTransform` via Core Image for high-quality downscaling.

---

## Implementation Phases

| # | Phase | Description |
|---|-------|-------------|
| 1 | Project scaffold | Xcode project, SwiftUI App, NSDocument subclass, `.lforge` UTI registration, document package folder creation, app icon placeholder |
| 2 | Data model | All Codable structs, project.json read/write, package folder management (sources/, generated/, trash/) |
| 3 | App-level persistence | connections.json + templates.json in Application Support |
| 4 | Address Book UI | List, add/edit/delete, test connection, Ollama caption prompt field |
| 5 | Main window shell | NavigationSplitView skeleton, sidebar scaffolding, toolbar buttons (non-functional placeholders) |
| 6 | Source image import | NSOpenPanel multi-select, copy to sources/, thumbnail display, inline label editing, remove |
| 7 | Prompt list & detail | Add/remove/reorder prompts, detail view, source slot picker, generate count stepper |
| 8 | Template save/load | Template library sheet, save current prompts, load (append or replace), delete |
| 9 | Config JSON editor | Base config raw text editor, per-prompt override toggle + editor, JSON validation |
| 10 | gRPC generation task | Wire DrawThingsClient, sequential task runner, progress UI, file writing, project.json persistence |
| 11 | Image grid + ranks | Thumbnail grid, rank badge overlays, right-click context menus, promote/demote/discard actions |
| 12 | Lightbox | Full-size overlay, rank controls, caption editor, ← → navigation |
| 13 | Inline captions | Caption text field per image cell, single-image Ollama auto-caption button |
| 14 | Bulk auto-caption | Sequential captioning with toolbar progress indicator |
| 15 | Trash bin | Trash view toggle, restore, Empty Trash (permanent delete) |
| 16 | Export | Export sheet, rank filter, Core Image resize, filename pattern, .txt sidecar writing |

---

## Notes for Claude Code

- The `Configuration` struct is defined in the `DrawThingsClient` Swift package — import and use it directly, do not redefine it.
- The `.lforge` document package is a **directory**, not a flat file. `NSDocument` must be subclassed with `isEntireFileLoaded = false` and proper `read(from:ofType:)` / `write(to:ofType:)` implementations that operate on the folder URL.
- Register the document type in `Info.plist` as a package (set `LSTypeIsPackage = YES` and `CFBundleTypeRole = Editor`).
- App Support directory path: `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("LoRAForge")`
- All file moves (discard → trash, restore → generated) should be done with `FileManager.moveItem(at:to:)`, not copy+delete.
- Seed value may not be returned by all Draw Things gRPC responses — handle optionally.
- The Ollama `/api/generate` endpoint is a simple HTTP POST — use `URLSession`, no special library needed.
