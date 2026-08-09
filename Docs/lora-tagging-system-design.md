# Character LoRA Tagging System — Design Overview

Reference notes for app design. Scope is the tagging system itself: the category
model, the default schema, the data model, and how tags are rendered within the app.
Trainer-specific behaviour and post-export usage are out of scope.

Items are marked **Decided** (settled), **Recommended** (proposed, not yet adopted),
or **Open** (needs testing or a decision).

---

## 1. Purpose

A structured tagging system for captioning character-LoRA datasets. Tags are selected
per-image from typed categories; the app renders them into a caption string.

**Target architecture:** modern diffusion models using an LLM text encoder
(Qwen2.5-VL, Llama, Gemma class) rather than T5 or CLIP.

**Caption style:** hybrid — comma-delimited segments with light natural-language
connectives. Verified in practice against LLM-encoder models.

---

## 2. Governing Principle

Whatever is captioned becomes controllable at inference; whatever is omitted is
absorbed into the trigger token.

The subject tag should absorb invariant identity (face structure, proportions).
Anything the user wants to vary at generation time is worth tagging; anything they're
happy to have fixed can be left out. Neither is wrong — omission is a legitimate choice
with a predictable consequence, not a mistake.

The one thing to avoid is *inconsistent* omission within a category. Tagging an
attribute in some images and not others gives mixed signal: the model neither learns
it as controllable nor cleanly absorbs it into the trigger.

---

## 3. Category Model

The set in §4 is a built-in default. Users can add their own categories, reorder
everything, and edit category properties.

### Category properties

| Property | Type | Notes |
|---|---|---|
| Name | string | Display label. Renaming must not break existing tag assignments — see §6 |
| Select mode | `single` \| `multi` | Single = one value per image; multi = several, joined with `and` (fixed, not editable) |
| Prefix | string, optional | Rendered before the value(s), e.g. `wearing`, `holding`. Empty = bare tag |
| Position | int | Order in the rendered caption — see §7 |
| Enabled | bool | Whether the category is active — see below |
| Coverage thresholds | high / low % | Auditing bounds, declared per category — see §8 |
| Tag library | list | The vocabulary available for selection — see §6 |

All categories are optional per image. A category may be left untagged on any image,
or never used at all.

### Built-ins vs. user categories

**Categories and tags are global.** There is one category set and one tag library,
shared by every project. Project-scoped categories were considered and dropped as
unnecessary complexity.

**Built-in categories cannot be deleted, only disabled.** They can be renamed,
reordered, and have their prefix edited, but the set is permanent — it's the shared
vocabulary the app is designed around, and removing pieces of it would make projects
structurally incompatible with each other.

User-created categories can be added and deleted freely.

### Enabled state

A disabled category renders nothing and is absent from the tagging UI, but its stored
assignments survive being re-enabled. This is what makes deletion unnecessary: eleven
categories is a lot of UI for someone who only uses five, and disabling gives that
relief without destroying data or fragmenting the schema.

Enabled state follows the same two-level model as ordering (§7):

- **App level** — a global default, set in preferences
- **Project level** — inherits the app default, overridable per project

The per-project override is what makes a global category set workable. A user can keep
Camera Angle available app-wide but switch it off for a dataset where it isn't worth
tagging, without touching any other project.

**Disabling a category warns** when it has assignments in the current project, since it
silently drops a segment from every caption there. Assignments are preserved, so the
warning describes a change in output rather than data loss.

**A newly added user category defaults to enabled** for existing projects. It appears
untagged everywhere and renders nothing until used, so it costs an empty slot in the UI
rather than changing any existing caption.

### Subject is special

Subject is not an ordinary category. It is **required, single-select, position zero,
prefix-less, and non-deletable.** It carries the trigger token, and its position is a
property of how the caption works rather than a user preference.

### Edits that rewrite the dataset

Reordering categories or editing a prefix on an in-progress project **must warn** — both
rewrite every caption in the dataset at once, and neither is visible from a single
image's view. The warning should carry a count of affected images, as deletion does.

### Deletion

