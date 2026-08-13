# LoRAForge

macOS and iPadOS app for generating and curating character-LoRA training datasets.
Images are generated through a remote Draw Things server, ranked, captioned, and exported
as image plus sidecar-text pairs.

---

## Documents

Read these before doing anything. They are in `Docs/`.

| File | What it is |
|---|---|
| `lora-tagging-system-design.md` | The tagging system — categories, tag library, caption rendering, auditing |
| `lora-dataset-app-design.md` | The application design — object model, views, integrations, persistence |
| `lora-dataset-app-build-plan.md` | Phase order and per-phase scope |

**Precedence.** Design documents beat the build plan. The build plan says *what to build
when*; the design documents say *how it behaves*. Where they conflict, the design documents
win and the conflict is worth reporting.

---

## The three markers

Every item in the design documents is marked. They mean different things and must be treated
differently.

**Decided** — settled. Implement as written. If it appears wrong, say so before changing it;
do not quietly implement something else.

**Recommended** — a proposal, not a decision. Implement it, but surface it: *this was a
Recommended item, here is what I built, it can go the other way.* Do not present these as
settled behaviour in a summary.

**Open** — not yet answered. **Stop and ask.** Do not pick an answer and continue.

---

## When the design is silent

Ask. Do not invent.

The design documents are unusually complete, so a gap is more likely to be a real gap than an
oversight worth filling in. Inventing behaviour here is costly in a specific way: much of the
design is load-bearing across sections — caption rendering, drift, coverage scoping and
export all read from the same model — so a locally reasonable guess can contradict something
three sections away.

If a gap blocks progress, say what is missing, propose options with trade-offs, and wait.

---

## Working discipline

**One phase at a time.** Each phase in the build plan lists what to leave alone. The common
failure is building UI for a subsystem that does not exist yet — it produces screens that
cannot be tested and constrains the real implementation when it lands.

**Each phase ends runnable and tested.** No phase should need a later phase to be verifiable.
Stub explicitly where a later dependency is unavoidable, and say what was stubbed.

**Report at phase end**: what was built, which Recommended items were implemented and remain
open to change, what was stubbed, and anything the design did not cover.

---

## Repository layout

```
Docs/            the three design documents — source of truth
LoRAForge/       app target
LoRAForgeTests/
LoRAForgeUITests/
References/      mockups and throwaway prototype code — see below
```

### `References/` is not a foundation

`References/EntryEditorViews` and `References/MainUI` are throwaway SwiftUI written only to
produce the mockup screenshots. They are not wired to real data and were never intended to
run as part of the app.

- Read them for **layout intent**
- Do not import, subclass, or extend them
- Do not move them into the app target
- Where they disagree with the design documents, the documents win

The mockups predate several decisions. The Entry Caption Editor's flat tag cloud in
particular was superseded — see design §6.5, which replaces it with per-category rows.

---

## Architecture

### Application shape

**Single window on both platforms. Not `DocumentGroup`-based.**

A sidebar lists projects from a managed library folder; selecting one changes the content
region. Project-scoped tabs — Dataset Builder, Reference Library — sit in the toolbar's
principal position, Calendar-style. The Tag Library is a **global** full-screen mode outside
those tabs, because it is not project-scoped and must not appear to change with the sidebar
selection.

Projects are `.loraforge` bundles in the library folder. The app can reach every project at
any time, which is what allows generation results to route to a project that is not currently
selected.

**Projects autosave.** There is no save command. Metadata writes are atomic — temp file then
swap — because there is no manual save point to fall back on.

### Module boundary

`TaggingCore` is a local Swift package, not a group in the app target. This is deliberate:
the compiler enforces its purity.

**`TaggingCore` must not import SwiftUI, SwiftData, or any I/O.** Plain Foundation is
expected and fine — `UUID`, `String`, and Unicode operations are exactly what the domain
model and renderer need. The rule excludes UI and persistence frameworks, not the standard
library.

It holds the domain model and the caption renderer, and it is the most heavily tested code in
the project. Anything that makes it un-unit-testable in isolation is a mistake regardless of
how convenient it is.

Other modules may start as groups and become packages if they earn it.

### Platform

- macOS 15 / iOS 18 minimum — above DrawThingsQueue's floor, for SwiftData `#Unique`
- Landscape is the iPad design target; **no portrait-specific layout**
- Build to a minimum usable width in size classes, not an orientation lock

### Dependencies

- `DrawThingsQueue` — image generation via a Draw Things gRPC server
- `DTConfigEditorKit` — generation configuration JSON editing

Do not reimplement what DrawThingsQueue provides. It already handles FIFO processing, pause
and resume, cancellation, reordering, retry, per-request status, progress with preview, and
persistence of pending requests.

---

## Known traps

These fail silently. They are worth re-reading before the phase that touches them.

**Result ingestion must consume the stream.** `DrawThingsQueue.maxCompletedResults` defaults
to 50 and drops older results. Subscribe to `results` or `events` and write images into the
bundle as they arrive. Polling `completedResults` loses images under load, and the loss looks
like a generation failure rather than a client bug.

**Route on project UUID, never file path.** The request-to-entry map keys on the stable
project UUID stored in the bundle. Path-keyed routing breaks when a bundle is renamed or
moved, and only then.

**Tags reference categories by ID, never by name.** Renaming a category, editing its prefix,
or reordering it must never touch stored assignments.

**Tags cannot be renamed.** There is no rename affordance anywhere. The canonical string is
fixed at creation, which is what makes duplicate detection at creation sufficient. Import is
the only other path a string can enter the library, and it must run the same fuzzy check.

**Locked captions are frozen text.** Retain their tags and settings. Do not re-render them.
Show drift instead — see design §6.3.

**Batch size is fixed at 1**, and the app owns the seed. Any seed or batch value in a Draw
Things configuration is ignored and is annotated as overridden in the editor.

**Autosave must write atomically.** Temp file then swap. Without `NSDocument` and without a
manual save point, a crash mid-write leaves a truncated project with nothing to fall back on.
Image files are write-once and do not participate in the debounce.

**Audit scope is narrow**: tagged-mode entries that have a final image. Not all entries, not
all tagged entries. The panel states its denominator.

---

## Conventions

- Swift concurrency (`async`/`await`) over completion handlers
- Repository interfaces over `@Model` types leaking into views
- Warnings that carry counts state what the count covers — cross-project counts can only
  cover known projects, and must say so
- Sentence case in UI text

---

## Commands

```
xcodebuild -scheme LoRAForge -destination 'platform=macOS' build
xcodebuild -scheme LoRAForge -destination 'platform=macOS' test
swift test --package-path Packages/TaggingCore
```

Correct these if the scheme names differ.
