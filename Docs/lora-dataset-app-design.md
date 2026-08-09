# LoRA Dataset Builder — Application Design

Companion to `lora-tagging-system-design.md`. That document specifies the tagging
system in isolation; this one specifies the application that hosts it — the object
model, the three views, the entry lifecycle, and the integration boundaries.

Items are marked **Decided** (settled), **Recommended** (proposed, not yet adopted),
or **Open** (needs a decision).

---

## 1. Purpose and Scope

An application for generating and curating character-LoRA training datasets. The user
generates candidate images against a set of dataset entries, promotes one image per
entry as the export candidate, captions each entry, and exports the result as a
training set.

Platform: **macOS and iPadOS.** *Decided.* Deployment floor macOS 15 / iOS 18 — see
§9.4; DrawThingsQueue requires macOS 14 / iOS 17, and the extra release buys SwiftData's
`#Unique` constraint.

**Scope: single user, possibly across multiple devices.** *Decided.* Multi-user
sharing, team workflows, and community distribution of projects or vocabularies are out
of scope for this build. General usability is worth pursuing, but not at the cost of
designing for collaboration that will not happen.

### 1.1 Layout target

**Decided.** Landscape is the design target on iPad. Every view is two- or three-pane —
the Dataset Builder pairs an entry header with a horizontally scrolling image strip, the
caption editor pairs an image with the tag panel, the generation editor is three columns.
The Dataset Builder is the binding case: in portrait its strip shows two or three
thumbnails, which defeats the view.

**Decided.** No portrait-specific layout is designed or built.

**Note — orientation lock is not a width guarantee.** On modern iPadOS, an app that
supports multitasking receives arbitrary window widths from Split View and Stage Manager
regardless of declared orientation. Locking to landscape stops the device rotating; it does
not stop the window being half a screen wide.

The real constraint is therefore a **minimum usable width, expressed in size classes**,
rather than an orientation.

**Recommended:** design to that minimum and let narrower widths degrade to something
coherent — a single pane, or the entry list without its strip — rather than breaking. This
is more robust than opting out of multitasking, and it does not depend on an API whose
status is moving.

**Open:** whether opting out of multitasking is still available and worth using.
`UIRequiresFullScreen` historically provided a genuine guarantee, but iPadOS 26 moved toward
resizable windows for all apps and the flag may no longer have that effect. Worth verifying
against current documentation before relying on it. For a single-user tool that will never
be used in Split View the guarantee would be convenient, but not at the cost of building
against a deprecated path.

Out of scope: training itself, trainer-specific configuration, and anything downstream
of export.

---

## 2. Object Model

```
Project
├── Dataset Entries        (ordered)
│   ├── Generation settings
│   ├── Candidate Images   (0..n; ranked unranked / shortlist / final)
│   └── Caption            (exactly one, with a persistent source mode)
├── Reference Library      (project-scoped image collection)
└── Subject tag library    (project-scoped — see tagging doc §6)

App
├── Category set           (global, shared by all projects)
├── Tag library            (global, except Subject)
└── Preferences            (app-level defaults for order, enabled state, thresholds)
```

### 2.1 The entry is the unit of the dataset

**Decided.** A dataset entry produces exactly one exported image and exactly one
caption. Candidate images are working inventory; only the final is exported.

This resolves the reading of the tagging document: wherever it says *image*, it means
*the final image of a dataset entry*. Every coverage and distribution rule in tagging
doc §8 applies at entry granularity.

It also means two counts must never be conflated in the UI. The Dataset Builder header
reads `4 entries · 27 images`, but the exported dataset is four images. Anywhere a
count drives a judgement — the audit especially — it must be an entry count, and the
UI should say so.

### 2.2 Image ranks

**Decided.** Four ranks. At most one final per entry; the other three are unbounded.

| Rank | Badge | Visible by default |
|---|---|---|
| Final | Solid star | Yes |
| Shortlist | Hollow star | Yes |
| Candidate | None | Yes |
| Discarded | Trash can | No |

Candidate is the unranked default — every generated image arrives as one, and the
absence of a badge is what marks it.

Shortlist is a flag, not an ordering — it marks images kept in contention while
culling. Promoting a new final demotes the previous final to shortlist rather than to
candidate, since the displaced image was, by definition, good enough to have been
chosen once.

**Decided.** Discarding the current final is permitted, but warns. It leaves the entry
with no final and therefore out of the export — a large consequence for one gesture, and
one that is not visible from the entry row afterwards except as a missing thumbnail.

The warning is specific to the final. Discarding a shortlist or candidate image is
ordinary culling and passes silently.

**Recommended:** the warning names the consequence rather than the action — *this entry
will have no final image and will not be exported* — since the user knows they are
discarding something and does not necessarily know it was the final.

### 2.3 Culling: sweep and trash

Two operations, deliberately asymmetric in cost.

**Sweep** is per-entry and moves every candidate image in that entry to discarded.
Shortlist and final are untouched. It is the bulk end of the cull: keep what is worth
keeping, sweep the rest. *Decided.*

Sweep needs no confirmation, because nothing is destroyed — the images move to a
visible, reversible rank. It does need undo, since a mis-aimed sweep on a large entry
is tedious to reverse by hand.

**Empty trash** is project-wide and permanently removes every discarded image across
all entries. It warns with a count and is the only operation that destroys image data.
*Decided.*

The pairing is the point. Sweep is cheap and frequent and safe; empty trash is rare,
explicit, and destructive. The user culls aggressively without deciding anything
permanent, then commits once when the project is settled.

**Recommended:** the empty trash warning reports entries as well as images — *312
images across 4 entries* — since a large number spread evenly reads differently from
the same number concentrated in one entry the user may have swept by mistake.

**Recommended:** discarded images are excluded from an entry's image count badge, and
the project shows a separate trash total alongside the empty-trash control. Once
discarded images have their own rank and their own destructive operation, counting them
as inventory overstates what the user actually has in hand.

