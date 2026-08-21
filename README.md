# Class Value OS

Front-end for Class Valuation's internal Value OS platform. Demand Management, Value CPQ, Plan Builder,
Roles & permissions, SSO configuration and Integration Studio are real, database-backed modules; the rest
are static design previews, built out module by module as the backend gets connected.

**Each module is its own page with its own URL** — `index.html`, `demand.html`, `cpq.html`,
`cpq-config.html`, `plan.html`, `studio.html`, `delivery.html`, `reporting.html`, `engagement.html`,
`roles.html`, `sso-config.html`, `states.html` — sharing a common sidebar/top bar (`shared.css`). This means:

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
wrapping, since wrapping would break the numbered stepper look. Plan Builder is inlined directly into
`plan.html` now (see below) — its own two-column layout collapses to one column under 920px via its own CSS,
same as everywhere else, but its tab bar doesn't have its own scroll/wrap behavior; on very narrow phones
(under ~420px) it can run wider than the screen, and the page falls back to horizontal scroll rather than
clipping it (the same last-resort safety net every other screen here uses) — a real gap in Plan Builder's own
responsive design, not something introduced by inlining it, worth a closer pass at some point. The six static
preview modules got the same stacking treatment as a baseline — they'll likely want a closer pass once
they're built out for real, same as everything else about them.

## Files

- `index.html` — My work (home).
- `demand.html` — Demand Management. Real, database-backed (see below).
- `cpq.html` — Value CPQ. Client & demand, Configure, Pricing & terms and Rules check are all real,
  database-backed (see below); only Quote & approvals is still a static design preview.
- `cpq-config.html` — CPQ Config, a subpage of Value CPQ (reached via the "Manage catalog" link on the
  CPQ list, not the main sidebar). Full CRUD admin catalog for every product, add-on and pricing rule
  Configure reads from — see below.
- `plan.html` — Plan Builder. Real, fully-functional, inlined directly into the page (no iframe) — see below.
- `roles.html` — Roles & permissions. Real CRUD — see "Roles & permissions" below.
- `sso-config.html` — SSO configuration, a Platform subpage for IT admins. Real form, deliberately inert —
  see "SSO configuration" below.
- `studio.html` — Integration Studio. Real, database-backed — see "Integration Studio" below.
- `delivery.html`, `reporting.html`, `engagement.html`, `states.html` — static
  design previews with sample data, waiting to be built out the same way Demand Management was.
- `shared.css` — the one file every page links to for the shared sidebar/top bar/layout styling, including
  the "acting as" role switcher in the sidebar footer (see "Roles & permissions" below).
