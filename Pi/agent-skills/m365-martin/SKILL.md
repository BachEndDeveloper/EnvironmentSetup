---
name: m365-martin
description: "Reference for working with Martin's Microsoft 365 at BESTSELLER — reading Outlook calendar, Outlook email, Teams chat, SharePoint, and meeting transcripts, AND creating Outlook email drafts and calendar events/meetings. Use this skill whenever a request requires reading Martin's calendar, mail, Teams threads, SharePoint files, or meeting transcripts, OR drafting/composing an email, replying or forwarding, scheduling or creating a meeting or calendar event, or sending a Teams meeting invite. Trigger on mentions of calendar, mail, email, draft, compose, reply, forward, send, Teams, SharePoint, meetings, schedule, book, invite, availability, transcripts, or any digest- or brief-driven lookup or any create/draft/schedule action on these sources, even when M365 is not named explicitly."
---
# Microsoft 365 — Martin's working reference
Microsoft 365 holds Martin's calendar, mail, Teams threads and meeting
transcripts. This skill captures the parameter patterns, gotchas, and
fallbacks that keep lookups reliable.
Output is in English. Skill instructions are also in English so they
can be shared across BESTSELLER's international organisation. When this
skill is invoked by another skill (e.g. `daily-copilot`), that skill's
output-language rule governs.
---
## Tools at a glance
| Tool | Purpose | Key constraint |
|---|---|---|
| `outlook_calendar_search` | Find calendar events | `query` optional; max 25 results |
| `outlook_email_search` | Find emails | `query` optional; max 25 results |
| `chat_message_search` | Find Teams chat messages | `query` **required**; sometimes unstable |
| `sharepoint_search` | Find SharePoint files/pages | `query` required; strict ISO 8601 dates |
| `sharepoint_folder_search` | Find SharePoint folders by name | Name partial match |
| `read_resource` | Read full content by URI | URI format must match resource type |
All search tools return **metadata only**. Use `read_resource` with the
returned URI to get full content (email body, event details, file
contents, etc.).
These six tools are **read-only**. Creating drafts and calendar events
goes through a separate write path — see "Creating drafts and events"
below.
---
## Universal patterns
### Dates and times
- Search tools accept **natural language** ("yesterday", "last week",
  "next Monday") for `afterDateTime` / `beforeDateTime` — except
  `sharepoint_search` and `find_meeting_availability`, which require
  strict ISO 8601 (`YYYY-MM-DDTHH:mm:ssZ`)
- Calendar event times are returned in **UTC**. Convert to **CEST
  (UTC+2)** when displaying to Martin (mid-Jutland / Denmark)
- `find_meeting_availability` takes UTC and returns UTC — always
  translate before showing
### Pagination
- All search tools return max 25 results (50 for SharePoint)
- When more exist, the final response item contains `nextOffset` (or
  `nextCursor` for some email searches)
- Pass `nextOffset` back as `offset` to fetch the next page
- Free-text email search in a folder or shared mailbox pages by
  `cursor`, not `offset`
### Result → content
1. Search returns URIs in result metadata
2. Pass each URI to `read_resource` for full content
3. Never assume full content from search snippets — read what matters
---
## Outlook calendar
### Common patterns
**Today's meetings**
```
outlook_calendar_search(afterDateTime: "today", beforeDateTime: "tomorrow", limit: 25)
```
**This week's meetings**
```
outlook_calendar_search(afterDateTime: "monday", beforeDateTime: "next monday", limit: 25)
```
**Meetings with a specific person**
```
outlook_calendar_search(attendee: "name@bestseller.com", afterDateTime: "last week")
```
### Gotchas
- `query` is **optional** — omit it to return all events in the date
  range. Earlier guidance to pass `query: "*"` is unnecessary
- Default date range is 1 year past → 1 year future if no dates passed.
  Always pass `afterDateTime` for digest use to avoid noise