### 2.4 An entry with no final

An entry can exist with no final image — it appears in the grid, holds generation
settings, and may already have a caption. It contributes nothing to the export and
nothing to the audit.

**Decided.** Such entries are shown as incomplete in the Dataset Builder and reported
separately by the audit. They are not errors; a project mid-build is mostly these.

---

## 3. The Three Views

### 3.1 Dataset Builder

The primary working view. Vertical list of entry rows; each row is an entry header on
the left and a horizontally scrolling strip of that entry's images on the right.

The entry header carries, indicatively:

- **Position number**, three digits, matching the export filename scheme (§8.3)
- Thumbnail of the final image (placeholder when none)
- Entry name and a caption preview
- Row actions: generate, caption, add images, **sweep**, export
- Badges: image count, and tag coverage as `n/11`

**Recommended:** the position number always reports true project position, never position
within a filtered view. A number that shifts when the user filters would defeat its
purpose, which is to be the same coordinate on screen as in the exported filename.

The `n/11` badge is assigned categories over enabled categories. **Recommended:** show it
whenever the entry is in tagged mode or has any tags assigned, and suppress it otherwise.
Tags can be staged in any mode (§6), so a manual-mode entry showing `7/11` is informative
rather than contradictory — but `0/11` on an entry that will never be tagged reads as
unfinished work rather than a different choice.

**Recommended:** sweep is destructive enough in appearance to warrant separation from
the other row actions, even though it is reversible. Sitting adjacent to *add images*
it is one mis-tap from undoing a generation session.

#### Two filtering axes

The view filters on two independent axes, and keeping them visually distinct matters
more than where either one sits.

**Entry filter** — a text field, retained. Operates on rows: it hides entries.

**Rank toggles** — four controls, one per rank. Operate on images: they hide thumbnails
within every visible entry's strip.

Confusing the two is the main risk. A user who filters to one entry and sees an empty
strip should be able to tell at a glance whether that entry has no images or whether the
ranks holding them are toggled off.

##### Entry filter

**Recommended:** matches entry name and caption text, plus assigned tags on tagged-mode
entries. Tag matching is worth including — with a large library it is the only practical
way to find *the entries where she is sitting* across a fifty-entry project, and the tags
are already stored as structured data rather than needing to be parsed back out of prose.

**Recommended:** alongside the text field, a small set of state filters — *no final*,
*not captioned*, *caption unlocked*, *drifted*. These surface exactly the entries that
need work, which plain text matching cannot do, and *drifted* in particular has no other
route to discovery once a project is large.

##### Rank visibility

**Decided.** Each toggle switches that rank's visibility across every entry strip at
once. Default: final, shortlist, and candidate on; discarded off.

The toggles are a view state, not a project property — they change what is shown, never
what is stored, and should not persist as part of the document. The same applies to the
entry filter.

**Recommended:** image counts on entry headers report inventory and do not respond to
either axis. A badge that changes when the user filters is reporting on the filter
rather than on the entry. The project header is the exception and should show both —
*showing 2 of 4 entries* — since that is the one place the filter state itself is worth
reporting.

Project-level controls: entry filter, rank toggles, thumbnail size, **empty trash**,
**Audit**, **New entry**.

### 3.2 Reference Library

Project-scoped collection of images used as generation input. **Decided.** Populated
three ways: drag-and-drop, file picker import, and copying a generated image out of an
entry.

**Decided.** Project-scoped, not global — reference images are character-specific in
the same way Subject tags are, and a global library would accumulate every reference
ever used.

**Decided.** An entry's reference slots hold *references into the project's library*,
not independent copies. One image serving five entries is stored once.

Two consequences to design for:

- Removing an image from the library affects every entry using it, and also every stored
  image whose provenance records it (§5.3). The warning should count both — *used by 4
  entries, referenced by 31 stored images* — since the second number is usually much larger
  and is invisible from the library view.
- The copy-from-entry path can produce duplicates: promote the same generated image
  twice and the library holds it twice. **Recommended:** deduplicate on content hash at
  add time, silently, since unlike tags there is no canonical-string question and no
  judgement call for the user to make.

**Recommended:** the library shows usage per image — which entries reference it — since
an unused reference image is a candidate for culling and is otherwise invisible.

### 3.3 Tag Library

Management interface for the tagging system — the category set, category properties,
and the global tag vocabulary. Behaviour is specified in `lora-tagging-system-design.md`
§3, §4, §6.

The view is responsible for the warning surfaces that document requires: duplicate
detection at tag creation, and affected-count warnings on category reorder, prefix
edit, disable, and delete. Section 6.3 below extends those warnings to cover locked
entries.

---

## 4. Entry Lifecycle

```
create → configure generation → generate candidates → cull / shortlist
       → promote final → caption → lock → export
```

Stages are not gated. An entry can be captioned before any image exists, locked
without a final (though it will not export), or re-generated after locking. The
lifecycle describes the common path, not a state machine the UI enforces.

---

## 5. Generation

### 5.1 Integration boundary

Image generation is delegated to **DrawThingsQueue**, a Swift package wrapping a Draw
Things gRPC server, and the generation configuration is edited through
**DTConfigEditorKit**. The app owns entry settings, submission, attribution, and
ingestion; it does not own the queue, the transport, or the config schema.

DrawThingsQueue requires macOS 14+ / iOS 17+, which sets the app's deployment floor.
Its observable types are `ObservableObject` with `@Published` properties rather than
`@Observable`, which constrains how the queue is bound into SwiftUI views.

*The following is derived from the package README and should be verified against source
before implementation.*

#### What the package already provides

Enough that the app should not rebuild any of it: FIFO sequential processing with
auto-start, pause and resume, cancellation of pending and in-progress requests,
reordering of pending requests, retry with a configurable ceiling, per-request status
including queue position, live progress with stage and preview image, a Combine event
publisher, an `AsyncStream` of results, and optional on-disk persistence of pending
requests across app restarts via `QueueStorage`.