- `class-plan-builder.html` — the same Class Plan Builder application as `plan.html`, as a standalone,
  bookmarkable page (its own `<html>/<head>/<body>`, no Value OS sidebar/topbar). `plan.html` no longer
  embeds this file — the two are independent files built from the same source (see "Plan Builder" below);
  editing one doesn't change the other. Both save projects to the browser's `localStorage` under the same key
  (`classPlanBuilder.projects.v1`), and since `localStorage` is scoped per origin, not per page, once this
  deploys to GitHub Pages the two pages actually **share** that data (same site, same key) — a plan created on
  one shows up on the other, on the same browser.
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
- **Value CPQ** — every Converted demand gets a "Configure quote" action that creates a real, versioned
  `quotes` record and opens a quote editor (see `CPQ_requirements_scope.md` for the full plan). Steps run
  **Client & demand → Configure → Pricing & terms → Rules check → Quote & approvals** — pricing is settled
  before the rules/compatibility check runs against it. Tab checkmarks reflect real captured data on that
  step (a selection made, a question answered, a discount set), not just "comes before whichever tab is
  active." **Client & demand** shows the demand's real context (client, segment, source demand, est. monthly
  volume) read-only from Demand Management, plus a guided-questions panel that saves to the quote.
  **Configure** is a real product/add-on catalog (`cpq_products`) — selections and monthly volumes persist
  to `quote_line_items`, eligibility is filtered live by the client's actual segment (no separate, redundant
  segment question), and a live pricing panel totals it all up. **Pricing & terms** is real (see below) —
  an ad hoc blended discount, a real gross-margin check against catalog cost data, commercial terms, and the
  approval gate the rest of the flow reads. **Rules check** is a real rule engine computed live from
  Configure's and Pricing & terms' actual state — configuration-completeness, a live segment/entitlement
  re-check (catches a product going ineligible after selection, not just at selection time), product data
  readiness, a generic "requirement to confirm" row for any selected add-on with a catalog caveat, and
  discount authority (real now — flags any ad hoc discount or margin-floor breach as a warning, not a hard
  stop, since Quote & approvals doesn't exist yet to route it anywhere). A hard stop blocks Continue (only a
  "Request exception" placeholder is offered, honest that routing isn't built yet); a warning doesn't block.
  **Quote & approvals** is still the original static mockup step, shown with an inline "not built yet"
  notice — including its stakeholders panel of named reviewers. Roles & permissions is real now (see below),
  so the *who* (Deal desk, Pricing & finance, VP Sales all exist as real approval-capable roles) is in place;
  what's still missing is the approval-routing engine itself — persisting a decision, notifying the right
  approver, and recording their response — which is a separate, not-yet-built piece.

- **Pricing & terms** — real. An **ad hoc blended discount** (0–30%, one rate for the whole quote) applies
  on top of whatever price is already in effect — catalog base, or tier-adjusted where a pricing tier
  applies — and stacks with it rather than replacing it; if a tier is already bringing prices down, an
  inline notice says so before the rep adds anything further. **The auto-approve cap defaults to 0%** — a
  rate-card tier is the only "discount" that doesn't need sign-off by default; the moment the ad hoc slider
  crosses the cap, a banner explains that Pricing & finance approval is required, live as it's dragged.
  **Gross margin** is computed from `cpq_products.unit_cost` (new column, editable in CPQ Config right next
  to unit price) — margin lives per product, not per client or per bundle, because cost to deliver genuinely
  varies by product (a licensed-appraiser dispatch costs far more than an automated AVM) and doesn't move
  with whatever tier or discount gets applied; the quote's blended margin is a volume-weighted rollup of
  whatever's actually selected, computed live, never a separately-configured number. A selected item with no
  cost data yet shows an honest "margin not verified" state rather than assuming it's fine. This margin bar
  (and its "below/within floor" verdict) is explicitly labeled **internal only, never shown on the quote or
  PDF** — the "Live pricing" panel on the right (the one closer to what a client would eventually see) shows
  monthly/annual totals, blended discount, and a **Total contract value** figure once a contract term is set
  (monthly total × term length), but deliberately does not surface margin anywhere in it. **The margin floor
  and discount auto-approve cap are real, editable settings** (`cpq_pricing_policy`, a singleton row — see
  CPQ Config below), not code constants — defaults are 42% and 0%, same as the placeholder values these
  replaced. Crossing either threshold — or having unknown cost data — sets `quotes.status` to
  `needs_pricing_approval` live (the header badge reflects this immediately) and clears back to `draft` the
  moment the condition no longer applies. **Commercial structure** (Tiered volume / Annual commitment / Pure
  consumption) is informational only — a label saved on the quote for the PDF/context, not a second pricing
  mechanic layered on top of Pricing tiers. **Terms** (contract length, payment terms, price review cadence,
  volume commitment, Pay Later) are plain fields, uniformly sized, that save on change. The line items table
  and live pricing panel show list vs. net (after tier + discount) side by side, so nobody negotiates
  against stale numbers.
- **CPQ Config** — a subpage of Value CPQ (the "⚙ Manage catalog" link on the CPQ list header), and fully
  real: full CRUD over the exact `cpq_products` catalog Configure reads from, with no separate publish
  step — a change here is live on Configure's next load. Four sections: "Products & services" (grouped
  into Appraisal Offerings / Alternative Valuations), "Add-ons & service levels," **"Pricing tiers"**
  (see below), and **"Pricing policy"** — two fields, the discount auto-approve cap and margin floor
  (`cpq_pricing_policy`), that Pricing & terms checks every quote against; saves on change and applies to
  every quote immediately, same as everything else here. Distinct from Pricing tiers (rate cards by volume
  band — sets the price itself) and a product's own Unit cost (sets that one product's cost) — this section
  sets the threshold at which a rep needs sign-off on top of whatever price is already in effect. The
  product/add-on create/edit modal covers every field Configure or Rules check can use:
  category (which also sets the underlying product/add-on mechanic and a sensible pricing-basis default),
  name, description, unit price (0 = shown as "Custom-priced," for things like Guaranteed Pricing or CVUE
  that are negotiated per account), **unit cost** (what it costs to deliver one unit — drives the real
  margin check on Pricing & terms, shown live on the card and in the modal as you type; left blank means
  "not yet costed," not zero), pricing basis (per order / per month / custom-priced per account),
  eligible segments (checkboxes — none checked means every segment), a requires-note caveat (the same field
  Rules check already surfaces as a warning), a data-ready flag, and sort order. Nothing is ever
  hard-deleted — "Deactivate" sets `active = false` (Configure already only shows active rows), and a "Show
  inactive" toggle brings deactivated rows back into view for review or reactivation. **Access:** real now —
  gated on Edit access to the `cpq-config` module (see "Roles & permissions" below). Whoever is "acting as"
  without that capability gets a read-only view (no Add/Edit/Rate card buttons, pricing policy fields shown
  but disabled) and a banner naming who to ask; Pricing & finance and Deal desk / Sales ops are the two seeded
  roles with View, and only Pricing & finance seeds with Edit.

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
  rate cards from CPQ Config's "Pricing tiers" section — each field there accepts either a flat dollar price
  (`495`) or a percent-off shorthand (`10%` or `-10%`, both read as "10% off," never a markup); typing a
  percent shows a live "X% off base" badge and resolves to its dollar amount on blur, but what's actually
  stored is always the dollar price, so a later base-price change on the product can never silently move an
  already-set tier price. Configure shows the tier-adjusted price (struck
  through against the base price) wherever a rate-card entry exists, and the frozen price a client actually
  gets is written to `quote_line_items.unit_price_snapshot` at the moment an item is selected — same
  snapshot pattern as everything else in quoting, so a client's tier changing later never rewrites an
  already-quoted price. A tier discount is pre-approved rate-card pricing, so Rules check's discount-authority
  row doesn't need to call it out — only the tier badge on the live pricing panel and Pricing & terms'
  "tier already applied" notice do that; the discount-authority row itself reacts to what's captured on
  Pricing & terms (ad hoc discount, margin) instead.
  **The volume ranges seeded (Standard 0–149, Preferred 150–349, Enterprise 350+ orders/mo) are an informed
  placeholder**, not real historical order data — swap them for real breakpoints once that data exists.