- Default `limit` is 10. Pass `limit: 25` for digest sweeps to avoid
  truncation
- Use `calendarOwnerEmail` if Martin asks about a delegated calendar
---
## Outlook email
### Common patterns
**Unread / recent inbox**
```
outlook_email_search(afterDateTime: "yesterday", folderName: "Inbox", limit: 25)
```
**From a specific person**
```
outlook_email_search(sender: "henrik", afterDateTime: "last week")
```
**Free-text search**
```
outlook_email_search(query: "datadog contract", afterDateTime: "last month")
```
### Gotchas
- Use `sender` / `recipient` to filter by person — **not** `folderName`
  with a name. `folderName` is for actual mail folders ("Inbox",
  "Sent Items", etc.)
- `recipient` is NOT compatible with `folderName`, `mailboxOwnerEmail`,
  or `order`
- `order` is NOT compatible with free-text `query` — use sender / date
  filters when you need date ordering
- Setting `order` without `folderName` defaults to Inbox only — pass
  `folderName: "Sent Items"` if Martin wants ordered results from
  another folder
---
## Creating drafts and events — the write path
The search/read tools above are **read-only**. The connected M365 MCP
does not expose mail- or calendar-creation tools. Writing (drafting
mail, creating events) goes through Martin's **local M365 MCP server**,
which wraps the Microsoft Graph endpoints documented here. If no write
tool is available in the current session, say so plainly rather than
pretending the action succeeded — do not fabricate a sent confirmation.
When a write tool *is* present, its inputs map onto the Graph request
bodies below; use these shapes to fill its parameters.
### Confirm before anything leaves the mailbox
Sending mail and creating invites that notify others are
**confirm-first** actions. The default workflow:
1. Build the draft / event details
2. Show them to Martin (recipients, subject, body, time, attendees)
3. Send or create the invite **only after he confirms**
Drafting and staging never need confirmation — only the send / invite
step does. This matches Martin's review-first habit.

For **meeting invites the server enforces this** rather than relying on
habit: there is no one-shot "create event with attendees" call. Inviting
is a two-step `prepare_meeting_invite` → `send_meeting_invite` flow where
step 1 returns a preview + one-time token and step 2 sends only when
handed that token — so Martin always sees the invite before it goes out
(see "Calendar events / meetings" below).
### Email — endpoints
| Action | Graph call |
|---|---|
| Create a draft | `POST /me/messages` (JSON `message` object) → `201` + `id` |
| Send an existing draft | `POST /me/messages/{id}/send` (no body) |
| One-shot compose + send | `POST /me/sendMail` (`{message:{…}, saveToSentItems:true}`) |
| Reply draft | `POST /me/messages/{id}/createReply` then PATCH + `/send` |
| Reply-all draft | `POST /me/messages/{id}/createReplyAll` |
| Forward draft | `POST /me/messages/{id}/createForward` |
| Add attachment | `POST /me/messages/{id}/attachments` |
- **Draft vs one-shot**: prefer the two-step draft → review → `/send`
  path so Martin sees it first. Reserve `/sendMail` for cases where he
  explicitly wants it sent without a review step
- Minimal draft body:
```json
{
  "subject": "…",
  "body": { "contentType": "HTML", "content": "…" },
  "toRecipients": [ { "emailAddress": { "address": "name@bestseller.com" } } ],
  "ccRecipients": []
}
```
- Reply/forward drafts come back **pre-populated** (quoted thread,
  recipients). PATCH the returned draft `id` to add Martin's text, then
  `/send` — don't rebuild the thread by hand
- Attachments under ~3 MB go inline as a `fileAttachment`; larger files
  need an upload session (`POST …/attachments/createUploadSession`)
- Shared / delegated mailbox: swap `/me` → `/users/{upn}`
- Permissions: `Mail.ReadWrite` to draft, `Mail.Send` to send
### Calendar events / meetings — the tools
Two distinct paths on the local M365 MCP server, depending on whether
anyone else gets notified.