The app's job is attribution and ingestion. Everything else is already handled.

#### Queue scope and routing

**The queue is app-level; entries are document-level.** One `DrawThingsQueue` instance
holds one connection to one server, and processes a single FIFO queue. Dataset entries
live inside bundle documents (§9), of which several may be open at once.

**Decided.** A single app-level queue. The app maintains a persistent request-to-entry
map keyed by document identity plus entry ID, recorded at enqueue time and stored
alongside the queue's own `QueueStorage` data.

**Decided.** Queueing work for one project and switching to another while it runs is a
supported workflow. Results route by the map, never by what is frontmost.

Three routing cases, in decreasing order of how often they occur:

**Document open.** The common case, and the one that workflow describes. Switching
windows does not close a document, so the target stays open in memory and results are
written into its model directly. Frontmost-ness is irrelevant, and no special handling is
required.

**Document closed with work in flight.** Results are staged into the app container and
ingested when the document is next opened. Writing into a bundle that is not open would
bypass document coordination and, under sandboxing, require retained access to a path the
app no longer holds — staging avoids both.

**Recommended:** the map keys on a **stable project UUID stored in the bundle**, not a
file path. Staged results are then matched when a document opens, whatever it has been
renamed or moved to in the meantime, and the app never needs to locate or reach into a
document it does not currently have open.

**Restored on relaunch.** `QueueStorage` restores pending requests, which may target a
document that is not open and may never be opened again. These follow the staging path.
Staged results whose document cannot be located are surfaced as orphans and are
discardable, rather than silently dropped or silently accumulating.

**Recommended:** closing a document with work in flight prompts — cancel the requests, or
continue and ingest later. Continuing silently is defensible, but it leaves generation
running for something the user may believe they have finished with.

**Recommended:** ingestion marks the document dirty for autosave but is **not** registered
with the undo manager. An arriving image is an external event, not a user edit, and making
it undoable would let the user undo an arrival — which has no coherent meaning and would
desynchronise the entry from the staged data.

**Note on iPadOS.** Several documents open at once is native on macOS and possible but
unusual on iPadOS, where switching documents often means closing one, making the staging
path the common path rather than the exception. This matters less than it might, since
backgrounding already drops the connection and pauses the queue regardless — queue-and-
switch is a macOS strength that iPadOS does not really offer.

The alternative architecture, a queue per open document, avoids the map but multiplies
connections to the same server and gives up global ordering and a single pause control.
Rejected.

#### Attribution

`GenerationRequest.id` is a UUID and `GenerationResult.id` matches it. Attribution is
therefore a lookup, provided the app records the mapping at enqueue time and persists it
alongside the queue's own storage.

`GenerationResult.images` is an array, but batch size is fixed at 1 (§5.2), so each result
carries a single image. **Decided:** it lands as candidate rank in the originating entry.
Attribution is one-to-one throughout.

Requests from several open projects interleave in one FIFO queue and queue position is
global, so a per-project view of pending work is the app's responsibility rather than the
package's.

#### Result ingestion is time-sensitive

`maxCompletedResults` defaults to 50 and caps what the queue retains in memory;
older results are dropped. The app must therefore **consume results as they arrive** —
subscribing to the `results` stream or the `events` publisher and writing images into the
bundle immediately — rather than polling `completedResults` at leisure.

**Recommended:** treat this as the ingestion contract and write it into the build plan
explicitly. A batch-oriented implementation that reads `completedResults` periodically
will silently lose images under load, and the loss will look like a generation failure
rather than a client bug.

#### Failure, retry, and connectivity

The queue auto-pauses on connectivity errors and records the reason in `lastError`.
Failures are exposed per request with the underlying error, and `canRetry` / `retry`
handle re-submission up to `maxRetries` (default 3).

**Recommended:** surface failures on the originating entry rather than only in a global
queue view, since an entry that produced nothing is the thing the user will notice.
A paused-on-connectivity state is a project-wide banner, not a per-entry one.

#### Backgrounding, and a limitation worth accepting

**Decided.** The queue pauses when the app backgrounds and resumes on return to the
foreground.

On iPadOS the gRPC connection will not survive backgrounding, and the queue would
auto-pause on the resulting connectivity error anyway. Pausing deliberately is better than
pausing by failure: it stops new requests being fed into a connection that is about to
drop, so at most one generation is exposed rather than a stream of them.

The unrecoverable case is a request that was *generating* when the connection dropped. The
server is remote and continues working, but the client is no longer there to receive the
result, and the package offers no mechanism to reclaim it. That image is lost and the
request needs re-running. Pausing on background bounds the damage to one image; it cannot
eliminate it.

#### Reference images

**Decided.** An entry's reference images are passed as **moodboard hints**, built with
`HintBuilder.addMoodboardImages(_:weight:)`. They are references into the project's
Reference Library (§3.2), not per-entry copies.

This settles the Reference Library's shape: one interchangeable pool of images with a
single role, rather than a mixed collection where each image's meaning depends on which
slot it occupies. img2img input and the other hint types — pose, depth, Canny, scribble,
line art, colour reference — are not used.

**Decided.** Hint weight is fixed at 1.0 for every reference image and is not exposed.

**Decided.** Four slots, as an app-level product decision rather than an API or Draw Things
limit. Edit models do not make useful use of more than about four reference images, and
additional ones cost processing time while degrading output. Recording the rationale here
because the constraint is invisible in the API and a future reader would otherwise be
tempted to lift it.

### 5.2 Seed ownership

**Decided.** The app owns the seed. It selects a random seed per request, or uses the
entry's fixed seed when one is defined, and **ignores any seed present in the generation
configuration JSON.**

Two consequences that need handling rather than just noting:

