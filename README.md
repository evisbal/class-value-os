# Class Value OS

Front-end for Class Valuation's internal Value OS platform. Plan Builder and Demand Management are real,
database-backed modules; the rest are static design previews, built out module by module as the backend
gets connected.

**Each module is its own page with its own URL** — `index.html`, `demand.html`, `cpq.html`,
`cpq-config.html`, `plan.html`, `studio.html`, `delivery.html`, `reporting.html`, `engagement.html`,
`roles.html`, `states.html` — sharing a common sidebar/top bar (`shared.css`). This means:

- Every module is directly linkable and bookmarkable (e.g. `.../demand.html` opens straight into Demand
  Management), and browser back/forward works normally between modules.
- Updating one module only requires re-uploading that module's single file. Editing Demand Management and
  re-uploading `demand.html` cannot break Plan Builder, CPQ, or any other page — they're separate files
  with separate JavaScript, not separate views inside one shared script.
- The only file every module depends on is `shared.css` (sidebar/top bar/layout styling). Changing that
  affects the shell's look everywhere, same as before, but still doesn't touch any module's own logic.

## Responsive / mobile

Every page works down to phone width. Below 900px the sidebar becomes a drawer — tap the ☰ button (top
right) to open it, tap the dimmed backdrop or ☰ again to close it; above 900px it's just always there like
before. Below 860px, list/detail and multi-column layouts stack into a single column so nothing gets cut
off — this includes Demand Management's table, which becomes a stack of cards (its column-header row hides
itself there since it stops meaning anything once stacked) and its detail panel, which moves below the list
instead of sitting beside it. Value CPQ's step tabs scroll horizontally on narrow screens instead of
wrapping, since wrapping would break the numbered stepper look. Plan Builder's own tool got the same
treatment (tab bar scrolls, its internal grids stack) since it's a real, separately-built tool embedded via
iframe, not generated from this shell. The six static preview modules got the same stacking treatment as a
baseline — they'll likely want a closer pass once they're built out for real, same as everything else about
them.

## Files

- `index.html` — My work (home).
- `demand.html` — Demand Management. Real, database-backed (see below).
- `cpq.html` — Value CPQ. Client & demand, Configure and Rules check are real, database-backed (see below);
  Pricing & terms and Quote & approvals are still static design previews.
- `cpq-config.html` — CPQ Config, a subpage of Value CPQ (reached via the "Manage catalog" link on the
  CPQ list, not the main sidebar). Full CRUD admin catalog for every product, add-on and pricing rule
  Configure reads from — see below.
- `plan.html` — Plan Builder. Real, fully-functional; embeds `class-plan-builder.html` via iframe.
- `studio.html`, `delivery.html`, `reporting.html`, `engagement.html`, `roles.html`, `states.html` — static
  design previews with sample data, waiting to be built out the same way Demand Management was.
- `shared.css` — the one file all ten pages link to for the shared sidebar/top bar/layout styling.
- `class-plan-builder.html` — the real, fully-functional Class Plan Builder application. Works standalone
  or embedded inside `plan.html`. Saves projects to the browser's `localStorage` under the key
  `classPlanBuilder.projects.v1` (per-browser, not shared across users yet).
- `supabase-config.js` — where you paste your Supabase project's URL and anon key. `demand.html`, `cpq.html`
  and `cpq-config.html` all read this file to connect. Ships blank; every module shows a clear "needs a
  database connection" state until it's filled in, rather than failing silently.
- `supabase/schema.sql` — the database schema for Demand Management and Value CPQ (including CPQ Config's
  catalog). Paste it into your Supabase project's SQL editor once, before any of these modules will have
  anything to read or write.
- `.nojekyll` — tells GitHub Pages to serve these files as-is, skipping Jekyll processing.

No build step, no framework. `demand.html` and `cpq.html` load the Supabase JS client from a CDN and talk
to your database directly from the browser — the anon key is safe to expose this way because your Row Level
Security policies (in `schema.sql`) control what it's actually allowed to do. No other page loads Supabase
at all, so they have nothing to configure and nothing that can fail to connect.

## What's functional right now

- **Plan Builder** — fully functional, saves to each browser's `localStorage`.
- **Demand Management** — fully functional once Supabase is configured (see below): real intake, filtering
  by segment/source/owner/score/created date/stage, saved-view tabs (My demands / Unscored / Awaiting
  decision / All open), a transparent 5-input weighted scoring model, an activity/notes thread per demand,
  and a portfolio matrix (value vs. integration effort). Demands are never hard-deleted.