**A. Martin's own calendar, no attendees → `create_event`**
A personal time block, focus time, reminder, or a meeting he'll invite
people to later. `create_event` puts it on his calendar and notifies
nobody. It **rejects attendees** — passing any is an error by design.
- Params: `subject`, `start`, `end` (local wall-clock ISO — see time
  zone note below), `time_zone` (default host zone), `location`, `body`,
  `body_type`, `is_online_meeting` (Teams link), `reminder_minutes`,
  `is_all_day`
- `update_event` patches an existing event's fields by `event_id`. It
  **also rejects attendees** — it cannot add people.
- `delete_event` removes an event by `event_id` (sends cancellations if
  it had attendees).

**B. Inviting other people → `prepare_meeting_invite` then `send_meeting_invite`**
Outlook events have no draft state, so attaching attendees notifies them
the instant the event is created. Inviting is therefore a deliberate,
confirm-first two-step — and the **only** way to invite anyone (path A
refuses attendees):
1. `prepare_meeting_invite` with the meeting details and `attendees`
   (≥1). It does **not** touch the calendar — it returns a `preview`
   string and a one-time `confirmation_token` (valid 10 minutes).
   - Omit `event_id` to create a **new** meeting — then `subject`,
     `start`, `end` are required.
   - Pass `event_id` to invite people to an event already staged via
     path A.
2. Show Martin the returned `preview` (subject, time, attendees, Teams
   yes/no) and get his explicit OK.
3. Only then call `send_meeting_invite` with that `confirmation_token`.
   This is what actually sends the invitations.
- **Teams by default**: an invite defaults to a Teams online meeting
  unless you pass `is_online_meeting: false`.
- `attendees[].type` is `required` | `optional` | `resource` (default
  `required`).
- One-time token: if it expired (>10 min) or was already spent,
  `send_meeting_invite` errors — just call `prepare_meeting_invite`
  again for a fresh one.

**Gating — these invite tools may be absent.** Sending is opt-in on the
server via `ALLOW_SEND`. When it's off (the current default),
`prepare_meeting_invite` and `send_meeting_invite` are **not registered
at all**, and `create_event` still refuses attendees — so inviting is
impossible in that session. If the invite tools aren't present, tell
Martin invites are disabled (the server needs `ALLOW_SEND=true`) rather
than implying an invite went out. Path A (`create_event`, no attendees)
works regardless.

- These tools target Martin's **own** calendar. Delegated/shared
  calendar writes aren't wrapped — note that if he asks.
- Find a slot first with `find_meeting_availability` (UTC in/out), then
  pass the chosen **local** time to the tool.
- Permissions: `Calendars.ReadWrite`.
### Time zone when writing — opposite of reading
The UTC→CEST rules below are for **displaying** times read back from
M365. When **creating** an event, do the reverse:
- Pass **local wall-clock** time in `start` / `end` (e.g. `09:00`, not
  the UTC `07:00`) and set `time_zone` to **`"Europe/Copenhagen"`** (or
  the Windows name `"Romance Standard Time"`)
- Do **not** pre-convert to UTC — Graph resolves DST from the zone
- `time_zone` defaults to the server host's zone, so it can be omitted
  when that's Martin's zone. The tool sets the `Prefer` timezone header
  itself, so the event echoes its times back in that zone
---
## Teams chat — the unstable one
### Common patterns
**Recent messages from a person**
```
chat_message_search(query: "name", sender: "name@bestseller.com", afterDateTime: "last week")
```
**Topic search**
```
chat_message_search(query: "datadog renewal", afterDateTime: "last week")
```
### Gotchas
- `query` is **required** and must be non-empty — unlike calendar/email,
  there is no "all messages" mode
