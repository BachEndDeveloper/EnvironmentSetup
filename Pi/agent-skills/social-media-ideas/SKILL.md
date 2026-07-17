---
name: social-media-ideas
description: >-
  Generate and export professional social-media / LinkedIn post ideas for the
  user's personal brand as a software/platform architecture leader (AI,
  platform engineering, event-driven architecture, governance, ERP
  transformation, technical leadership). Each idea is exported as its own
  markdown file inside a per-theme folder so ideas from every chat accumulate
  in one place — written directly into the user's synced GitHub repo when it is
  connected, or bundled into a repo-ready zip when it is not. Use this skill
  whenever the user wants social media post ideas, LinkedIn content, post
  seeds, a content backlog, a topic bank, content for professional visibility,
  or "things I could post about" — even if they don't name the file format or
  say "skill". Also use it when they want to add a few more ideas to their
  existing content store.
---

# Social Media Idea Bank

Turn what you know about the user — their role, expertise, current projects,
and recent work in this conversation — into a batch of high-quality
social-media post ideas, then export each idea as its own markdown file in a
repo-ready structure.

## Positioning (the user's angle)

Posts are for **professional self-promotion and visibility** — on LinkedIn and
inside their company. The voice is a credible, opinionated architecture/AI/
platform leader. When generating ideas, hold these principles:

- **One idea per post.** A post that says three things says none. Keep each
  seed narrow enough to become a single post.
- **Contrarian beats explainer for reputation.** The ideas that build a name
  are the ones that say something most people get *wrong*, not the ones that
  explain something correctly. Bias the batch toward defensible, contrarian
  takes; include explainers too, but flag which is which.
- **Lead with external, attributable sources.** Research and named cases (e.g.
  DORA, Adidas, Booking.com, CodeScene, Gartner, McKinsey, Team Topologies,
  Zalando/Spotify/Netflix patterns) depersonalise the claim and travel further
  than internal assertions. Prefer them as the backbone of the angle.
- **Generalise confidential internal figures.** Anything internal — specific
  costs, headcounts, internal metrics, named colleagues, unannounced roles or
  proposals — must NOT appear verbatim. Convert to a pattern ("a programme that
  hit 90%+ of its Kafka ACL ceiling") and note this in the post's publishing
  note. This protects the user; treat it as non-negotiable.
- **Pair claim with an artifact where possible.** Suggest a simple visual
  (a 2×2, a before/after, a diagram) in the angle when one would carry the post.

Draw on everything you already know about the user (their role, projects,
expertise, and the work in the current conversation). Only ask the user a
question if something genuinely blocks you — otherwise infer and proceed.

## Workflow

### 1. Decide the scope
If the user named a theme or a specific subject, generate ideas for that. If
they asked broadly ("ideas I could post about"), produce a spread across
several themes. Default batch size is generous (aim for breadth) unless they
ask for a focused few.

### 2. Pick a `base_folder` name (stable across chats)
This is the repo subfolder all ideas live under. **Keep it the same every time**
so files from different chats cluster together when synced. Default:
`content-ideas`. Only change it if the user asks.

### 3. Map every idea to a canonical theme slug
Theme slugs become folder names. Reuse these canonical slugs so ideas cluster
correctly across chats — do not invent near-duplicate variants (e.g. never use
`ai-x-architecture` when `ai-architecture` already exists):

| Slug | Covers |
|---|---|
| `ai-architecture` | AI × architecture: AI as amplifier, agentic coding, code health for AI, AI FinOps, AI readiness |
| `event-driven-architecture` | Kafka, EDA, integration patterns, domain gateways, data contracts as interfaces |
| `governance` | Architecture governance, ADRs, Tech Radar, paved roads, deviation registers, leading standards |
| `transformation` | First 90 days, ERP turnaround, strangler fig, change management, tech-debt-as-business-language |
| `data-ddd-platform` | Data architecture, operational vs analytical, DDD, data products, platform engineering |
| `role-career-meta` | The architect role, influence without authority, decision frameworks, career, meta-reflection |

If a genuinely new area comes up, create a new lowercase-hyphenated slug and
reuse it consistently thereafter.

### 4. Build the ideas JSON
Assemble all ideas into a single JSON object matching this schema, then write
it to a temp file (e.g. `/tmp/ideas.json`):

```json
{
  "base_folder": "content-ideas",
  "ideas": [
    {
      "title": "AI is an amplifier, not a fix",
      "theme": "ai-architecture",
      "description": "One-line summary of the post's core point.",
      "angle": "The raw material to build the story: the claim, the source, the hook, the implication.",
      "hook": "Optional strong opening line.",
      "sources": ["DORA 2025"],
      "publishing_note": "Optional — e.g. generalise any internal figures.",
      "status": "idea"
    }
  ]
}
```

`title`, `theme`, `description`, `angle` are required. The others are optional.
`status` defaults to `idea` and follows the lifecycle `idea | in-progress |
completed`.

### 5. Run the export script
Write the files into the user's repo. Two cases:

**A — the repo folder is connected (preferred).** Point `--out` straight at the
connected repo so the files land in `content-ideas/<theme>/` and are ready to
commit:

```bash
python /path/to/social-media-ideas/scripts/export_ideas.py /tmp/ideas.json --out /path/to/connected/repo
```

**B — no folder access (fallback).** Write to the outputs dir; the script also
zips the result for manual download:

```bash
python /path/to/social-media-ideas/scripts/export_ideas.py /tmp/ideas.json --out /mnt/user-data/outputs
```

Either way the script writes one markdown file per idea into
`content-ideas/<theme>/`, gives each file a collision-proof name
(`<title-slug>-<random>.md`), prints a summary, and produces a zip when run
against the outputs dir.

### 6. Present and explain the sync
- **Connected repo:** present the new files, then commit and push:
  ```bash
  git add . && git commit -m "Add social post ideas" && git push
  ```
  The new files merge into existing theme folders; because every filename is
  unique, nothing is ever overwritten — the store is append-only.
- **Zip fallback:** present the zip with `present_files`, and tell the user to
  unzip it into the **root of their private GitHub repo** (the files merge into
  existing theme folders without overwriting anything), then commit and push.

## Why this design

One file per idea (not one big file per theme) is deliberate: it makes the
GitHub store **append-only**. A new chat only ever adds files, so there are no
merge conflicts and no risk of clobbering ideas captured elsewhere. The YAML
front-matter (`status`, `theme`, `sources`, `created`) lets the user track and
filter ideas over time — flip `status` to `in-progress` or `completed` as the
idea moves from seed to published.

## Output file shape (for reference)

```markdown
---
title: "AI is an amplifier, not a fix"
theme: ai-architecture
status: idea            # idea | in-progress | completed
created: 2026-06-10
id: ai-is-an-amplifier-not-a-fix-a1b2c3
sources: ["DORA 2025"]
published:              # date set when status -> completed (optional)
---

# AI is an amplifier, not a fix

**Description:** The contrarian core idea, in one line.

**Angle:** The story material — claim, evidence, hook, implication.

**Hook / opening line:** Optional.

**Publishing note:** Optional — e.g. generalise internal figures.
```