**The config editor will show values the app disregards.** A user who edits seed in the
JSON pane and watches it have no effect has found a bug, not a design. **Decided:** seed
and batch size are annotated in DTConfigEditorKit as overridden by the app. Silently
accepting an input that does nothing would be the worst of the available options.

**Decided.** Batch size is fixed at 1. The app never requests more than one image per
generation request.

This removes the per-image seed problem entirely rather than solving it: one request, one
image, one known seed. The seed recorded against an image (§5.3) is exactly the seed the
app supplied, with no derivation to verify and no convention to depend on.

**Decided.** Both seed and batch size are annotated in the configuration editor as
overridden by the app, so a user editing either can see that it will not take effect.

The cost is that generating several candidates enqueues several requests rather than one.
That is arguably the better behaviour anyway — each image gets its own queue position,
progress, and cancellation, so a run of eight can be stopped after three without losing the
three already made.

### 5.3 Per-image provenance

**Decided.** Every ingested image is stored with the generation configuration and the
reference image links that produced it.

Entry generation settings are therefore a **working draft**, not a description of the
entry's images. The user changes prompt, config, and references continuously while
developing a dataset, so an image's settings will routinely differ from the entry's
current ones. The image is the record; the entry is the workbench.

**Decided.** Right-clicking an image offers to recall its settings to the entry,
overwriting the entry's current generation settings.

This is the feature that makes the working-draft model safe. Without it, changing settings
loses the ability to return to what produced a good image, and the user would have to
either keep notes or avoid experimenting.

Four things to design around:

- **Recall is a destructive edit to the entry.** It overwrites prompt, negative prompt,
  configuration, seed, and reference slots. It should be undoable, and it should be clear
  before confirming which of those fields will change.
- **Recall must include the seed** actually used for that image, not the entry's seed
  field, or recalling settings from a randomly-seeded image reproduces nothing. Batch size
  being fixed at 1 (§5.2) makes this unambiguous — the recorded seed is the seed supplied.
- **Reference links can dangle.** An image records links into the Reference Library, and a
  library image can be removed later (§3.2). The recorded link should be retained and shown
  as missing rather than dropped, so the provenance stays honest — *this image used a
  reference that no longer exists* is useful information, and silently showing three
  references where there were four is not.
- **Recall with missing references** is partial by necessity. It should say so rather than
  quietly recalling fewer references than the image used.

**Recommended:** the image inspector shows its recorded settings read-only, so provenance
can be inspected without recalling. Comparing two candidates is a common reason to want the
settings, and recalling is the wrong tool for that.

### 5.4 Entry generation settings

Per the Entry Generation Editor mockup: Name, Prompt, Negative prompt, Seed, up to four
Reference Images, and a generation configuration JSON.

Seed and generation configuration each carry a **Use custom** toggle, defaulting off.
This implies project-level defaults that entries inherit — the same two-level
inheritance the tagging document uses for category order and enabled state.

**Recommended:** make that explicit and consistent. Project holds default prompt
scaffolding, seed policy, and generation config; entries inherit and override
individually. Adopting the tagging doc's snapshot rule, changing a project default
should not retroactively alter entries that have already generated images.

**Decided.** The prompt is a plain text field. It cannot reference the entry's tags.

The caption describes the training image; the prompt describes what to generate. They
diverge the moment the user starts generating variations, and coupling them would make
one an unreliable proxy for the other.

The broader principle, which settles this and future questions of the same shape:
**tags exist solely to render a tagged-mode caption.** They are not a general-purpose
metadata layer, and nothing else in the app consumes them as an input. See §6.2.

---

## 6. Captioning

Each entry has exactly one caption and a **persistent source mode**. *Decided.*

| Mode | Text editable | Tag panel | Ollama wand |
|---|---|---|---|
| Tagged | No | Yes | Disabled |
| Manual | Yes, with spellcheck | Yes | Enabled |
| Ollama | Yes, with spellcheck | Yes | Enabled |

**Decided.** The tag panel is always visible and tags are selectable in every mode. Tags
selected outside tagged mode render nothing; they are staged, waiting.

This supports a specific and useful workflow: generate or write a caption, then use it as
a reference while building the tag selection that will replace it. Hiding the panel would
force the user to memorise their own caption, switch modes, and rebuild it from memory
against a field that has already been overwritten.

**Recommended:** the panel shows a live preview of what the tags would render to, in every
mode. This is what makes staging safe — the user can see the replacement before committing
to it, and switching to tagged mode holds no surprise. Without the preview, staging tags
outside tagged mode is working blind.

Manual and Ollama differ only in provenance — both terminate in an editable text field.
Tracking them separately is still worth it for auditing provenance and for knowing
whether an Ollama re-run would overwrite hand-written work.

### 6.1 Mode switching and replacement

**Decided.**

- Entering **tagged mode** replaces the current caption text with text rendered from the
  entry's tags.
- Pressing the **Ollama wand** replaces the current caption text with the model's output.

Both are destructive to existing text and both need confirmation when the text being
replaced is non-empty and was hand-edited. Losing a hand-written caption to a mode
toggle is a real and irritating failure.

**Recommended:** single-level undo on both, which is cheaper and less intrusive than a
confirmation dialogue on every switch.

The live tag preview (§6) does most of this work already for the tagged-mode switch — the
user can see the replacement text before committing. The Ollama wand has no equivalent,
since its output does not exist until the request returns, which makes confirmation more
important there than on the mode switch.

### 6.2 Tag persistence

**Decided.** Tag assignments persist on an entry regardless of caption mode. Switching
to manual mode and back to tagged restores the previously rendered caption without
re-tagging.

**Decided.** Tags exist solely to render a tagged-mode caption. They are a captioning
mechanism, not a general-purpose metadata layer, and nothing else in the app consumes
them as an input to anything it produces. They have no effect in manual or Ollama mode,
the audit ignores them there (§7), and they cannot feed generation prompts (§5.2).