- **Value CPQ** — Phases 1 & 2 are real (see `CPQ_requirements_scope.md` for the full plan): every Converted
  demand gets a "Configure quote" action that creates a real, versioned `quotes` record and opens a quote
  editor. **Client & demand** shows the demand's real context (client, segment, source demand, est. monthly
  volume) read-only from Demand Management, plus a guided-questions panel that saves to the quote.
  **Configure** is a real product/add-on catalog (`cpq_products`) — selections and monthly volumes persist
  to `quote_line_items`, eligibility is filtered live by the client's actual segment (no separate, redundant
  segment question), and a live pricing panel totals it all up. **Rules check** is a real rule engine
  computed live from Configure's selections — configuration-completeness, a live segment/entitlement
  re-check (catches a product going ineligible after selection, not just at selection time), product data
  readiness, and a generic "requirement to confirm" row for any selected add-on with a catalog caveat. A
  hard stop blocks Continue (only a "Request exception" placeholder is offered, honest that routing isn't
  built yet); a warning doesn't block. Discount authority is shown as an honest "not evaluated yet" row —
  it needs a real discount, which Pricing & terms (next phase) will capture. **Pricing & terms** and
  **Quote & approvals** are still the original static mockup steps, shown with an inline "not built yet"
  notice.
- **CPQ Config** — a subpage of Value CPQ (the "⚙ Manage catalog" link on the CPQ list header), and fully
  real: full CRUD over the exact `cpq_products` catalog Configure reads from, with no separate publish
  step — a change here is live on Configure's next load. Three sections: "Products & services" (grouped
  into Appraisal Offerings / Alternative Valuations), "Add-ons & service levels," and **"Pricing tiers"**
  (see below). The product/add-on create/edit modal covers every field Configure or Rules check can use:
  category (which also sets the underlying product/add-on mechanic and a sensible pricing-basis default),
  name, description, unit price (0 = shown as "Custom-priced," for things like Guaranteed Pricing or CVUE
  that are negotiated per account), pricing basis (per order / per month / custom-priced per account),
  eligible segments (checkboxes — none checked means every segment), a requires-note caveat (the same field
  Rules check already surfaces as a warning), a data-ready flag, and sort order. Nothing is ever
  hard-deleted — "Deactivate" sets `active = false` (Configure already only shows active rows), and a "Show
  inactive" toggle brings deactivated rows back into view for review or reactivation. **Access:** open to
  every role for now — an inline banner at the top says so explicitly. Roles & permissions doesn't exist
  yet; once it does, this page should be gated to whoever owns pricing (Sales VP / Pricing & Finance are the
  obvious candidates), not left open like this.

- **Pricing tiers (volume-based rate cards)** — a real, working piece of the Phase 3 "Pricing & terms"
  concept, built ahead of the rest of that phase. A tier (`pricing_tiers`: name, min/max monthly volume,
  description) is a **client-level business rule, not a quote-level one, and has no connection to
  invoicing** — its only output is what a quote shows. From Value CPQ's Client & demand tab, applying a
  tier writes to `clients.pricing_tier_id` (sticky — future quotes for that client default to it) and to
  `quotes.pricing_tier_id` (what was in effect for this specific quote); a suggested tier is shown based on
  the demand's estimated monthly volume, but applying one is always a deliberate action, never automatic.
  Each tier is a **per-product rate card** (`pricing_tier_rates`: tier + product + override price), not a
  blanket discount — a product with no override at a given tier simply falls back to its catalog base
  price, so admin effort only grows with how many prices actually differ per tier. Manage tiers and their
  rate cards from CPQ Config's "Pricing tiers" section. Configure shows the tier-adjusted price (struck
  through against the base price) wherever a rate-card entry exists, and the frozen price a client actually
  gets is written to `quote_line_items.unit_price_snapshot` at the moment an item is selected — same
  snapshot pattern as everything else in quoting, so a client's tier changing later never rewrites an
  already-quoted price. Rules check's discount-authority row names the applied tier when one is set.
  **The volume ranges seeded (Standard 0–149, Preferred 150–349, Enterprise 350+ orders/mo) are an informed
  placeholder**, not real historical order data — swap them for real breakpoints once that data exists.