- **Integration Studio** — real (see "Integration Studio" below): a configurable Task Library driving both
  the Standard Offering Library and Custom Configuration Canvas, an effort roll-up, JIRA CSV export + a
  wired-but-credential-gated JIRA API push, and versioned requirement-doc PDF generation.
- **Delivery** — real now (see "Delivery" below): a cockpit over exactly the clients Integration Studio has
  moved to Delivery, with computed (not JIRA-sourced, not hand-typed) plan completion and risk, manual
  blockers and a go-live checklist, and the one lifecycle transition into Engagement.
- Everything else (Status Reporting, Engagement Management, System states) is still a static mockup with
  sample data, waiting to be built the same way.

## Plan Builder

`plan.html` used to embed Plan Builder via `<iframe src="class-plan-builder.html">` — a full extra HTML
document loaded inside a bordered card. It's inlined directly into the page now: no iframe, no card, no
fixed height. Plan Builder's own header/tabs/panels render flush in the content area, the same way Demand
Management or Value CPQ do, and it scrolls with the rest of the page instead of having its own separate
scroll region.

The style/body/script split lives in `fragments/plan_builder_*` (extracted from `Class_Plan_Builder.html` at
build time, not hand-edited) and gets pulled into both `plan.html` and the merged Cowork-artifact build.
Before inlining, every element ID, CSS class, and DOM-wide script query in Plan Builder was checked against
everything else in this app for collisions, since inlining means it now shares one DOM and one global script
scope with every other module instead of living in its own isolated iframe document. One real collision was
found and fixed: Plan Builder redefined `.info-icon` tooltip styling identically to what `shared.css` already
provides — its copy is dropped at extraction time so there's only one definition. Everything else (58 element
IDs, its CSS classes, its four `document.querySelectorAll` calls) was already clean. `Class_Plan_Builder.html`
itself is untouched by this — it's also a separately published, standalone Cowork artifact and needs to keep
working on its own (see "Files" above for how the two now relate).

