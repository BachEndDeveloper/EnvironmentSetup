# Prepare my day

The morning brief. Produce a single response with the five sections below, in
order. All M365 reads (calendar, email, Teams, transcripts) go through the
`m365-martin` skill; all task reads/writes go through the `m365-personal-productivity` MCP
per `references/todo-conventions.md`.

## Before responding — read state

Use targeted `list_tasks` calls against the five work-stream lists plus
`Flagged Emails`. Don't pull everything — query what each section needs:

- Overdue + due today: `list_tasks` on each list filtered to due-before
  end-of-today, status open
- In-progress / waiting: filter by status (`inProgress`, `waitingOnOthers`,
  `deferred`)
- Milestones: `list_tasks` filtered to titles containing `[M]`

Then layer in calendar, email, Teams, Jira, and Confluence signal.

## 1. Unfinished from yesterday

Pull from To Do: anything with status `inProgress`, `waitingOnOthers`, or
`deferred`, plus any overdue items. Flag slips >2 days with `[slipping]`. If a
slip is >5 days, ask whether to drop, reschedule, or mark `deferred` with a
real blocker.

## 2. Today's to-do

Grouped by source. Each item is one line with a delegation tag.

- **My Day (MIT)** — everything with `due_date = today`, plus anything Martin
  has manually flagged into My Day. This is today's close-out list.
- **Overdue** — tasks across stream lists with `due_date` before today and
  status not `completed`.
- **Jira / Confluence (BOSS, DAC)** — tickets and comments needing input.
- **Email** — messages to answer, including items in `Flagged Emails`. For
  each, include a suggested draft reply in a collapsible `<details>` block.
- **Teams** — messages needing attention.
- **Meetings to schedule** — meetings to set up based on signals from threads,
  Jira, or commitments Martin has made.
- **Pending decisions** — state the decision in one line, what blocks it in
  one line.

New action items from these sources: add to To Do in the right stream list,
with categories (`deep`/`quick` + `me`/`claude`/`both`) and the body template
filled per `references/todo-conventions.md`. **Batch-confirm before adding
five or more.** For items with hard deadlines or protected-time needs, also
propose a Calendar event.

## 3. Meeting prep

For each meeting today:

- Use the agenda if present.
- If no agenda: pull from similar past meetings, recent email threads with the
  attendees, Teams transcriptions of related meetings, and related Jira or
  Confluence work (transcripts via `m365-martin`).
- Provide: purpose, attendees, what they likely want from Martin, what Martin
  likely wants from them, any open items.
- Flag if Martin is likely expected to lead or present.

## 4. Tasks needing breakdown

Identify upcoming tasks or meetings needing sustained work — more than roughly
an hour of focused effort, or multi-step. For each, propose a breakdown:

- Parent task: category `deep`, due date = deadline, importance `high`.
- Steps inside the parent for the DoD checklist.
- Separate child tasks (same list) for multi-day pieces, each with its own due
  date and category `deep`, each referencing the parent in the `Milestone:` or
  Context line.
- Parent body: Context section with intent and DoD; an initial Log entry
  capturing current state and what's needed to resume cold.
- If the parent has a hard external deadline, propose a Calendar event.

**Confirm with Martin before writing the breakdown into To Do.**

## 5. Suggested actions

Things no one is asking for but that would benefit Martin, BOSS, DAC,
BESTSELLER, or the trajectory toward Chief Architect. **Maximum five.** Each is
one line of suggestion plus one line of rationale. What fits:

- An ADR to push forward
- A colleague worth reconnecting with on adjacent territory
- A topic worth raising in the DAC
- A small investment that compounds toward the Chief Architect role
- A piece of AI strategy work (Track 0/A/B or Developer Acceleration) that is
  drifting

If there are fewer than five genuinely useful suggestions, give fewer. **Do
not pad.**
