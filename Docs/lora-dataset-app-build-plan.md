# LoRA Dataset Builder — Build Plan

Implementation plan for `lora-dataset-app-design.md` and `lora-tagging-system-design.md`.
Those two documents are the specification; this one is the order of work.

---

## 0. How to use this plan

**The design documents are the source of truth.** This plan says what to build and in what
order; it does not restate behaviour. Where the two disagree, the design documents win.

**Where the design is silent, stop and ask rather than inventing.** The design docs mark
items **Decided**, **Recommended**, and **Open**. Recommended items are proposals — implement
them, but flag them as decision points rather than treating them as settled. Open items are
not yet answered and should not be guessed at.

**Each phase ends in something runnable and testable.** No phase should require a later phase
to be verifiable. Where a later dependency is unavoidable, stub it explicitly rather than
building ahead.

**Do not build ahead.** Each phase lists what to leave alone. The most common failure mode
here is building UI for a subsystem that does not exist yet, which produces plausible screens
that cannot be tested and that constrain the real implementation when it arrives.

---

## 1. Architecture

### Targets and modules

```
LoRAForge/                     app target (SwiftUI, macOS + iPadOS)
Packages/
  TaggingCore/                 domain types, caption renderer — pure Swift, no UI, no I/O
```

**Create packages when a phase gives them content, not upfront.** `TaggingCore` is created
in phase 0 because the purity constraint is the reason it exists as a package at all — the
compiler enforcing it is the point.

Everything else starts as a group in the app target and is promoted only if it earns it.
Empty package shells add build overhead and fix module boundaries before there is code to
draw them around.

`Generation` is the most likely to earn promotion: request routing and result staging are
both in the risk register as silent-failure paths, and a package boundary is what makes them
testable against a stubbed queue without running the app. Assess at phase 9.

Candidate groupings as content arrives — project and entry types with the document format,
SwiftData models with their repositories, the Ollama client — but these are organisation,
not architecture, until something makes them worth isolating.

### External dependencies

| Package | Purpose | Notes |
|---|---|---|
| DrawThingsQueue | Image generation | Requires macOS 14 / iOS 17 |
| DTConfigEditorKit | Generation config JSON editing | |

### Deployment target

macOS 15 / iOS 18 — above DrawThingsQueue's floor, to get SwiftData's `#Unique`
(design §9.4). Confirm `#Unique` availability at this target before relying on it; the
fallback is application-level uniqueness enforcement, which is needed anyway.

### Platform

Landscape is the iPad design target. Build to a minimum usable width in size classes rather
than an orientation lock (design §1.1). No portrait-specific layout.

---

## 2. Phase overview

| # | Phase | Depends on | Milestone |
|---|---|---|---|
| 0 | Scaffold and settings shell | — | Runs, empty |
| 1 | Tagging core and caption renderer | 0 | Renderer passes its tests |
| 2 | App-level store | 1 | Categories and tags persist |
| 3 | Tag Library view | 2 | Vocabulary is manageable |
| 4 | Document format and persistence | 1, 2 | Projects save and reopen |
| 5 | Dataset Builder | 4 | Entries, ranks, manual images |
| 6 | Caption editor | 3, 5 | **App is usable end to end** |
| 7 | Export | 6 | Training sets come out |
| 8 | Generation spike | 0 | Connection proven |
| 9 | Generation integration | 5, 8 | Images arrive from Draw Things |
| 10 | Reference Library | 9 | Moodboard hints |
| 11 | Ollama captioning | 6 | Auto-captioning |
| 12 | Auditing | 6 | Distribution analysis |

Phase 6 is the point at which the app does its job: images added by hand can be ranked,
captioned, and — after 7 — exported. Everything from 8 onward makes it better rather than
making it work.

**Phase 8 is deliberately out of order.** It is a throwaway spike to prove the Draw Things
connection early, before phase 9 depends on it. Run it any time after phase 0.

---

## 3. Phases

### Phase 0 — Scaffold and settings shell

**Goal.** A running app with navigation and an empty settings dialogue.