Deleting a user category orphans every tag assigned to it, across every project — the
category set is global, so deletion is app-wide. This needs a defined behaviour rather
than a silent cascade. **Recommended:** warn with a count of affected images across all
projects, and offer to reassign the category's tags to another category rather than only
offering to discard them.

Disabling is the non-destructive alternative and should be offered in the same dialogue.

---

## 4. Default Category Set

The built-in template, in default order:

```
Subject, Framing, Camera Angle, Pose, Gaze, Expression, Lighting,
Hairstyle, Clothing, Held-Items, Background-Location
```

Example render:

```
Maya, medium shot, three-quarter view, standing, looking at viewer, smiling,
warm overhead lighting, hair down, wearing yellow sundress and white hat,
holding black purse, hotel lobby background
```

| Category | Select | Prefix | Notes |
|---|---|---|---|
| Subject | single | — | Trigger token. Required, position zero, project-scoped library |
| Framing | single | — | How much of the subject is in frame — close-up, medium, full |
| Camera Angle | single | — | From above, low angle, profile, three-quarter view |
| Pose | single | — | Standing, sitting, arms crossed, leaning |
| Gaze | single | — | Looking at viewer / looking away. Independent of Expression |
| Expression | single | — | Bare tag; the literal word "expression" adds nothing |
| Lighting | single | — | |
| Hairstyle | single | — | See §4.1 |
| Clothing | multi | `wearing` | Worn items — see §4.2 |
| Held-Items | multi | `holding` | Held items — see §4.2 |
| Background-Location | single | — | |

The value of the more granular camera categories is unproven; a user may reasonably
never tag Framing or Camera Angle at all. The schema defines format and order *if*
they are used.

Framing, Camera Angle, Pose, and Gaze were originally one combined category. They are
independent axes, and separating them is what allows combinations like a low-angle
close-up, or a smile with averted gaze.

### 4.1 Hairstyle

Tag it if style should be promptable. Leave it out and it bakes into the trigger —
fine for a character whose hair never changes, limiting for one whose does.

Colour is handled separately from style. Common pattern: bake colour (never tag
`brown hair`), keep style variable (`ponytail`, `hair down`).

**Recommended:** expose colour-baked-vs-variable as a per-character setting rather
than a global rule — the right answer differs per dataset.

### 4.2 Clothing and Held-Items

Not slot-based. Garments are ordinary multi-select tags; a tag like `yellow sundress`
stays atomic, with colour carried in the tag rather than modelled as a separate
attribute.

The boundary is **worn vs. held**. Anything on the body — garments, headwear, footwear,
jewelry — belongs to the Clothing library. Held-Items covers what the subject is
carrying. The category was renamed from "Accessories" because that name invited jewelry
and other worn items into the wrong library.

---

## 5. Rendering Rules

Tag text renders **verbatim**. Phrasing is a property of the tag, not the renderer.
Whether the library contains `in a hotel lobby` or `hotel lobby background` is the
user's decision, and the app does not append, rewrite, or normalise it.

A category with a prefix renders it before the value(s):

```
wearing yellow sundress and white hat and gold earrings
holding black purse and paper coffee cup
```

Multi-select values join with `and` — fixed, not editable per category — in **selection
order**, the order the user picked them, preserved as-is rather than sorted. The same
outfit may render as `sundress and hat` in one image and `hat and sundress` in another;
acceptable, since it reflects what the user actually did and the encoder is insensitive
to it.

Categories with no tag selected are omitted from the render along with their comma,
rather than emitting an empty segment. This includes the prefix — an empty Held-Items
category emits nothing, not a stray `holding`.

---

## 6. Data Model

**Tags are the source of truth; the caption string is a render target.**

Store atomic tags with category metadata and render caption text on demand. The same
tag set then drives the UI, filtering, auditing, and any output format, rather than
the app storing prose it has to re-parse.

Because categories are user-editable, **tags must reference categories by stable ID,
not by name.** Renaming a category, changing its prefix, or reordering it should never
touch stored assignments.

### Tag library scope

**The tag library is global.** One vocabulary, shared across every project. Building up
`warm overhead lighting` once makes it available everywhere, and a new project starts
with the full library rather than an empty one.