One thing this surfaced rather than caused: Plan Builder's tab bar has no responsive behavior of its own
(no wrap, no internal scroll), so on very narrow phones it can run wider than the screen — the page falls
back to horizontal scroll, same safety net every other screen here uses, rather than clipping content. This
existed before too, just contained inside the iframe's own scroll area instead of the page's; a closer
responsive pass on Plan Builder's tab bar is worth doing at some point but wasn't part of this change.

## Integration Studio

Real now — `studio.html` (`fragments/studio_module.js`) replaces the static design mockup. One configurable
**Task Library** (`integration_task_templates`) feeds two views over the same data instead of two
disconnected lists: the **Standard Offering Library** ("out of box" onboarding, known effort — check items
off for a client) and the **Custom Configuration Canvas** (for clients needing their own mapping —
start from the same library or add a requirement from scratch, with systems touched / acceptance criteria /
confidence / client dependency fields). Each template can be eligible for either section, both, or neither.
A client's task list can freely **mix** OOO and Custom items — not a mode the whole client is locked into.

Selecting a task copies it from the template into `client_integration_tasks` (client-scoped instances, same
catalog-vs-line-item split CPQ already uses) — editing a template later never rewrites an already-selected
client task. The **Effort roll-up** panel sums Standard vs. Custom vs. Total from real task data; it
deliberately does not show a comparison against a "CPQ-assumed" estimate, since no quote in this schema
carries an implementation-effort figure to compare against yet — that's flagged in the UI rather than faked.

**JIRA Mapping & Export**: one Epic per client, one Story per task. Effort maps to JIRA's own Original
Estimate field (as working days) rather than story points, since these are already time-based estimates.
"Download JIRA import (.csv)" produces a real file in exactly the shape JIRA's own CSV importer consumes —
works today, no live connection needed. "Push to JIRA" is wired to make a real API call (Basic auth against
JIRA's REST API v3), but checks `jira_config` (base URL, project key, API email/token, an `enabled` flag —
a Platform admin fills these in from the JIRA connection panel on the same tab) before ever attempting one,
and explains what's missing instead of silently failing or pretending to succeed — same honesty pattern as
SSO configuration above. Studio stays the system of record for intent, never JIRA: nothing pushed back from
a JIRA ticket is ever read back and written here.

**Requirement Doc** generates a PDF snapshot of a client's full task list (Standard + Custom), versioned in
`integration_requirement_docs` — same print/PDF pattern as Plan Builder's exports, and same append-only
version history (generating a new one never rewrites an earlier version).

**Move to Delivery** is the answer to a real problem: without it, every client onboarded through Studio would
pile up in the client picker forever, with no signal that a PM had actually handed the plan off to execution.
It's a one-row-per-client status (`client_integration_status`, `status` = `planning` | `in_delivery`) that a PM
sets explicitly with a "Move to Delivery →" button on the client workspace — never automatic, since Studio has
no other signal for "onboarding is actually done" to key off of. Moving a client to Delivery **freezes** their
plan: OOO checkboxes, Custom add/edit/remove, and Push to JIRA all become read-only, so the plan stays exactly
as a record of what was decided during onboarding. CSV export, PDF generation, and moving back to Planning all
stay available regardless, since none of them mutate the committed plan. Clients in Delivery drop out of the
default client picker list (an "IN DELIVERY" badge + a "Show clients in Delivery (N)" toggle reveal them again
— same default-hidden pattern already used for archived demands and inactive catalog items) so the picker
stays focused on active onboarding work instead of accumulating completed ones.

The move is reversible: **"Move back to Planning"** on the frozen banner un-freezes the plan and clears it from
the "in Delivery" bucket, for a PM who triggered the move by mistake or needs to correct something before
handoff is really ready. Moving back doesn't erase the original handoff record — `moved_to_delivery_at` /
`moved_to_delivery_by` stay on file alongside the new `moved_back_at` / `moved_back_by`, so the audit trail
shows the full history rather than just the current state. Nothing in this feature ever deletes a task,
document, or JIRA link — the status flag only ever gates editability of what's already there.

## Delivery