**Build**
- Xcode project, local SPM packages per §1, deployment targets set
- DrawThingsQueue and DTConfigEditorKit added and building
- Three-view navigation shell: Dataset Builder, Reference Library, Tag Library
- Tabbed settings dialogue (design §10.1) with the five tabs present and empty
- Size-class-aware layout scaffolding

**Done when.** The app launches on both platforms, all views and settings tabs are
reachable, and everything is empty.

**Do not build yet.** Any view content. Any persistence.

---

### Phase 1 — Tagging core and caption renderer

**Goal.** The pure domain layer, fully tested, with no UI or storage.

This is the highest-value phase to get exactly right. Everything downstream reads from it,
and it is the only part of the system that can be verified completely in isolation.

**Build**
- `Tag`, `Category`, `CategoryProperties` (select mode, prefix, position, enabled,
  thresholds), `TagAssignment` — see tagging doc §3
- Stable IDs throughout; assignments reference categories by ID, never by name
  (tagging doc §6)
- The caption renderer: assignments + category set + order → caption string
- Fuzzy duplicate detection against a tag list — the matching function only, no UI

**Renderer rules to test explicitly** (tagging doc §5)
- Tag text renders verbatim; no appending, rewriting, or normalising
- Prefixes render before values; a prefix with no values emits nothing
- Multi-select joins with `and`, in selection order, never sorted
- Empty categories are omitted along with their comma
- Subject is position zero, prefix-less
- Disabled categories render nothing

**Done when.** Unit tests cover every rule above, including the example render in tagging
doc §4, and the renderer has no import of SwiftUI or SwiftData.

**Do not build yet.** Persistence. Any UI. The audit — it reads this model but belongs in
phase 12.

---

### Phase 2 — App-level store

**Goal.** Categories and the global tag library persist.

**Build**
- SwiftData models mirroring the phase 1 domain types
- Repository interfaces wrapping the store, so `@Model` types do not leak into views
  (design §9.4)
- The eleven built-in categories seeded on first launch (tagging doc §4), each carrying its
  own 70/10 threshold pair rather than pointing at a shared constant (tagging doc §8)
- Uniqueness on canonical string within a category — `#Unique` plus an application-level
  check
- App preferences: default category order, default enabled state, default thresholds
- Known-projects index (design §9.4)

**Done when.** Categories and tags survive relaunch, built-ins seed correctly, and a
duplicate canonical string within a category is rejected by both the constraint and the
application path.

**Do not build yet.** Project documents. Tag Library UI.

---

### Phase 3 — Tag Library view

**Goal.** The vocabulary and category set are manageable.

**Build**
- Category list: reorder, rename, edit prefix, enable/disable, edit thresholds
- Built-ins cannot be deleted, only disabled (tagging doc §3)
- User categories: create and delete
- Tag library per category: create, delete, search
- Duplicate detection at creation, surfacing near-matches before committing
  (tagging doc §6)
- Tags cannot be renamed — no affordance for it
- Warnings with affected counts on reorder, prefix edit, disable, delete

**Note.** Affected counts span projects and are only answerable for known projects
(design §9.4). The warning must say so — *affects 34 images across 3 known projects* —
rather than implying completeness.

**Done when.** The full category and tag lifecycle works, and every destructive or
caption-rewriting edit warns with a count.

**Do not build yet.** Drift indicators — they need locked captions, phase 6.

---

### Phase 4 — Document format and persistence

**Goal.** Projects exist as bundle documents that save, reopen, and reconcile.

**Build**
- Bundle document: `Codable` JSON metadata plus image files in the package
  (design §9.4)
- Stable project UUID in the bundle (design §5.1)
- Project-level properties: category order and enabled state, snapshotted at creation and
  independent thereafter (design §7)
- Schema snapshot written on save: tags with IDs, canonical strings, owning category; and
  categories with IDs, names, select modes, prefixes, thresholds (design §9.1)
- Reconciliation on open: the four-case table in design §9.2
- Import flow, running through the same fuzzy duplicate detection as creation
  (design §9.3)

**Done when.** A project round-trips, and a project opened against a library missing some of
its tags offers import rather than failing or silently rendering wrong.

**Test explicitly.** Create a project, delete one of its tags from the library, reopen.
Import should be offered. This is the case the whole schema snapshot exists for.

