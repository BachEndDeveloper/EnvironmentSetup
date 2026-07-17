# Microsoft To Do — task conventions

The full task model for `daily-copilot`. This governs every write to To Do.
Read it before creating or updating tasks. SKILL.md holds the list table and
the where-work-lives decision; this file holds the structure.

## Task structure

Every task has:

- **Title** — outcome-shaped, short. Milestones prefix with `[M] WNN: `
  (e.g. `[M] W17: Ship BOSS ADR draft`).
- **Due date** — "the day I commit to closing this out". For a hard external
  deadline, that's the deadline; otherwise it's the day Martin intends to
  finish. `due_date = today` auto-surfaces the task in My Day, so **this is
  the MIT (Most Important Task) mechanism** — no separate flag needed.
- **Start date** — optional. Use to park a task out of active attention until
  a date (future work that shouldn't clutter the current view). Most tasks
  don't need it.
- **Reminder** — set when To Do should ping Martin before the due date. Use
  sparingly, for things that truly need a nudge.
- **Importance** — `high` for this-week priorities, `normal` for backlog,
  `low` for someday. Not conflated with MIT — MIT is `due_date = today`.
- **Categories** — native Outlook categories, flat vocabulary:
  - **Work type:** `deep` / `quick`
  - **Delegation:** `me` / `claude` / `both`

  Apply one of each to every task. They render as pills in To Do and Outlook
  and are filterable. Don't invent new categories without checking with
  Martin first.
- **Recurrence** — set only when a task genuinely repeats on a schedule
  (weekly planning ritual, monthly review, recurring DAC prep). Don't use it
  for pseudo-recurring work ("I should read more" is a habit, not a recurring
  task).
- **Status** — map as follows:
  - `notStarted` → not started
  - `inProgress` → in progress
  - `completed` → done
  - `waitingOnOthers` → waiting on external input (expected to arrive)
  - `deferred` → blocked (can't proceed without something concrete). Name the
    impediment in the body `Blockers:` section.
- **Steps** — the definition-of-done checklist for this one task (max ~20).
  Tick as progress happens. Not for daily-surfacing work — see subtasks below.
- **Body** — the structured template below.
- **My Day** — auto-populated by any task with `due_date = today`, plus
  anything Martin manually flags in the app. Treat My Day as the MIT list. The
  MCP drives MIT via the due date; Martin can flag extras in the app.

## Body template

Use this shape. Sections are optional — omit when empty.

```
Milestone: [M] WNN: <outcome>

Context:
<why this matters, definition of done, background>

Blockers:
<what's blocking, if deferred for that reason>

Links:
- [BOSS-123](https://...)
- [Confluence page](https://...)
- [Email thread](...)

Log:
- YYYY-MM-DD: <checkpoint line>
- YYYY-MM-DD: <checkpoint line>
```

- **Milestone** — only if this task belongs to one. Copy the milestone task's
  exact title.
- **Context** — static intent and DoD. Written once, occasionally edited.
- **Blockers** — short, concrete. What's blocking, not the backstory.
- **Links** — label + URL markdown. Don't dump raw URLs into Context.
- **Log** — append-only dated checkpoints. Add one whenever progress is made,
  something is learned, or a decision is captured. This is the re-entry
  mechanism when returning to a long-horizon task cold.

Work type and delegation live in **categories**, not the body. **When updating
a task, read the body first, modify the relevant section, then write the full
body back. Don't clobber sections that weren't the point of the update.**

## Milestones

Milestones are **tasks inside a stream list**, not their own lists.

- Title: `[M] WNN: <outcome>` (e.g. `[M] W17: Ship BOSS ADR draft`)
- Importance: `high` (this-week priority)
- Due date: end-of-milestone target (typically end of week)
- Body Context: why it matters / what "done" looks like
- Steps: the DoD checklist (concrete observable ticks)
- Child tasks reference the milestone in their body `Milestone:` line and
  auto-surface in My Day on their assigned day

When a milestone is done, complete the task — To Do hides completed tasks, so
no archive step.

## Subtasks for deep work

When a task is larger than ~1 hour or spans multiple days, don't use steps.
Create **separate tasks in the same list**, each with its own due date so each
surfaces in My Day on its day. Reference the parent milestone in their
`Milestone:` line.

The distinction:

- **Step** — "did I remember to do this sub-thing while working on this task"
- **Subtask** — "this needs its own protected time on its own day, and should
  auto-appear in My Day when that day arrives"

## Edge case: external deadline later, MIT earlier

If a task has a real external deadline (e.g. Friday) but Martin wants it as an
MIT today, **don't clobber the Friday date**. Either:

- Create a subtask due today (preferred — fits the deep-work breakdown
  pattern), or
- Martin flags the parent into My Day manually in the app.