Real now — `delivery.html` (`fragments/delivery_module.js`) replaces the static design mockup. Delivery was
originally scoped as a read-mostly cockpit over live JIRA work, but there's no real JIRA connection yet, and
even once there is one, JIRA's own scope can drift from what Integration Studio committed at handoff (engineers
split stories, add work) — so "% of JIRA done" and "% of the Studio plan done" are two honestly different
numbers. Rather than fake a JIRA-shaped stat, this cockpit runs entirely on data Class Value OS already has:

The **worklist is exactly the clients Integration Studio has moved to Delivery** —
`client_integration_status.status = 'in_delivery'` — so the two modules share one handoff record instead of
two disconnected ideas of "who's in delivery." **Plan completion** is computed live from
`client_integration_tasks` (the same frozen plan Move-to-Delivery committed), weighted by each task's
estimated effort, and labeled "plan completion" rather than "JIRA progress" so it's never mistaken for live
dev-side data. Delivery is also where a PM now updates each task's status (Not started / In progress /
Blocked / Done) — Studio froze the *plan*, Delivery is where the *execution* status lives from here on.

**Risk** (the ON TRACK / AT RISK / BLOCKED badge, and "Sort by risk") is computed too, from open/escalated
blockers, blocked tasks, and pace against a target or implied go-live date — never hand-typed, so it can't
disagree with the blocker list sitting next to it. Pace uses a PM-set **target go-live date** when one exists;
if not, it falls back to an *implied* duration from the plan's own committed effort (5 working days per week,
same convention Studio's JIRA export already uses), and the UI says plainly when it's using the implied
fallback rather than a confirmed date. The exact thresholds (see `computeRisk()` in the module) are
deliberately simple: BLOCKED means any escalated blocker, being past the target/implied go-live date, or 3+
combined open blockers/escalations/blocked tasks; AT RISK means any open blocker or blocked task, or being
more than 15 points behind the expected pace; otherwise ON TRACK.

**Blockers** and the **go-live checklist** are the two things that genuinely need a human either way — "is
this stuck on our side or the client's" and "were the pilot orders actually completed end-to-end" aren't
things a ticket system reliably knows on its own, JIRA or not. Blockers (`delivery_blockers`) capture a
class-side/client-side split, an owner team, a status (new/open/escalated/resolved), and an optional
`linked_jira_key` for later — resolved blockers collapse into a "Show resolved" disclosure instead of
disappearing. The checklist (`delivery_checklist_templates` / `delivery_checklist_items`) uses the same
template-vs-instance split as Integration Studio's task library: a fixed, institution-wide checklist that's
copied into independently-checkable items the moment a client's Delivery workspace is first opened, so editing
a template later never rewrites an already-checked client's history.

**"Mark complete → Engagement"** is the one lifecycle transition this screen makes, gated on `can_approve`
(not just `can_edit`) since it's a bigger, one-way action than day-to-day status updates — disabled until every
checklist item is checked, and confirmed through a modal since there's no "move back" from Engagement the way
Studio's Planning⇄Delivery move has. Confirming sets `client_integration_status.status = 'in_engagement'` (with
`moved_to_engagement_at`/`_by`), which is also what drops the client off Delivery's worklist — everything
committed (tasks, blockers, checklist history) stays on record regardless.

**"Open in JIRA" / "Open Epic in JIRA"** are real deep links once `jira_config` (the same singleton table
Integration Studio's JIRA tab writes to) is enabled with a base URL and project key — the per-client Epic link
reuses Studio's exact `epicKeyFor()` convention (`INT-` + the client name, uppercased and stripped to
alphanumerics) so the same Epic key resolves from either module. Until JIRA is configured, clicking explains
what's missing instead of failing silently — the same honesty pattern already used for SSO configuration and
Studio's "Push to JIRA."

## Roles & permissions

