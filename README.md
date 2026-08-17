# Class Value OS

Front-end for Class Valuation's internal Value OS platform. Plan Builder and Demand Management are real,
database-backed modules; the rest are static design previews, built out module by module as the backend
gets connected.

**Each module is its own page with its own URL** — `index.html`, `demand.html`, `cpq.html`, `plan.html`,
`studio.html`, `delivery.html`, `reporting.html`, `engagement.html`, `roles.html`, `states.html` — sharing
a common sidebar/top bar (`shared.css`). This means:

- Every module is directly linkable and bookmarkable (e.g. `.../demand.html` opens straight into Demand
  Management), and browser back/forward works normally between modules.
- Updating one module only requires re-uploading that module's single file. Editing Demand Management and
  re-uploading `demand.html` cannot break Plan Builder, CPQ, or any other page — they're separate files
  with separate JavaScript, not separate views inside one shared script.
- The only file every module depends on is `shared.css` (sidebar/top bar/layout styling). Changing that
  affects the shell's look everywhere, same as before, but still doesn't touch any module's own logic.

## Files

- `index.html` — My work (home).
- `demand.html` — Demand Management. Real, database-backed (see below).
- `cpq.html` — Value CPQ (static design preview).
- `plan.html` — Plan Builder. Real, fully-functional; embeds `class-plan-builder.html` via iframe.
- `studio.html`, `delivery.html`, `reporting.html`, `engagement.html`, `roles.html`, `states.html` — static
  design previews with sample data, waiting to be built out the same way Demand Management was.
- `shared.css` — the one file all ten pages link to for the shared sidebar/top bar/layout styling.
- `class-plan-builder.html` — the real, fully-functional Class Plan Builder application. Works standalone
  or embedded inside `plan.html`. Saves projects to the browser's `localStorage` under the key
  `classPlanBuilder.projects.v1` (per-browser, not shared across users yet).
- `supabase-config.js` — where you paste your Supabase project's URL and anon key. Only `demand.html` reads
  this file to connect. Ships blank; the module shows a clear "needs a database connection" state until
  it's filled in, rather than failing silently.
- `supabase/schema.sql` — the database schema for Demand Management. Paste it into your Supabase project's
  SQL editor once, before the module will have anything to read or write.
- `.nojekyll` — tells GitHub Pages to serve these files as-is, skipping Jekyll processing.

No build step, no framework. `demand.html` loads the Supabase JS client from a CDN and talks to your
database directly from the browser — the anon key is safe to expose this way because your Row Level
Security policies (in `schema.sql`) control what it's actually allowed to do. No other page loads Supabase
at all, so they have nothing to configure and nothing that can fail to connect.

## What's functional right now

- **Plan Builder** — fully functional, saves to each browser's `localStorage`.
- **Demand Management** — fully functional once Supabase is configured (see below): real intake, filtering
  by segment/source/owner/score/created date/stage, saved-view tabs (My demands / Unscored / Awaiting
  decision / All open), a transparent 5-input weighted scoring model, an activity/notes thread per demand,
  and a portfolio matrix (value vs. integration effort). Demands are never hard-deleted.
- **Value CPQ** — still a static design preview for actually building a quote, but its "Client & demand"
  step now shows a real, live, read-only list of every Converted demand (client, segment, volume, value,
  score, requirement summary), pulled from the same Supabase project as Demand Management. Nothing else in
  CPQ is wired up yet.
- Everything else (Integration Studio, Delivery, Status Reporting, Engagement Management, Roles &
  permissions, System states) is still a static mockup with sample data, waiting to be built the same way.

### Demand stage flow

A demand only reaches Decision or Converted through a manual, deliberate action — nothing moves it there
automatically, since Value CPQ has no backend of its own yet to trigger it:

- **Unscored → Open** — automatic, the moment all 5 strategic-fit scores are entered.
- **Open → Decision** — manual, via the "Change stage" control on the demand. You name who owns the call
  (an internal teammate, or the client — with a stakeholder name and contact info if so) and what's actually
  being decided. That context stays visible on the demand afterward.
- **Decision → Converted** — manual, one click, once a demand meets all criteria and is ready to be quoted.
  This is the real trigger that makes it appear on Value CPQ's Client & demand list — not the "Configure
  quote in CPQ" button, which stays informational until CPQ itself is built.