- Everything else (Integration Studio, Delivery, Status Reporting, Engagement Management, Roles &
  permissions, System states) is still a static mockup with sample data, waiting to be built the same way.

### The catalog itself was revised against classvaluation.com

Building CPQ Config was also the occasion to check the seeded product catalog against Class Valuation's
real "Our Products" menu (Appraisal Offerings + Alternative Valuations) and Solutions pages. The original
9-row seed had 6 real products, was missing 6 more, and had 3 add-ons that don't actually exist as public
Class Valuation offerings (a "Rush turn-time tier," a "Guaranteed Pricing" seeded with an invented 12-month
term, and an "Order API + webhooks"). The current seed (`supabase/schema.sql`) is 14 rows: all 12 real
products (5 Appraisal Offerings, 7 Alternative Valuations) plus the 2 real Solutions that behave like a
selectable line item — Guaranteed Pricing and CVUE, both correctly modeled as custom-priced per account
rather than given a made-up flat fee. This only affects **new** installs — an existing project's seeded
rows (including the fabricated add-ons) are left alone rather than silently rewritten; review and
deactivate or correct them from CPQ Config if you already ran the original schema. Pay Later (a borrower
payment-plan option on the real site) isn't a catalog line item at all — it's a candidate for a future
Pricing & terms "payment terms" field, not something CPQ Config manages.

### Demand stage flow

A demand only reaches Decision or Converted through a manual, deliberate action — nothing moves it there
automatically, since Value CPQ has no backend of its own yet to trigger it:

- **Unscored → Open** — automatic, the moment all 5 strategic-fit scores are entered.
- **Open → Decision** — manual, via the "Change stage" control on the demand. You name who owns the call
  (an internal teammate, or the client — with a stakeholder name and contact info if so) and what's actually
  being decided. That context stays visible on the demand afterward.
- **Open → Converted** — manual, one click, whenever a demand meets all criteria and is ready to be quoted
  with no open questions. Decision isn't a required gate — most demands won't need it.
- **Decision → Converted** — the same one-click action, once whatever was pending in Decision is resolved.
  Either path is the real trigger that makes a demand appear on Value CPQ's Client & demand list — not the
  "Configure quote in CPQ" button, which stays informational until CPQ itself is built.
- **Park / Reject (with a reason)** — available from Unscored, Open, or Decision. Never deletes the record.
- **Reopen** — brings a parked or rejected demand back to Open at any time.
- **Archive** — only ever offered once a demand is Rejected. It's a visibility flag, not a stage: archived
  demands drop out of the default list (and out of tab counts) but are never deleted, and a "Show archived"
  checkbox in the filter row brings them back into view. Reopening an archived demand un-archives it too.

## Setting up Supabase for Demand Management

**Already have a project running from before?** This update adds a `family` column to `cpq_products`
(backing CPQ Config's Appraisal Offering / Alternative Valuation / Add-on & Service Level grouping),
revises the seed catalog to match classvaluation.com's real product list (see "The catalog itself was
revised" above), and adds `pricing_tiers` + `pricing_tier_rates` (volume-based rate-card pricing, plus a
`pricing_tier_id` column on both `clients` and `quotes`) — see "Pricing tiers" above. Open **SQL Editor →
New query**, paste in the current `supabase/schema.sql`, and click **Run** once. It's written to be safe
against a project that already has data: it only adds what's missing and never touches or deletes existing
rows (including your existing seeded catalog rows, even the ones the new seed list no longer includes —
review those from CPQ Config).

1. Create a free account at [supabase.com](https://supabase.com) and click **New project**. Pick any name
   and a database password (Supabase asks you to set one — store it somewhere safe, you likely won't need
   it day-to-day since the app talks to Supabase through the API, not a direct Postgres connection).
2. Once the project finishes provisioning, open **SQL Editor** in the left sidebar → **New query**, paste
   in the entire contents of `supabase/schema.sql` from this folder, and click **Run**. This creates the
   tables (`clients`, `demands`, `demand_activity`, `demand_attachments`, `demand_scoring_weights`,
   `cpq_products`, `quotes`, `quote_line_items`), their constraints, starter Row Level Security policies, and
   the CPQ product/add-on catalog. It's safe to re-run if you ever need to.
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