**Subject is the single exception: its tags are project-scoped.** A character name is
meaningful to one dataset in a way that `medium shot` is not, and a global library
accumulating every trigger token ever used would be noise in every new project.

Two consequences worth designing around:

- Editing or deleting a library tag affects every project using it, so tag edits need
  the same warning treatment as category edits.
- The library grows monotonically, so search, aliasing, and some notion of
  recently-or-frequently-used ordering matter more than they would with per-project
  vocabularies.

### Vocabulary consistency

Each tag has one **canonical string** — the text that renders — and the same tag should
never exist twice under different wording. On LLM encoders this matters less for the
model (synonyms are handled gracefully) and more for **auditing**: two tags meaning
`looking at viewer` split a category that is really at 100% coverage into a misleading
60/40, corrupting the very signal §8 exists to provide.

The risk grows with the library. Thirty projects in, nobody recalls exact wording, and
a tag that can't be found gets recreated.

**Duplicate detection at creation** is the mechanism: fuzzy-match a newly typed tag
against the existing library and prompt with near-matches before creating it. It
requires no ongoing upkeep and catches the failure at the moment it would occur.

**Tags cannot be renamed.** The canonical string is fixed at creation, which makes
creation the only moment a new string enters the library and duplicate detection the
only guard needed. Renaming was considered and dropped: it opens a second path to
collisions, and the merge-versus-block question it raises costs more complexity than the
feature returns. Correcting a tag means deleting it and creating the replacement.

An alias layer — alternate spellings per tag that surface it in search but never render
— was considered and rejected for the same reason.

---

## 7. Ordering

**Decided: fixed category ordering, no jitter, no per-image variation.**

Repeated practical results show no positional artifacts with this format. A consistent
frame arguably helps — each slot reliably means the same kind of thing in every caption.

Order is a project-level property, never per-image.

### Configurable order

Category order is a setting with two levels:

- **App level** — a global default, editable in preferences
- **Project level** — inherits the app default, overridable per project

A project's order is captured at project creation and thereafter independent; changing
the app default does not retroactively reorder existing projects. Snapshotting on
creation is safer than live inheritance, since silently reordering the captions of an
in-progress dataset is worse than a stale default.

The same two-level model applies to enabled state (§3) — the app-level defaults form
the starting point that new projects inherit.

Subject stays at position zero and is not reorderable.

---

## 8. Dataset Auditing — *Recommended, high priority*

The main advantage a tagging app has over hand-captioning.

Clean captions and consistent ordering do not protect against **distribution collapse**.
A category that is 90% one value bakes in regardless of how well it is tagged. If 45 of
50 images are `smiling`, the tag carries no information and the smile fuses to the
character. If everything is a medium shot, close-ups cannot be prompted no matter what.

**Feature:** live per-category coverage histogram, flagging tags above ~70% or below
~10% of the dataset.

**Partial coverage** is the other signal. An untagged category is not an error — the
user may have deliberately skipped Camera Angle entirely. What matters is a category
tagged in *some* images and not others, which is the inconsistent-omission case from
§2. A category at 0% or 100% is a decision; one at 60% usually isn't.

Multi-select categories need their own treatment: coverage should count the *presence
of any tag* in the category separately from the frequency of individual values, since
a garment appearing in every image is a different problem from the Clothing category
being unevenly filled.

Thresholds are **per-category and user-adjustable**, with ~70% / ~10% as the starting
values rather than fixed rules. Held-Items is legitimately sparse — most images have
nothing held — and user-defined categories will have their own expected fill rates. A
single global rule would flag them constantly.

The defaults are declared **per category in the category definition**, not as one shared
constant that every category points at. Every built-in currently ships the same 70/10
pair, but each holds its own copy, so a built-in's default can be retuned independently
without touching the others or introducing an override mechanism later. User-created
categories inherit 70/10 at creation and are editable from there like any other.

---

## 9. Open Questions

None outstanding. The schema, rendering rules, scope model, and editing behaviour are
settled.

The two things most likely to change once the app is in use: the 70/10 threshold
defaults, which are a starting guess rather than a measured figure, and whether the four
camera categories (Framing, Camera Angle, Pose, Gaze) earn their place — their value for
training is unproven, and a few datasets will answer it better than further discussion.