The line worth stating precisely, since two features already sit near it: other parts of
the app may **read** tags, but nothing may **produce** output from them except the
caption renderer. The audit reads them to report coverage; the entry filter reads them to
locate entries (§3.1). Neither turns them into content. A prompt built from tags would
have crossed the line, which is why §5.2 rules it out.

### 6.3 Locking

**Decided.** Locking an entry freezes the caption as stored text and prevents further
editing. Tag assignments and generation settings are retained in full.

The purpose is insurance. Tags cannot be renamed (tagging doc §6), so deletion is the
only way a canonical string leaves the library — and a library edit made two projects
later would otherwise reach back and silently alter a finished caption. Locking is what
stops that.

**Drift.** A locked caption drifts when its stored text no longer matches what its tags
would render today. Four edits cause this, all already flagged in the tagging document
as dataset-wide rewrites:

- a tag deleted from the library
- a category prefix edited
- categories reordered
- a category disabled

The entry shows a drift indicator. Nothing is rewritten.

**Warnings become precise.** Because locked and unlocked entries respond differently,
the warnings on those four edits should split the count rather than report one total:

> Reordering categories will rewrite 12 captions. 5 locked entries will show drift.

This is a better warning than an affected-image count, because it distinguishes what
changes now from what is merely flagged.

**Unlocking** recomputes the caption from current tags. Where a tag has been deleted its
segment simply disappears. Because the change can be substantial and is not otherwise
visible, unlocking a drifted entry should show a before/after of the caption text rather
than a generic warning. *Recommended.*

Locking a manual or Ollama entry is also meaningful — it protects against accidental
edits and against an Ollama re-run — but such entries can never drift, since no library
state feeds their text.

### 6.4 Ollama integration

Network request to a vision model with the entry's final image and an instruction,
replacing the caption text with the response.

**Decided.** Settings are stored as **named profiles at app level**, with a management
interface. A profile holds the endpoint, the model, and the instruction — the three things
that vary together and that a user will want to switch between rather than retype.

Profiles are the right shape because instructions are the part worth iterating on. A
captioning instruction that works well is a small asset, and the natural workflow is to
keep several — a terse one, a detailed one, one tuned for full-body shots — and try them
against the same image.

**Decided.** An entry requires a final image to be sent for auto-captioning. The wand is
disabled without one.

**Recommended:** the disabled wand explains why rather than simply not responding, since
an entry with candidates but no promoted final looks like it has images.

**Recommended:** a project may nominate a default profile, inheriting from an app-level
default — the same two-level pattern used for category order, enabled state, and
generation settings. A character captioned tersely in one project and verbosely in another
is an ordinary situation, and without this the user re-selects on every entry.

**Note.** The caption is a snapshot of the response, not a live binding. Promoting a
different final later does not re-run captioning or mark the caption stale. This is
consistent with manual mode and with locking, but it does mean a swapped final can leave a
caption describing the previous image, with nothing to indicate it. **Recommended:** if
that proves to be a real problem in use, the cheapest fix is recording which image a
caption was generated from and flagging the mismatch — the same drift-indicator pattern as
§6.3, rather than anything new.

---

### 6.5 Tag panel layout

The mockup shows a flat chip cloud with a filter field. That was a placeholder and does not
survive contact with the category model: eleven categories with mixed select modes, per-
category prefixes, a required Subject, and a global library that grows monotonically.

**Decided.** One row per enabled category, in caption order, each holding the tags selected
for that category.

Four properties follow from the row layout, and they are the reason for it:

**The panel reads as the caption.** Row order is render order, so the panel and the live
preview share a structure. There is no mapping to learn between where a tag was picked and
where it lands in the output.

**Empty rows are the coverage signal.** A category with nothing selected is a visible gap,
which is exactly what §7's partial-coverage rule cares about. The `n/11` badge is the count
of non-empty rows, so the badge and the panel cannot disagree.

**Search rather than browse.** Each row is a token field with type-ahead. Cost is flat as
the library grows, where a chip cloud degrades badly — tagging doc §6 explicitly anticipates
this, noting that search and frequency ordering matter more with a global vocabulary.
**Recommended:** focusing an empty field shows recent and frequently used tags for that
category, so browsing still works while the library is small.

**Selection order is visible and editable.** Multi-select renders in selection order
(tagging doc §5), so tokens sit in pick order and drag to reorder. Without this the rule is
invisible, and a user who wants `hat and sundress` rather than `sundress and hat` has no way
to get it.

#### Details that follow

- **Prefixes** show inline and greyed at the head of the row — `wearing`, `holding` — so the
  row previews its own segment.
- **Single-select rows** hold one token and replace on new selection rather than appending.
  Multi-select rows append.
- **Subject** is pinned first and visually distinct. It is required, and its library is
  project-scoped, so its type-ahead offers only this project's subjects.
- **Disabled categories are absent**, per §3. **Recommended:** if an entry has assignments in
  a category that was later disabled, the panel says so in one line rather than leaving a
  silent discrepancy between stored data and what is shown.
- **Tag creation happens in the field.** Typing a string with no match offers to create it,
  which is where the fuzzy duplicate check fires (tagging doc §6). This puts the guard at the
  exact moment a new string would enter the library.
- **Removal** is an affordance on the token itself.

#### Platform and scrolling

**Decided.** The rows scroll. Eleven at roughly 40px each does not fit alongside an image
preview on an iPad, and the category set can grow beyond eleven.

**Decided.** The header — category count and any panel-level controls — and the live preview
are pinned outside the scroll region. The preview is what the user is checking *while*
tagging, so scrolling it away defeats the purpose, and pinning it preserves the
reads-as-the-caption property once rows start leaving the viewport.

**Recommended:** one scroll region, not nested. If the caption editor pane already scrolls,
the tag rows should be part of that scroll rather than a scrolling box inside a scrolling
pane.