Real now — `roles.html` is full CRUD over who can do what, not a mockup. Four tables back it
(`supabase/schema.sql`): **`roles`** (name, description, an `is_admin` flag, soft-delete `active`),
**`role_capabilities`** (one row per role × module the role has *any* access to, with `can_view` /
`can_create` / `can_edit` / `can_approve` / `can_export` booleans — a module with no row for a role means
zero access, not "everything off" spelled out), **`app_users`** (name, email, soft-delete `active`), and
**`user_roles`** (many-to-many — a user can hold more than one role, and gets the union of what any of them
grant). The schema seeds **9 roles**, reconciled against both the original Roles & permissions mockup's 6
and the separate Quote & approvals mockup's 4-stage approval chain (which named two approver stages — Deal
desk, Operations capacity — that had no home in the original 6): Account executive, Solutions engineer, Deal
desk / Sales ops, Pricing & finance, Implementation PM, VP Sales, Engagement manager, Executive / portfolio,
and Platform admin (the only role flagged `is_admin` — deliberately kept separate from any approval role,
so people who approve deals don't automatically also control who has access to the app). A starting
32-row capability matrix is seeded too, editable from the page afterward — it's a sensible default, not a
fixed rule.

From the role list, selecting a role shows its capability matrix (with an "Edit capabilities" modal) and the
users currently assigned to it, with controls to add an existing user or create a new one by name + email,
remove a user from the role, and deactivate/reactivate the role itself (soft-delete, same pattern as
`cpq_products`). "+ Request new role" creates one from scratch. Nothing here is ever hard-deleted.

**There is no real login yet.** Every page's sidebar footer is a shared switcher
(`fragments/role_context.js`) — click it to see every seeded user and pick who you're "acting as," clearly
labeled **TEST MODE — NOT REAL LOGIN**. Whoever is picked persists in the browser's `localStorage`
(`classValueOs.actingAsUserId`) and is what every capability check in the app (`RoleContext.can(module,
action)`, `RoleContext.isAdmin()`) reads. This is a deliberate, honest stand-in — the same "permissive until
something real exists" pattern already used for CPQ Config's and Pricing policy's access before this arc —
designed so wiring up real SSO later only means changing *how* the current user gets set (JIT-provisioned
from the identity provider on sign-in, instead of a manual pick), not touching any of the `can()`/`isAdmin()`
call sites that already depend on it. CPQ Config is the first (and so far only) page with real capability
gating wired in — see above; extending the same `RoleContext.can(...)` pattern to other modules as they get
built for real is the natural next step.

## SSO configuration

`sso-config.html`, a new Platform subpage, for IT admins to record connection details for the company's
identity provider (Entra ID / AD via ADFS, Okta, or similar — Supabase Auth supports SAML 2.0 against all
three) once the organization is ready to connect one. The form (IdP name, entity ID / issuer, SSO URL, X.509
certificate, and an `enabled` toggle) saves real values to a real table (`sso_config`, a singleton row, same
pattern as `cpq_pricing_policy`) — but it is **deliberately inert**: nothing anywhere in the app reads this
table to authenticate anyone, and the page says so explicitly. Enabling is blocked client-side until entity
ID, SSO URL, and certificate are all filled in, but even a successful "enable" has no effect yet.

This is intentional sequencing, not an oversight: real SSO needs a real identity provider to test against,
which didn't exist at the time this was built, so it's the one piece of the login story left for last. The
page itself lists what's still needed once a real IdP is available to test against: a real login screen that
redirects to the IdP and handles the SAML assertion, just-in-time provisioning into `app_users` on first
sign-in (replacing the manual "add user" flow in Roles & permissions), a session model tied to the SSO
identity (replacing the `localStorage` "acting as" picker), and rejecting sign-in for anyone not present in
the IdP directory so access always tracks AD/IdP membership — the hard security requirement this whole
feature was built toward.

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
   `cpq_products`, `quotes`, `quote_line_items`, `pricing_tiers`, `pricing_tier_rates`, `cpq_pricing_policy`,
   `roles`, `role_capabilities`, `app_users`, `user_roles`, `sso_config`), their constraints, starter Row
   Level Security policies, the CPQ product/add-on catalog, and the seeded roles/capabilities/users described
   under "Roles & permissions" above. It's safe to re-run if you ever need to.
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

Row Level Security is **on**, but every policy is still permissive (`using (true)`) at the database level —
anyone with the anon key can read and write every table. Roles & permissions (see above) now exists and
CPQ Config enforces its capability matrix in the UI, but that's app-level gating, not database-level: the
underlying Postgres policies aren't tied to a real signed-in identity yet, because there is no real login yet
(see "Roles & permissions" → the "acting as" switcher, and "SSO configuration"). Every policy in
`schema.sql` is written so tightening it later — swapping `using (true)` for a real `auth.uid()` check once
real SSO exists — is a small, targeted change per table rather than a rewrite.

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