- **Park / Reject (with a reason)** — available from Unscored, Open, or Decision. Never deletes the record.
- **Reopen** — brings a parked or rejected demand back to Open at any time.
- **Archive** — only ever offered once a demand is Rejected. It's a visibility flag, not a stage: archived
  demands drop out of the default list (and out of tab counts) but are never deleted, and a "Show archived"
  checkbox in the filter row brings them back into view. Reopening an archived demand un-archives it too.

## Setting up Supabase for Demand Management

**Already have a project running from before?** This update added new columns to `demands` (decision
owner/pending-note fields, `archived`) — open **SQL Editor → New query**, paste in the current
`supabase/schema.sql`, and click **Run** once. It's written to be safe against a project that already has
data: it only adds what's missing and never touches existing rows.

1. Create a free account at [supabase.com](https://supabase.com) and click **New project**. Pick any name
   and a database password (Supabase asks you to set one — store it somewhere safe, you likely won't need
   it day-to-day since the app talks to Supabase through the API, not a direct Postgres connection).
2. Once the project finishes provisioning, open **SQL Editor** in the left sidebar → **New query**, paste
   in the entire contents of `supabase/schema.sql` from this folder, and click **Run**. This creates the
   tables (`clients`, `demands`, `demand_activity`, `demand_attachments`, `demand_scoring_weights`), their
   constraints, and starter Row Level Security policies. It's safe to re-run if you ever need to.
3. Open **Project Settings → API**. Copy the **Project URL** and the **`anon` `public`** key (not the
   `service_role` key — that one must never go into client-side code).
4. Open `supabase-config.js` and fill in both values:
   ```js
   window.SUPABASE_CONFIG = {
     url: 'https://xxxxxxxxxxxx.supabase.co',
     anonKey: 'eyJhbGciOi...'
   };
   ```
5. Push/upload the updated `supabase-config.js` to your GitHub repo (same "Add file → Upload files" flow
   you've used before) — you don't need to re-upload `demand.html` or anything else for this step. Demand
   Management will connect on the next page load.

### About the current access model

Row Level Security is **on**, but every policy is permissive (`using (true)`) — anyone with the anon key
can read and write. That's intentional for now: Roles & permissions (who can see or do what) hasn't been
designed yet, and you said that's a later step once more modules exist. Every policy in `schema.sql` is
written so tightening it later is a small, targeted change (e.g. swapping `using (true)` for a real
`auth.uid()` check) rather than a rewrite.

## Deploying to GitHub Pages

1. Create a new repository on GitHub (public — Pages is free for public repos; private repos need GitHub
   Pro/Team/Enterprise for Pages).
2. Push these files to the repo's default branch (`main`), at the repo root — either via `git push` or the
   "Add file → Upload files" web UI.
3. In the repo on GitHub: **Settings → Pages → Build and deployment → Source: "Deploy from a branch"** →
   Branch: `main`, folder `/ (root)` → Save.
4. GitHub gives you a URL like `https://<your-username>.github.io/<your-repo>/`. It auto-redeploys on every
   push to `main` — no extra workflow file needed. Each module has its own path off that URL, e.g.
   `.../demand.html`, `.../plan.html`.

**For future updates:** since each module is its own file, you only need to upload the file(s) that
actually changed. Got a new `demand.html` from a Demand Management update? Upload just that one file —
`index.html`, `plan.html`, `cpq.html`, and everything else on the live site stay exactly as they are.

## The one Cowork-only feature

Inside Class Plan Builder, the **"Process document(s)"** button (part of "Upload & Process") calls
`window.cowork.askClaude(...)` to auto-fill fields from an uploaded file. That bridge only exists inside
Cowork. Outside it — here, on GitHub Pages — the button is still there but shows *"AI extraction is not
available in this view"* instead of crashing. Everything else works the same. Making that button work in
this deployment would need a small backend or serverless function to hold an Anthropic API key server-side
(never in client-side code).

## Local testing before you push

Don't just double-click the HTML files — some browsers restrict `localStorage` on `file://` URLs, and the
Supabase client behaves better served over `http://`. Serve them locally instead:

```bash
python3 -m http.server 8000
# then open http://localhost:8000/
```