Type-ahead is the primary path on macOS. **Decided:** on iPadOS, tapping a row opens a
picker sheet listing that category's tags.

This is not a touch convenience — it is structural. A focused inline token field on iPad
brings up the software keyboard, which takes roughly half the screen, and the type-ahead
dropdown needs room below the focused row on top of that. Row layout, keyboard, and dropdown
do not coexist in what remains. A sheet owns the full screen, so the list and the keyboard
stop competing with the rows behind them. Both paths write the same thing; neither is a
separate mode.

**Recommended:** focusing a row scrolls it into view above the keyboard inset. Standard
behaviour, but easy to get wrong with a long row list and worth specifying.

**Recommended:** if vertical space still proves tight in use, a preference to hide empty
categories is the next lever — at the cost of the coverage-at-a-glance property above, which
is why it is a preference rather than the default.

Landscape being the design target (§1.1) removes the portrait stacking problem for this
view, but not the scrolling one: eleven rows beside an image well is tight even in landscape
on a smaller iPad.

**Recommended:** the live preview (§6) sits below the rows in all caption modes. In tagged
mode it duplicates the caption field, which is harmless; in manual and Ollama modes it is the
only place staged tags can be seen, which is what makes staging usable.

---

## 7. Auditing

Specified in `lora-tagging-system-design.md` §8. Two scoping rules the tagging document
does not state, because they only arise in the application:

**Decided.** The audit considers **tagged-mode entries that have a final image.**
Manual and Ollama entries are excluded — their tag assignments do not affect their
caption text, so auditing them would report distribution over something that does not
ship. Entries without a final are excluded because they do not export.

**Decided.** The Audit panel states its denominator explicitly. Something to the effect
of *18 of 27 entries — 6 not finalized, 3 not tag-captioned.* Without this, a histogram
over a partially finished project reads as a broken dataset, and the coverage figures in
tagging doc §8 lose their meaning.

This scoping has a consequence worth accepting openly: a project captioned primarily by
Ollama gets little or no distribution analysis. That is a real loss, since distribution
collapse is invisible to hand-inspection and the audit is the app's main advantage over
hand-captioning. The alternative — auditing inert tags on non-tagged entries — was
considered and rejected as reporting on data that does not affect the export.

---

## 8. Export

### 8.1 Scope

**Decided.** Three options, chosen at export time:

- **Finals only** — default. The training set.
- **Finals and shortlist**
- **All images**

Discarded images are never exported in any mode.

**Decided.** Captions export as sidecar `.txt` files whose basename matches their image.
Only finals carry captions, so only finals get sidecars.

The wider modes are an image dump for archival or outside review, not a training set. What
happens to an export downstream is the user's responsibility, and the app does not attempt
to guarantee that any export is valid training input.

### 8.2 Empty sidecars

**Decided.** A final with no caption produces an empty `.txt` rather than no file.

The empty file is the error signal. A zero-byte entry sorts to the top of a size-ordered
listing and is trivially greppable, whereas a missing member of a matched pair is
effectively invisible in a directory of two hundred files. Emitting nothing would make the
problem harder to find, not safer.

### 8.3 Filenames

**Decided.** Filenames are built from a base name entered in the export dialogue, not from
entry names.

```
<name>_<NNN>.png        final for entry NNN
<name>_<NNN>.txt         its caption sidecar
<name>_<NNN>-1.png       first additional image from that entry
<name>_<NNN>-2.png       second, and so on
```

The entry number is zero-padded to three digits. Additional images — shortlist and
candidates, depending on export scope — take an incrementing dash suffix. Only the final
carries a sidecar.

This removes almost all of the sanitization burden. One user-supplied string is cleaned
once, per export, rather than every entry name being sanitized, case-folded, Unicode-
normalized, and collision-checked against every other. Entry numbers are unique by
construction, so no cross-entry collision is possible.

**Recommended:** underscore between name and number, dash before the additional-image
suffix, as above. Using a dash in both positions makes `maya-001-1` ambiguous to parse and
harder to read; distinct separators keep the two levels visually distinct.

**Recommended:** the dialogue validates the base name live and previews the resulting
filename. With one string determining every name in the export, a preview is cheap and
catches an unusable name before it produces two hundred files.

**Recommended:** the base name defaults to the project name, sanitized.

**Decided.** The entry number is the entry's **position in the project**, not its position
in the export. A finals-only export of a project whose third entry has no final yields
`001`, `002`, `004`. The gaps are informative: the number is a coordinate into the project,
so any exported file can be traced back to the entry that produced it.

**Decided.** The position number is displayed on the entry in the Dataset Builder, which is
what makes the scheme pay off — noticing a problem in `maya_047.png` while reviewing an
export leads directly to entry 047 in the project.

Reordering or deleting entries changes positions and therefore changes filenames on the
next export. Accepted: the number is a current coordinate rather than a permanent
identifier, and its job is to point from a file back into the open project — which the
displayed position number does directly. An export is a snapshot, not a record that has to
stay valid against a project that keeps moving.

**Note:** three digits caps at 999 entries. Almost certainly sufficient, but the format
should degrade to four digits rather than colliding if exceeded.

**Recommended:** additional images are ordered deterministically — shortlist before
candidates, and stably within each — so that re-exporting an unchanged project assigns the
same suffixes. Arbitrary ordering makes the output undiffable for no benefit.

### 8.4 Caption source at export

**Recommended.** Locked entries export their stored text. Unlocked tagged-mode entries
render fresh from their current tags at export time.

This follows from tags being the source of truth (tagging doc §6) and from what locking
is for (§6.3). It has one consequence worth stating plainly: a drifted locked entry
exports text that its tags would no longer produce, which is the intended behaviour and
not a defect.

### 8.5 Re-export

**Recommended:** exporting into a directory that already holds an export offers to clear
it first, defaulting to yes.