**Do not build yet.** Entry content beyond what the format needs.

---

### Phase 5 — Dataset Builder

**Goal.** Entries, image ranks, and manual image import.

**Build**
- Entry list with position numbers, three digits, true project position (design §8.3)
- Horizontally scrolling image strip per entry
- Four ranks with badges: final (solid star), shortlist (hollow star), candidate (none),
  discarded (trash can) — design §2.2
- Rank visibility toggles; discarded hidden by default (design §3.1)
- Entry text filter, plus state filters — no final, not captioned (design §3.1)
- Sweep per entry: all candidates to discarded, no confirmation, with undo (design §2.3)
- Empty trash, project-wide, warning with image and entry counts
- Manual image import: drag-drop and file picker
- Promotion between ranks; promoting a new final demotes the previous to shortlist
- Warning when discarding the current final (design §2.2)

**Done when.** Images can be added, ranked, swept, and permanently removed, and the entry
list reflects all of it. Counts report inventory and do not respond to filters.

**Do not build yet.** Captions. Generation. The Audit button — leave it present and inert.

---

### Phase 6 — Caption editor

**Goal.** The app becomes usable end to end.

**Build**
- Caption editor: image well, caption field, persistent mode (design §6)
- Tag panel: one row per enabled category in caption order, token fields with type-ahead
  (design §6.5)
- Panel visible in all modes; tags stageable regardless of mode
- Live render preview below the rows, pinned; rows scroll
- iPad picker sheet on row tap (design §6.5)
- Drag to reorder tokens within a multi-select row
- Tag creation inline, running duplicate detection
- Mode switching with replacement and undo (design §6.1)
- Locking: freeze text, retain tags and settings (design §6.3)
- Drift indicators for all four causes — tag deleted, prefix edited, categories reordered,
  category disabled
- Unlock showing a before/after diff
- Warning counts split by lock state — *N rewritten, M drifted* (design §6.3)

**Done when.** An entry can be captioned by tags or by hand, locked, and shown to drift when
the library changes underneath it. Manual mode has spellcheck.

**Milestone.** With phase 7, the app does its job.

**Do not build yet.** Ollama — the wand is present and disabled.

---

### Phase 7 — Export

**Goal.** Training sets come out.

**Build**
- Export dialogue: base name field, scope selector, standard OS directory picker
- Three scopes: finals only (default), finals and shortlist, all images (design §8.1)
- Naming: `<name>_<NNN>` for finals, `-N` suffix for additional images (design §8.3)
- Sidecar `.txt` per final, UTF-8 without BOM, trailing newline; empty when uncaptioned
- Locked entries export stored text; unlocked tagged-mode entries render fresh
  (design §8.4)
- Clear-first offer when the destination already holds an export
- Base name remembered per project
- Reporting of what was skipped

**Done when.** A project exports to a directory a trainer can consume, and re-exporting an
unchanged project produces identical filenames.

**Do not build.** A manifest. Explicitly out of scope (design §8.6).

---

### Phase 8 — Generation spike *(throwaway; run any time after phase 0)*

**Goal.** Prove the Draw Things connection before phase 9 depends on it.

**Build**
- Connect to a Draw Things gRPC server
- Enqueue one text-to-image request with batch size 1
- Receive the result and display it
- Observe progress and the preview image

**Answer these questions**
- Does `DrawThingsConfiguration` expose seed, and does the app-supplied seed take effect?
- What does the config JSON look like in practice, and how does DTConfigEditorKit present it?
- What happens on connection failure, and what does `lastError` contain?

**Done when.** An image comes back and the questions above are answered.

**Then delete it.** This is a spike, not a foundation.

---

### Phase 9 — Generation integration

**Goal.** Images arrive from Draw Things into the right entry.

**Build**
- Single app-level `DrawThingsQueue`, with server settings in the Draw Things tab
- Entry generation editor: name, prompt, negative prompt, seed with custom toggle,
  generation config via DTConfigEditorKit
- Seed owned by the app; seed and batch annotated as overridden in the config editor
  (design §5.2)
- Batch size fixed at 1
- Persistent request-to-entry map, keyed on project UUID plus entry ID (design §5.1)
- **Result ingestion driven by the results stream or events publisher, not by polling
  `completedResults`** — the queue caps retained results and drops older ones