- KQL syntax supported in `query`: `from:`, `sent:`, `hasAttachment:`
- **Signal is often unreliable**. When chat search misses messages
  Martin knows exist, fall back to Outlook: Teams sends email
  notifications for many actions, and `outlook_email_search` with
  `sender: "no-reply@teams.mail.microsoft.com"` surfaces what chat
  search missed
---
## SharePoint and OneDrive
### Common patterns
**Find a document by topic**
```
sharepoint_search(query: "OKR Q3 2026", afterDateTime: "2026-04-01T00:00:00Z")
```
**Find a meeting transcript**
```
sharepoint_search(query: "[meeting name] transcript", afterDateTime: "2026-05-20T00:00:00Z")
```
**Find a folder**
```
sharepoint_folder_search(name: "TECH Foundation")
```
### Gotchas
- `query` is required; cannot be empty
- Date filters use **strict ISO 8601** with `Z` suffix — natural
  language is not accepted
- Use `fileType: "pdf"` / `"docx"` / `"pptx"` to narrow by type
- Max limit is 50, higher than the other M365 tools
---
## Meeting transcripts — two paths
Transcripts can be retrieved two ways. Path 1 is canonical when it
works; path 2 is the reliable fallback.
### Path 1 — via the calendar event (preferred)
1. Find the meeting with `outlook_calendar_search`
2. Read the event with `read_resource` using URI:
   `calendar:///events/{eventId}`
3. The event response includes a `meetingTranscriptUrl` field
4. Pass that URL **verbatim** to `read_resource` as the URI
   (it starts with `meeting-transcript:///events/...`)
### Path 2 — via SharePoint (fallback)
Used historically when path 1 was unreliable.
```
sharepoint_search(query: "[meeting name] transcript", afterDateTime: "{date}")
```
Then read the resulting file URI with `read_resource`.
When in doubt during a digest transcript check, try path 1 first and
fall back to path 2 if it returns nothing. See the `daily-copilot` skill
for what to log into Microsoft To Do once transcripts are found.
---
## read_resource — URI cheat sheet
| Resource | URI pattern |
|---|---|
| Outlook email | `mail:///messages/{messageId}` |
| Email in shared mailbox | `mail:///messages/{messageId}?owner={email}` |
| Outlook folder | `mail:///folders/{folderId}` |
| Calendar event | `calendar:///events/{eventId}` |
| Calendar event in delegated calendar | `calendar:///events/{eventId}?owner={email}` |
| Meeting transcript | `meeting-transcript:///events/{joinUrlToken}` (pass verbatim from event) |
| SharePoint / OneDrive file | `file:///{driveId}/{itemId}` |
| SharePoint page | `page:///sites/{siteId}/pages/{pageId}` |
| Teams chat message | `teams:///chats/{chatId}/messages/{messageId}` |
| Teams channel message | `teams:///teams/{teamId}/channels/{channelId}/messages/{messageId}` |
---
## Time zone — UTC to CEST
Martin is in Denmark (CEST, UTC+2 in summer, UTC+1 in winter).
- All calendar and meeting times come back in UTC
- Convert before displaying: `09:00 UTC` → `11:00` (summer) or
  `10:00` (winter)
- When in doubt about DST, check current offset rather than guessing
---
## What this skill does NOT cover
- Digest / morning-brief format and order of operations (see the
  `daily-copilot` skill — "Prepare my day" / "Prepare my week")
- Logging tasks and meeting notes once found (see the `daily-copilot`
  skill — Microsoft To Do conventions)
- Cloud cost data (see the cloud-cost skill, if present)
- **Tone / wording** of drafted emails and Teams replies — the *how to
  create* mechanics (endpoints, fields, confirm-first flow) are covered
  above, but the voice is governed by Martin's working preferences
  (concise, architect-to-architect, no preamble, mobile-readable, no
  emojis), not by this skill
- Teams chat *posting* — only mail and calendar writes are covered here;
  there is no documented Teams send path yet