The base name makes overwriting mostly clean — same name, same project, same files — but
stale output survives two edits. Delete an entry, or promote a final where there was none,
and project-position numbering shifts every file below it, leaving the previous run's
files interleaved with the new ones. Nothing in the output directory marks which run a
given file came from.

### 8.6 Format

**Recommended:** images are copied out of the bundle without re-encoding, with the format
decided once at ingestion rather than at export. Re-encoding a training image at export
is lossy for no benefit.

**Recommended:** sidecars are UTF-8 without BOM, with a trailing newline.

**Decided.** No manifest. An export is images and captions, nothing else.

Reconstructing a project from an export is not a supported operation and not an expected
one — the bundle is the project, and the export is a derived artifact aimed at a trainer.
Provenance lives in the project (§5.3), which is where it is useful.

### 8.7 Reporting

**Recommended:** the export reports what it skipped — *5 of 8 entries exported; 3 have no
final image.* Entries without a final are omitted silently otherwise, and silence is
indistinguishable from success.

Uncaptioned finals need no separate report, since §8.2 already makes them visible in the
output directory itself.

### 8.8 Remembered settings

**Decided.** The base name is remembered per project and pre-fills the export dialogue.
Scope may reasonably be remembered alongside it.

**Decided.** The destination is chosen through a standard OS directory picker on every
export. Nothing about the destination is retained.

This is the simpler and safer arrangement. A remembered destination would require a
security-scoped bookmark to survive relaunch, would need defined behaviour when that
bookmark goes stale, and would make repeat export one click from overwriting a previous
run under the clear-first default in §8.5. Presenting the picker each time removes all
three problems and matches what every other app does.

---

## 9. Persistence

**Decided.** A project is a **bundle document** — a file package containing project
metadata, entries, captions, tag assignments, generation settings, and all image files.
Images live in the bundle, not in a separate store.

**Decided.** The global category set and tag library live in an **app-level store**,
outside any document.

**Decided.** Nothing syncs automatically. A user may place a bundle somewhere both
machines can reach, but coordinating that is outside the app's scope and the app makes
no guarantees about concurrent access.

### 9.1 Schema snapshot

**Decided.** Every bundle carries a snapshot of the schema its assignments depend on,
sufficient to reconstruct or diagnose them against an unfamiliar library.

Per tag: stable ID, canonical string, owning category ID.
Per category: stable ID, name, select mode, prefix, and the thresholds in force.

The snapshot is written on save and is a record of what the project was authored
against — not a live mirror of the app library.

This is worth more than portability. The bundles collectively become a redundant copy of
the app-level library, so a lost or corrupted global store can be rebuilt by opening
projects. It also makes receiving a project from elsewhere a defined operation rather
than an undefined one.

### 9.2 Reconciliation on open

Opening a bundle compares its snapshot against the current app library. Four outcomes:

| Case | Meaning | Behaviour |
|---|---|---|
| ID present, properties match | Normal | Nothing |
| ID absent | Tag or category unknown to this library | Offer import |
| ID present, render-affecting property differs | Prefix or select mode diverged | Report as drift |
| ID present, cosmetic property differs | Category renamed, thresholds retuned | Note quietly |

**Tag divergence is almost always the absent case.** Tags cannot be renamed (tagging doc
§6), so a present tag ID reliably means the correct canonical string. Missing tags are
the whole of the problem.

**Category divergence is the interesting case.** Order and enabled state are project
properties and travel inside the bundle, so they never diverge. Prefix and select mode
are global, and both change what captions render to — a project authored where
`Clothing` carried the prefix `wearing`, opened where it carries `in`, renders
differently with nothing missing and nothing to import.

**Decided.** Render-affecting category divergence is reported using the same drift
vocabulary and the same indicator as §6.3. It is the same failure at a different scale:
stored caption text no longer matches what the current schema would produce. A user who
has learned what drift means on one entry does not need to learn a second concept for
the document-level case.

### 9.3 Import

**Decided.** Import is offered, never automatic, and covers both tags and categories.

Since projects are not shared between people (§1), import serves recovery and
device-to-device movement rather than onboarding foreign work. A bundle carried from the
iPad to the Mac is the user's own project, and a category it depends on is a category
they built — so importing it restores their own schema rather than acquiring someone
else's. There is no pollution risk to guard against.

It stays a prompt rather than an automatic merge only because opening a document should
not silently modify app-level state the user may not be thinking about.

**Decided.** Import runs through the same fuzzy duplicate detection as tag creation.

This is not optional polish, and it survives the narrowing of scope — the hazard simply
changes shape. Tagging doc §6 rests on creation being the only moment a new canonical
string enters the library, which is what makes detection at creation a sufficient guard.
Import is a second such path and breaks that invariant.

The single-user, multi-device case produces the collision just as reliably as sharing
would. Create `hair down` on the iPad, create `hair down` on the Mac, and the two carry
different IDs and identical text. Neither creation could have detected the other. Once
both libraries meet, tagging doc §8 reports one category as an even split between two
tags that are really one — the exact misleading coverage figure that section exists to
surface. Since tags cannot be renamed, the only repair is deletion and reassignment
across every affected entry.

Import should therefore offer, per incoming tag, to map onto an existing near-match
rather than only to add. Mapping rewrites the bundle's assignments to the local tag ID
on save.

**Recommended:** the same detection runs on category import, matched by name and
properties. Two categories named `Held-Items` with different IDs would be the same
failure at schema level, and harder to notice.

### 9.4 Store technology

Two stores, with different requirements — worth separating before choosing anything.

**The bundle document** needs longevity, portability, and a format that survives the app
being rewritten. **Recommended:** `Codable` JSON for metadata plus image files in the
package. A document format coupled to a framework's schema versioning is a liability;
one you control entirely is not.