- Staging to the app container for closed documents; ingestion on next open
- Orphan surfacing for staged results whose project cannot be found
- Ingestion marks the document dirty but is not registered with the undo manager
- Queue pauses on background, resumes on foreground
- Per-image provenance: generation config, seed, and reference links stored with each image
  (design §5.3)
- Right-click recall of an image's settings to its entry, with the seed actually used
- Per-project view of pending work
- Failures surfaced on the originating entry; connectivity pause as a project-level banner

**Done when.** Generation works, results route correctly with two projects open, and closing
a project with work in flight does not lose images.

**Test explicitly.** Queue work in project A, switch to project B, confirm results land in A.
Then close A with work pending and confirm ingestion on reopen.

**Highest-risk phase.** The ingestion contract and the routing map are the two things most
likely to be got subtly wrong, and both fail silently.

---

### Phase 10 — Reference Library

**Goal.** Moodboard hints.

**Build**
- Project-scoped image collection: drag-drop, file picker, copy from entry
- Deduplication on content hash at add time
- Usage display — which entries reference each image
- Four reference slots per entry, referencing library images
- Passed as moodboard hints at weight 1.0 (design §5.1)
- Removal warning counting both entries and stored image provenance
- Dangling provenance links retained and shown as missing

**Done when.** Reference images influence generation and removal warns accurately.

---

### Phase 11 — Ollama captioning

**Goal.** Auto-captioning from a vision model.

**Build**
- Ollama client
- Profile management in the Ollama settings tab: name, endpoint, model, instruction
- Wand enabled only when the entry has a final image, explaining itself when disabled
- Response replaces caption text, with undo
- Optional project-level default profile

**Done when.** An entry with a final can be captioned by a vision model, and profiles are
switchable.

---

### Phase 12 — Auditing

**Goal.** Distribution analysis.

**Build**
- Per-category coverage histogram
- Scope: tagged-mode entries with a final image only (design §7)
- Explicit denominator statement — *18 of 27 entries; 6 not finalized, 3 not tag-captioned*
- Flagging above and below per-category thresholds, defaulting to 70/10
- Multi-select categories: presence of any tag counted separately from individual value
  frequency
- Partial coverage flagged; 0% and 100% treated as decisions rather than errors

**Done when.** The audit reports over the correct subset and states what it excluded.

---

## 4. Testing strategy

| Layer | Approach |
|---|---|
| `TaggingCore` | Exhaustive unit tests. Every renderer rule, every duplicate-detection case. |
| Document format | Round-trip tests, plus reconciliation against a divergent library. |
| Store | Uniqueness enforcement, built-in seeding, cross-project counting. |
| Generation routing | Integration tests with a stubbed queue — two projects, closed-document staging, orphans. |
| UI | Manual, both platforms, both window widths. |

The two subsystems that fail silently are the renderer and generation routing. Both deserve
tests that assert on exact output rather than on absence of error.

---

## 5. Risk register

| Risk | Phase | Mitigation |
|---|---|---|
| Result ingestion polls instead of streaming; images lost under load | 9 | Written into the phase; test with a queued burst |
| Routing map keyed on file path rather than project UUID | 9 | Explicit in the design; test with a renamed bundle |
| Recalled seed does not reproduce the image | 9 | Batch fixed at 1; verify in the phase 8 spike |
| SwiftData migration difficulty | 2+ | Schema snapshots make the library rebuildable from documents |
| Tag panel too tall in landscape on smaller iPads | 6 | Scrolling; hide-empty-categories preference in reserve |
| `#Unique` unavailable at target | 2 | Application-level check, needed regardless |

---

## 6. Carried-forward items

Answer during the phase that touches them, not before:

- Whether `#Unique` is available at the deployment target — phase 2
- Whether seed is exposed on `DrawThingsConfiguration` — phase 8
- Whether the 0.85 tag-matching threshold holds up in use — after phase 3, with a real
  vocabulary
- Whether 70/10 audit thresholds hold up in use — after phase 12, with real datasets
- Whether four reference slots is the right ceiling — after phase 10, with real datasets