**The app-level store** needs queryability. It holds the category set, the global tag
library, preferences, Ollama profiles, the known-projects index, and the queue's
request-to-entry map and staging records.

#### What the app-level store is actually asked to do

Small data, modest queries. A few thousand tags at the outside, a dozen categories,
a handful of profiles. The demanding operations are:

- Fuzzy matching a typed string against the tag library (duplicate detection, §6 of the
  tagging doc) — done in memory whatever the store, since neither framework does
  trigram or edit-distance matching
- Cross-project affected counts for tag and category edits
- Uniqueness on canonical string within a category
- Ordered fetches for category order

Nothing here strains either option.

#### SwiftData

*For:* markedly less boilerplate, `@Model` and `@Query` integrate directly with SwiftUI,
type-safe predicates, and a deployment floor of macOS 14 / iOS 17 that
**DrawThingsQueue already imposes** — so it costs nothing here.

*Against:* less mature, with a migration story that is younger and less battle-tested
than Core Data's. `#Predicate` does not cover everything, and complex or aggregate
queries can require fetching into memory. Less visibility when something misbehaves.

**Recommended:** target macOS 15 / iOS 18 rather than the macOS 14 / iOS 17 floor that
DrawThingsQueue imposes, so that `#Unique` is available to enforce one canonical string
per category at the storage layer.

This is a backstop rather than the mechanism. Duplicate detection already queries the
library before creating a tag (tagging doc §6), and an exact-match check is a subset of
that fuzzy check — so application code enforces uniqueness regardless. The constraint earns
its place because **import is a second insertion path** (§9.3), and a storage-level rule
protects against a bug in either one. For a single-user tool the cost of the higher floor
is nil.

#### Core Data

*For:* mature and predictable, with thoroughly proven migration tooling, full control via
`NSFetchRequest`, direct aggregate queries, and long-standing unique constraint support.

*Against:* substantial boilerplate, an Objective-C-shaped API that sits awkwardly in
modern Swift, dated SwiftUI integration, and a concurrency model that is a reliable source
of bugs.

#### Recommendation: SwiftData

The usual reason to prefer Core Data here would be CloudKit, whose constraints —
including the absence of unique constraint support under
`NSPersistentCloudKitContainer` — tend to force the mature option. **Nothing syncs (§9),
so that pressure is absent.** Single user, single process, small data, no sync: the
concurrency and scale arguments for Core Data do not apply.

The migration-maturity risk is the real one, and this design happens to defuse it.
**The app-level store is not the sole source of truth.** Every bundle carries a schema
snapshot (§9.1) sufficient to reconstruct the library, so a migration that goes wrong is
recoverable by opening projects rather than by restoring a backup. That is an unusually
strong safety net, and it is the specific reason to accept SwiftData's immaturity here
when it would be harder to accept elsewhere.

**Recommended:** keep the store behind a repository interface rather than letting
`@Model` types leak into views. It preserves the option to move to Core Data or GRDB if
SwiftData's limits bite, and given the store is small the abstraction is cheap.

**Note for the build plan.** The cross-project count in tagging doc §3 is now only
answerable for projects the app has seen. A count of affected images across all projects
must be scoped to a known-projects index, and must say so — *affects 34 images across 3
known projects* — since a bundle the app has never opened cannot be counted and silently
omitting it would misstate the consequence of a deletion.

---

## 10. Application Settings

**Decided.** Settings are presented as a **tabbed dialogue**, organised by category from
the outset rather than as a single panel to be broken up later. The structure is the point:
new settings get a home in an existing tab, or a new tab, without reorganising what is
already there.

### 10.1 Tabs

An initial set, expected to grow:

| Tab | Holds |
|---|---|
| General | Application-wide behaviour that fits nowhere more specific |
| Draw Things | Server connection; queue behaviour such as retry ceiling |
| Ollama | Captioning profiles (§6.4) |
| Tagging | App-level defaults for category order, enabled state, and coverage thresholds |
| Generation | Default generation configuration, seed policy, ingestion image format |

**Decided.** A single Draw Things server, configured in settings — address, port, and TLS.
Not a profile set.

`DrawThingsQueue` holds one connection anyway, so multiple profiles would only add a
selection mechanism and the questions that follow from it: what happens to queued work when
the active server changes, and what to do when a generation configuration names a model the
newly selected server does not have. Neither is worth answering for a single-user tool
pointed at one machine. If a second server is ever needed, the Ollama profile interface is
the pattern to copy.

**Recommended:** the Tag Library stays a main view rather than becoming a settings tab.
Managing vocabulary is primary work, not configuration, and it needs more room than a
dialogue affords.

### 10.2 App defaults versus project values

Much of this design uses two-level inheritance — category order, enabled state, thresholds,
generation defaults, Ollama profile selection. In every case a project snapshots the app
default at creation and is independent thereafter (§7, tagging doc §7).

**Recommended:** the settings UI states this wherever it applies — *applies to new
projects* — rather than leaving it to be discovered. A user who changes a default, reopens
an existing project, and finds nothing changed has hit the intended behaviour, and the only
thing standing between that and a bug report is a line of text in the dialogue.

---

## 11. Open Questions Summary

| # | Question | Section |
|---|---|---|
| 1 | Whether opting out of iPad multitasking is still available and worth using | 1.1 |

Item 1 is a compatibility check rather than a design decision — the minimum-width approach
works either way, and opting out would only be a convenience on top of it.

The object model, view structure, entry lifecycle, integration boundaries, captioning
behaviour, auditing scope, export format, and persistence architecture are otherwise
settled.

Two things most likely to change once the app is in use, neither blocking: the 70/10
audit thresholds inherited from the tagging document, which are a starting guess rather
than a measured figure, and whether four reference slots (§5.1) is the right practical
ceiling — a few datasets will answer both better than further discussion.

Items marked **Recommended** throughout remain proposals rather than decisions, and are
the natural place to push back during the build plan.
