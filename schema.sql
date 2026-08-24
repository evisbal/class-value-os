-- Class Value OS — Demand Management schema
-- Run this once in your Supabase project's SQL editor (Project → SQL Editor → New query → paste → Run).
-- Safe to re-run: every statement is guarded with IF NOT EXISTS / OR REPLACE.

-- Note: gen_random_uuid() is built into Postgres core since v13 (Supabase runs
-- on newer than that), so no extension needs enabling for it.

-- ---------------------------------------------------------------------------
-- clients — "Demand is the only place a client record is born" (MODULE_SPECS.md).
-- CPQ, Plan Builder, Delivery and Engagement Management will all reference this
-- same client id once they're built, so every module points at one record.
-- ---------------------------------------------------------------------------
create table if not exists clients (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  segment      text not null check (segment in (
                 'Banking / Centralized Banking',
                 'Wholesale Lending / TPO',
                 'Distributed Retail Lending',
                 'Credit Union',
                 'Private Lending',
                 'Other'
               )),
  created_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- demand_scoring_weights — the transparent, portfolio-owner-maintained weights
-- behind the strategic fit score. Singleton row (id is always 1). Every input
-- that produces a demand's score stays visible on the demand itself — see
-- demands.score_* columns below — so a re-weight never makes old scores a
-- mystery number.
-- ---------------------------------------------------------------------------
create table if not exists demand_scoring_weights (
  id                       smallint primary key default 1 check (id = 1),
  w_volume_potential       numeric not null default 0.25,
  w_segment_fit            numeric not null default 0.20,
  w_integration_effort     numeric not null default 0.20, -- inverse: higher input score = less effort
  w_margin_potential       numeric not null default 0.20,
  w_competitive_position   numeric not null default 0.15,
  updated_at               timestamptz not null default now()
);
insert into demand_scoring_weights (id) values (1) on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- demands
-- ---------------------------------------------------------------------------
create table if not exists demands (
  id                        uuid primary key default gen_random_uuid(),
  demand_number             bigint generated always as identity,   -- backs the DMD-#### code
  client_id                 uuid not null references clients(id) on delete restrict,

  source                    text,        -- e.g. RFP, Referral, Inbound, Outbound, Existing client
  owner_name                text,        -- free text for now; becomes owner_user_id once Roles & permissions exists
  owner_user_id             uuid,        -- reserved for later — nullable until Supabase Auth is wired

  est_monthly_volume        integer,
  est_annual_value          numeric,
  requirement_summary       text,

  stage                     text not null default 'unscored' check (stage in (
                               'unscored','open','decision','converted','parked','rejected'
                             )),
  decision_reason           text,        -- required in the app when parking or rejecting; never a hard delete

  score_volume_potential     smallint check (score_volume_potential between 0 and 100),
  score_segment_fit          smallint check (score_segment_fit between 0 and 100),
  score_integration_effort   smallint check (score_integration_effort between 0 and 100),
  score_margin_potential     smallint check (score_margin_potential between 0 and 100),
  score_competitive_position smallint check (score_competitive_position between 0 and 100),
  score_overall               numeric,  -- computed client-side from the weights above and saved alongside the inputs

  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now()
);

create index if not exists idx_demands_client_id on demands(client_id);
create index if not exists idx_demands_stage on demands(stage);
create index if not exists idx_demands_created_at on demands(created_at desc);

-- ---------------------------------------------------------------------------
-- Decision routing + archive (added after the initial ship). A demand only
-- reaches 'decision' or 'converted' by a manual action in the app — there's
-- no CPQ backend yet to drive these automatically. Archiving is a visibility
-- flag, not a stage: it only ever hides a demand from the default list, never
-- deletes it, and is only ever set while a demand is 'rejected'.
-- Safe to re-run against an existing project — every add is IF NOT EXISTS.
-- ---------------------------------------------------------------------------
alter table demands add column if not exists decision_owner_type text check (decision_owner_type in ('internal','client'));
alter table demands add column if not exists decision_owner_name text;      -- internal teammate's name, or the client contact's name
alter table demands add column if not exists decision_client_contact text;  -- email/phone — only meaningful when decision_owner_type = 'client'
alter table demands add column if not exists decision_pending_note text;    -- what's actually being decided / followed up on
alter table demands add column if not exists decision_at timestamptz;
alter table demands add column if not exists converted_at timestamptz;
alter table demands add column if not exists archived boolean not null default false;
alter table demands add column if not exists archived_at timestamptz;

alter table demands drop constraint if exists chk_archived_only_when_rejected;
alter table demands add constraint chk_archived_only_when_rejected check (not archived or stage = 'rejected');

-- ---------------------------------------------------------------------------
-- demand_activity — the activity thread on a demand (notes + automatic stage
-- change entries). Kept append-only from the app's point of view.
-- ---------------------------------------------------------------------------
create table if not exists demand_activity (
  id           uuid primary key default gen_random_uuid(),
  demand_id    uuid not null references demands(id) on delete cascade,
  kind         text not null default 'note' check (kind in ('note','stage_change','system')),
  body         text not null,
  author_name  text,
  created_at   timestamptz not null default now()
);
create index if not exists idx_demand_activity_demand_id on demand_activity(demand_id);

-- ---------------------------------------------------------------------------
-- demand_attachments — metadata only for now (filename + note). Wiring these
-- to real files means adding a Supabase Storage bucket, which is a clean,
-- separate follow-up rather than something this table needs to anticipate.
-- ---------------------------------------------------------------------------
create table if not exists demand_attachments (
  id            uuid primary key default gen_random_uuid(),
  demand_id     uuid not null references demands(id) on delete cascade,
  file_name     text not null,
  note          text,
  storage_path  text, -- populated later once Supabase Storage is wired in
  uploaded_at   timestamptz not null default now()
);
create index if not exists idx_demand_attachments_demand_id on demand_attachments(demand_id);

-- ---------------------------------------------------------------------------
-- updated_at trigger for demands
-- ---------------------------------------------------------------------------
create or replace function set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_demands_updated_at on demands;
create trigger trg_demands_updated_at
  before update on demands
  for each row execute function set_updated_at();

-- ---------------------------------------------------------------------------
-- Row Level Security
--
-- Roles & permissions (who can see/do what) hasn't been designed yet — that's
-- a deliberate later step. Until then, RLS is ON (so nothing is ever silently
-- wide open by accident) but every policy is permissive: any request using
-- your project's anon key can read and write. This is fine for one internal
-- team building against a private repo, and every policy below is written so
-- it's a one-line change to tighten later (e.g. swap `using (true)` for
-- `using (auth.uid() = owner_user_id)` once users log in).
-- ---------------------------------------------------------------------------
alter table clients enable row level security;
alter table demand_scoring_weights enable row level security;
alter table demands enable row level security;
alter table demand_activity enable row level security;
alter table demand_attachments enable row level security;

drop policy if exists "permissive_all_clients" on clients;
create policy "permissive_all_clients" on clients for all using (true) with check (true);

drop policy if exists "permissive_all_weights" on demand_scoring_weights;
create policy "permissive_all_weights" on demand_scoring_weights for all using (true) with check (true);

drop policy if exists "permissive_all_demands" on demands;
create policy "permissive_all_demands" on demands for all using (true) with check (true);

drop policy if exists "permissive_all_activity" on demand_activity;
create policy "permissive_all_activity" on demand_activity for all using (true) with check (true);

drop policy if exists "permissive_all_attachments" on demand_attachments;
create policy "permissive_all_attachments" on demand_attachments for all using (true) with check (true);

-- ---------------------------------------------------------------------------
-- Optional: a couple of example rows so the module isn't empty on first load.
-- Safe to delete from the Supabase Table Editor at any time.
-- ---------------------------------------------------------------------------
do $$
declare
  c1 uuid;
  c2 uuid;
begin
  if not exists (select 1 from clients where name = 'Cascade Credit Union') then
    insert into clients (name, segment) values ('Cascade Credit Union', 'Credit Union') returning id into c1;
    insert into demands (client_id, source, owner_name, est_monthly_volume, est_annual_value, requirement_summary, stage)
      values (c1, 'Referral', 'Dana Mercer', 210, 600000, 'Regional credit union evaluating AMC consolidation for conventional originations.', 'unscored');
  end if;
  if not exists (select 1 from clients where name = 'Anchor Mutual') then
    insert into clients (name, segment) values ('Anchor Mutual', 'Banking / Centralized Banking') returning id into c2;
    insert into demands (client_id, source, owner_name, est_monthly_volume, est_annual_value, requirement_summary, stage,
      score_volume_potential, score_segment_fit, score_integration_effort, score_margin_potential, score_competitive_position)
      values (c2, 'Inbound', 'Dana Mercer', 390, 1200000, 'Centralized bank looking to replace an incumbent AMC after a service escalation.', 'open',
      70, 65, 55, 60, 58);
  end if;
end $$;

-- =============================================================================
-- Value CPQ — Phase 1 (Client & demand + Configure) and Phase 2 (Rules check)
-- are real. See CPQ_requirements_scope.md for the full module plan. Pricing &
-- terms and Quote & approvals stay static mockups until their own phases;
-- nothing here needs to anticipate them beyond the `status` values already
-- reserved below. Safe to re-run against an existing project — every add is
-- IF NOT EXISTS.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- cpq_products — the product/add-on catalog a quote's line items are built
-- from. `eligible_segments` mirrors clients.segment's values; null/empty means
-- eligible for every segment — re-checked live on the Rules check step (not
-- just enforced in Configure's UI), so a later catalog change never leaves a
-- stale, silently-ineligible selection on an existing quote. `data_ready`
-- backs Rules check's "product data readiness" row — a simple boolean today;
-- if the real requirement ever needs more than pass/fail it can grow a note
-- column the same way `requires_note` already works.
-- ---------------------------------------------------------------------------
create table if not exists cpq_products (
  id                 uuid primary key default gen_random_uuid(),
  category           text not null check (category in ('product','addon')),
  name               text not null,
  description        text,
  unit_price         numeric not null default 0,
  unit_label         text not null default 'order',  -- 'order' = priced per monthly order volume, 'month' = flat monthly fee
  eligible_segments  text[],                          -- null/empty = eligible for every segment
  requires_note      text,                            -- shown on the card when ineligible, or as a caveat when eligible
  sort_order         int not null default 0,
  active             boolean not null default true,
  created_at         timestamptz not null default now()
);
alter table cpq_products add column if not exists data_ready boolean not null default true;
create index if not exists idx_cpq_products_category on cpq_products(category);

-- ---------------------------------------------------------------------------
-- family — added for CPQ Config (the admin catalog page at cpq-config.html).
-- `category` ('product'/'addon') still drives Configure/Rules check's actual
-- mechanics (per-order volume vs. flat fee, addon-caveat surfacing); `family`
-- is a display/grouping taxonomy layered on top of it, matching
-- classvaluation.com's real two-tier "Our Products" structure (Appraisal
-- Offerings / Alternative Valuations) plus a third bucket for add-ons &
-- service levels. Every family maps to exactly one category (enforced in the
-- CPQ Config UI, not here, since Postgres check constraints can't easily
-- cross-reference two columns without a trigger for a case this simple).
-- Existing rows default to 'appraisal_offering' on this ALTER (Postgres
-- backfills the column default into existing rows); the two UPDATEs below
-- correct that default for the rows where it's wrong.
-- ---------------------------------------------------------------------------
alter table cpq_products add column if not exists family text not null default 'appraisal_offering'
  check (family in ('appraisal_offering','alternative_valuation','addon_solution'));
update cpq_products set family = 'addon_solution' where category = 'addon' and family <> 'addon_solution';
update cpq_products set family = 'alternative_valuation' where name in ('AVM + PCR','Class Evaluation') and family = 'appraisal_offering';

-- ---------------------------------------------------------------------------
-- quotes — one row per quote attempt against a Converted demand. `status`
-- values beyond 'draft' are reserved for the approval-routing phase (Quote &
-- approvals) and aren't set by the app yet. `guided_answers` holds the
-- Client & demand step's questionnaire; it's informational context today —
-- it doesn't yet drive Configure eligibility, which instead uses the
-- demand's real client segment (already-live data, not a re-asked question).
-- ---------------------------------------------------------------------------
create table if not exists quotes (
  id              uuid primary key default gen_random_uuid(),
  quote_number    bigint generated always as identity,  -- backs the Q-#### code
  demand_id       uuid not null references demands(id) on delete restrict,
  client_id       uuid not null references clients(id) on delete restrict,
  status          text not null default 'draft' check (status in (
                    'draft','needs_pricing_approval','approved','locked'
                  )),
  version         int not null default 1,
  guided_answers  jsonb not null default '{}'::jsonb,
  owner_name      text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists idx_quotes_demand_id on quotes(demand_id);

drop trigger if exists trg_quotes_updated_at on quotes;
create trigger trg_quotes_updated_at
  before update on quotes
  for each row execute function set_updated_at();

-- ---------------------------------------------------------------------------
-- quote_line_items — one row per product/add-on ever touched on a quote.
-- `monthly_volume` only applies to 'order'-priced products; addons are flat
-- monthly fees. `unit_price_snapshot` freezes the catalog price at selection
-- time so a later catalog price change never silently rewrites an existing
-- quote's numbers.
-- ---------------------------------------------------------------------------
create table if not exists quote_line_items (
  id                    uuid primary key default gen_random_uuid(),
  quote_id              uuid not null references quotes(id) on delete cascade,
  product_id            uuid not null references cpq_products(id) on delete restrict,
  selected              boolean not null default false,
  monthly_volume        numeric,
  unit_price_snapshot   numeric not null,
  updated_at            timestamptz not null default now(),
  unique (quote_id, product_id)
);
create index if not exists idx_quote_line_items_quote_id on quote_line_items(quote_id);

drop trigger if exists trg_quote_line_items_updated_at on quote_line_items;
create trigger trg_quote_line_items_updated_at
  before update on quote_line_items
  for each row execute function set_updated_at();

-- ---------------------------------------------------------------------------
-- pricing_tiers + pricing_tier_rates — volume-based tiered pricing, added
-- after CPQ Config shipped. A tier is a per-product RATE CARD, not a blanket
-- discount: pricing_tier_rates holds a per-(tier, product) override price; a
-- product with no override row for a given tier simply falls back to
-- cpq_products.unit_price. Admin overhead only grows with how many prices
-- actually differ per tier, not the full tier x catalog matrix — most
-- products are expected to have zero overrides at most tiers.
--
-- Volume ranges (min_volume/max_volume) are an informed placeholder (see
-- CPQ_requirements_scope.md), not real historical order data — swap them
-- for real breakpoints once historical volume-per-client data exists.
--
-- Applying a tier is a client-level business rule, not a quote-level one:
-- clients.pricing_tier_id is the sticky assignment a rep sets from CPQ's
-- Client & demand tab; quotes.pricing_tier_id records what was in effect for
-- that specific quote at the time. The actual frozen price still lives where
-- it always has — quote_line_items.unit_price_snapshot — written using the
-- tier-adjusted price at the moment an item was selected, so a client's tier
-- changing later never rewrites an already-quoted price. This has no
-- connection to invoicing or billing; its only output is what a quote shows.
-- ---------------------------------------------------------------------------
create table if not exists pricing_tiers (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  min_volume   int not null default 0,
  max_volume   int,                       -- null = open-ended (top tier)
  description  text,
  sort_order   int not null default 0,
  active       boolean not null default true,
  created_at   timestamptz not null default now()
);

create table if not exists pricing_tier_rates (
  id              uuid primary key default gen_random_uuid(),
  tier_id         uuid not null references pricing_tiers(id) on delete cascade,
  product_id      uuid not null references cpq_products(id) on delete cascade,
  override_price  numeric not null,
  created_at      timestamptz not null default now(),
  unique (tier_id, product_id)
);
create index if not exists idx_pricing_tier_rates_tier_id on pricing_tier_rates(tier_id);

alter table clients add column if not exists pricing_tier_id uuid references pricing_tiers(id) on delete set null;
alter table quotes add column if not exists pricing_tier_id uuid references pricing_tiers(id) on delete set null;

-- ---------------------------------------------------------------------------
-- Row Level Security — same permissive-until-Roles-&-Permissions-exists
-- pattern as every other table in this schema (see the note above).
-- ---------------------------------------------------------------------------
alter table cpq_products enable row level security;
alter table quotes enable row level security;
alter table quote_line_items enable row level security;
alter table pricing_tiers enable row level security;
alter table pricing_tier_rates enable row level security;

drop policy if exists "permissive_all_cpq_products" on cpq_products;
create policy "permissive_all_cpq_products" on cpq_products for all using (true) with check (true);

drop policy if exists "permissive_all_quotes" on quotes;
create policy "permissive_all_quotes" on quotes for all using (true) with check (true);

drop policy if exists "permissive_all_quote_line_items" on quote_line_items;
create policy "permissive_all_quote_line_items" on quote_line_items for all using (true) with check (true);

drop policy if exists "permissive_all_pricing_tiers" on pricing_tiers;
create policy "permissive_all_pricing_tiers" on pricing_tiers for all using (true) with check (true);

drop policy if exists "permissive_all_pricing_tier_rates" on pricing_tier_rates;
create policy "permissive_all_pricing_tier_rates" on pricing_tier_rates for all using (true) with check (true);

-- ---------------------------------------------------------------------------
-- Seed the 3 tiers (informed placeholder ranges — see the comment above)
-- plus a few illustrative rate-card overrides on the highest-volume real
-- products, so the feature isn't empty on first load. Most products
-- intentionally have no override row at any tier (falls back to the catalog
-- base price) — only add rows here for prices that would actually differ.
-- ---------------------------------------------------------------------------
insert into pricing_tiers (name, min_volume, max_volume, description, sort_order)
select * from (values
  ('Standard', 0, 149, 'Community banks, credit unions, private lenders.', 1),
  ('Preferred', 150, 349, 'Regional banks, larger credit unions, TPO shops.', 2),
  ('Enterprise', 350, null::int, 'Large national originators, big TPO aggregators.', 3)
) as v(name, min_volume, max_volume, description, sort_order)
where not exists (select 1 from pricing_tiers where pricing_tiers.name = v.name);

insert into pricing_tier_rates (tier_id, product_id, override_price)
select t.id, p.id, r.override_price
from (values
  ('Preferred', 'Traditional Appraisal', 495),
  ('Enterprise', 'Traditional Appraisal', 450),
  ('Preferred', 'Hybrid Appraisal', 365),
  ('Enterprise', 'Hybrid Appraisal', 335),
  ('Preferred', 'AVM + PCR', 85),
  ('Enterprise', 'AVM + PCR', 75)
) as r(tier_name, product_name, override_price)
join pricing_tiers t on t.name = r.tier_name
join cpq_products p on p.name = r.product_name
where not exists (
  select 1 from pricing_tier_rates x where x.tier_id = t.id and x.product_id = p.id
);

-- ---------------------------------------------------------------------------
-- Seed catalog — revised against classvaluation.com's real "Our Products"
-- menu (Appraisal Offerings + Alternative Valuations) and its Solutions pages,
-- via the CPQ Config buildout. The original seed had 6 real products plus 3
-- fabricated add-ons (Rush turn-time tier, Guaranteed Pricing with an
-- invented "12mo term", Order API + webhooks) and was missing 6 real
-- products. This version: keeps the 6 real products (2 description tweaks
-- for accuracy), adds the 6 missing real ones, drops the fabricated add-ons
-- in favor of Class Valuation's 2 actual "Solutions" that behave like
-- catalog line items (Guaranteed Pricing, CVUE) — both custom-priced per
-- account (unit_price 0, unit_label 'account'), which CPQ Config's pricing
-- basis field and cpq_module.js's "Custom-priced" display both handle
-- natively. Pay Later (a borrower payment-plan option) isn't a catalog line
-- item — it belongs to a future Pricing & terms "payment terms" field.
--
-- Only new installs get this corrected list — this insert is keyed by name
-- and only fires `where not exists`, so an existing project's old seeded
-- rows (including the fabricated add-ons) are left alone rather than
-- silently rewritten. Review and correct or deactivate them from CPQ Config
-- (cpq-config.html) if you already ran the original schema. Safe to edit or
-- add to from CPQ Config, or the Supabase Table Editor, at any time —
-- nothing in the app hardcodes these rows.
-- ---------------------------------------------------------------------------
insert into cpq_products (category, family, name, description, unit_price, unit_label, eligible_segments, requires_note, sort_order)
select * from (values
  -- Appraisal Offerings
  ('product', 'appraisal_offering', 'Traditional Appraisal', 'Full interior/exterior appraisal for conventional, FHA, condo, multi-family and land loans, with nationwide coverage and integrated quality review.', 545, 'order', null::text[], null, 1),
  ('product', 'appraisal_offering', 'Digital Appraisal', 'Digital-first appraisal using 3D property data capture and AI-assisted desktop review for faster, more consistent turn times.', 475, 'order', null::text[], null, 2),
  ('product', 'appraisal_offering', 'Hybrid Appraisal', 'Appraiser desktop review paired with a third-party property data collection visit — GSE-eligible for Fannie Mae and Freddie Mac.', 395, 'order', null::text[], null, 3),
  ('product', 'appraisal_offering', 'Inspection-Based Waiver', 'Data-collection-only appraisal waiver — no valuation required, typically a 2–3 day turn.', 145, 'order', null::text[], null, 4),
  ('product', 'appraisal_offering', 'Property Data Advantage', 'Flexible property-data collection and report supporting both Fannie Mae Value Acceptance + Property Data and Freddie Mac ACE+ PDR in one order.', 165, 'order', null::text[], null, 5),
  -- Alternative Valuations
  ('product', 'alternative_valuation', 'AVM', 'Automated valuation model — a fast baseline market value estimate from property databases and sales history.', 35, 'order', null::text[], null, 6),
  ('product', 'alternative_valuation', 'BPO', 'Broker price opinion — a licensed local broker’s comparative market analysis, a lower-cost alternative to a full appraisal.', 125, 'order', null::text[], null, 7),
  ('product', 'alternative_valuation', 'AVM + PCR', 'Automated valuation combined with a property condition report and analyst review.', 95, 'order',
    array['Credit Union','Private Lending'], 'Requires alternative-valuation eligibility — not enabled for this segment yet.', 8),
  ('product', 'alternative_valuation', 'Class Evaluation', 'Analyst-assisted AVM for home equity lending — comparable-sales report with confidence scoring and optional inspection.', 210, 'order', null::text[], null, 9),
  ('product', 'alternative_valuation', 'Limited Desktop', 'Appraiser desktop analysis with a physical inspection — the escalation option when an AVM’s confidence score isn’t enough.', 275, 'order', null::text[], null, 10),
  ('product', 'alternative_valuation', 'Borrower-Led Inspection', 'Self-guided digital inspection completed remotely, with automated fraud checks — fulfills GSE final-inspection requirements without a site visit.', 65, 'order', null::text[], null, 11),
  ('product', 'alternative_valuation', 'Class Valuation Analysis', 'USPAP-compliant third-party review of an existing appraisal by a state-licensed appraiser, to flag errors before funding.', 85, 'order', null::text[], null, 12),
  -- Add-ons & service levels (Class Valuation's actual "Solutions" that behave like a selectable line item)
  ('addon', 'addon_solution', 'Guaranteed Pricing', 'Locks the appraisal fee at time of order under a schedule built around your volume, geography and property profile.', 0, 'account', null::text[], 'Custom-priced per account — contact Pricing & Finance for a schedule.', 1),
  ('addon', 'addon_solution', 'CVUE', 'Underwriting & appraisal assurance program — Class assumes repurchase risk and completes the review on eligible appraisals.', 0, 'account', null::text[], 'Program eligibility and pricing set per lender — contact Pricing & Finance.', 2)
) as v(category, family, name, description, unit_price, unit_label, eligible_segments, requires_note, sort_order)
where not exists (select 1 from cpq_products where cpq_products.name = v.name);

-- ---------------------------------------------------------------------------
-- Pricing & terms (tab 3) — unit_cost + quote-level commercial terms.
--
-- unit_cost lives on cpq_products, right next to unit_price, because cost to
-- deliver varies by product (a licensed-appraiser dispatch costs far more
-- than an automated AVM) and doesn't change with the tier a client is on —
-- only the selling price does. Margin is therefore computed per line as
-- (effective price − unit_cost) / effective price, using whatever price is
-- actually in effect (tier override if any, minus the quote's ad hoc
-- discount), then blended across the quote weighted by volume. This is the
-- standard CPQ pattern (a "cost" field alongside list price on the price
-- book entry) rather than a single client- or bundle-level margin number,
-- which can't account for a mixed cart of high- and low-cost products.
--
-- unit_cost is nullable on purpose: a null cost means "not yet costed in the
-- catalog" (both add-ons ship this way — they're custom-priced per account,
-- so there's no single cost to seed). cpq_module.js treats a selected line
-- with no cost data as margin-unknown, not margin-zero, and — like every
-- other honesty gap in this app — flags it rather than silently assuming
-- the deal is fine. Editable from CPQ Config alongside unit_price, same
-- open-to-all-roles-for-now access pattern.
--
-- The 42% floor itself, and the 0% auto-approve discount cap below, are
-- fixed constants in cpq_module.js for now (not a table) — same "seeded
-- until the real Sales-VP configurator exists" placeholder pattern already
-- used for pricing tier volume ranges. Move them here if/when that
-- configurator gets built.
-- ---------------------------------------------------------------------------
alter table cpq_products add column if not exists unit_cost numeric;  -- null = not yet costed

update cpq_products set unit_cost = v.unit_cost
from (values
  ('Traditional Appraisal', 325),      -- licensed-appraiser dispatch, full field inspection — highest cost in the catalog
  ('Digital Appraisal', 275),          -- appraiser desktop review + 3D capture logistics
  ('Hybrid Appraisal', 230),           -- appraiser desktop review + 3rd-party data-collection visit
  ('Inspection-Based Waiver', 70),     -- vendor data-collection visit only, no valuation
  ('Property Data Advantage', 78),     -- vendor data-collection visit, dual GSE program support
  ('AVM', 6),                          -- fully automated, data licensing + compute only
  ('BPO', 70),                         -- flat fee paid to a local broker
  ('AVM + PCR', 42),                   -- automated valuation + vendor property condition report + analyst review
  ('Class Evaluation', 95),            -- analyst-assisted review, optional inspection
  ('Limited Desktop', 165),            -- appraiser desktop analysis + vendor physical inspection
  ('Borrower-Led Inspection', 22),     -- self-guided digital flow, automated fraud checks — mostly tech/ops cost
  ('Class Valuation Analysis', 45)     -- licensed-appraiser review of an existing report (lighter than a full appraisal)
  -- Guaranteed Pricing and CVUE intentionally excluded — custom-priced per
  -- account/lender, so there's no single catalog cost to seed. Cost these
  -- from CPQ Config only once a specific account's economics are known.
) as v(name, unit_cost)
where cpq_products.name = v.name and cpq_products.unit_cost is null;

-- Commercial terms captured per quote. commercial_structure is informational
-- only (shown on the quote/PDF, doesn't change pricing math — actual pricing
-- still comes from Configure + any applied tier + this quote's discount_pct)
-- since Pricing tiers already covers the "different rate per volume band"
-- mechanic this field originally implied in the design mock. discount_pct is
-- a single blended ad hoc discount applied on top of whatever price is
-- already in effect (catalog or tier-adjusted) — distinct from, and stacked
-- on top of, any pricing tier. status already had 'needs_pricing_approval'
-- reserved (see the quotes table above) — cpq_module.js flips a quote into
-- and out of that status live as discount/margin/cost-data conditions
-- change, so no separate approval-flag column is needed.
alter table quotes add column if not exists commercial_structure text
  check (commercial_structure in ('tiered_volume','annual_commitment','pure_consumption'));
alter table quotes add column if not exists discount_pct numeric not null default 0;
alter table quotes add column if not exists contract_term_months int;
alter table quotes add column if not exists payment_terms text;
alter table quotes add column if not exists pay_later_enabled boolean not null default false;
alter table quotes add column if not exists volume_commitment numeric;
alter table quotes add column if not exists price_review_cadence text;

-- ---------------------------------------------------------------------------
-- cpq_pricing_policy — makes the discount auto-approve cap and margin floor
-- real, editable settings instead of the code constants they started as.
-- Singleton row, same pattern as demand_scoring_weights above (id fixed to 1
-- via the check constraint, so there's only ever one row to read/write).
-- Editable from CPQ Config's "Pricing policy" section, same open-to-all-
-- roles-for-now access pattern as the rest of CPQ Config — gate this to a
-- real Sales VP role once Roles & permissions exists, per the original
-- phasing note. cpq_module.js reads this table on load and falls back to
-- 0% / 42% if the row is somehow missing.
-- ---------------------------------------------------------------------------
create table if not exists cpq_pricing_policy (
  id                              smallint primary key default 1 check (id = 1),
  discount_auto_approve_cap_pct  numeric not null default 0,
  margin_floor_pct               numeric not null default 42,
  updated_at                     timestamptz not null default now()
);
insert into cpq_pricing_policy (id) values (1) on conflict (id) do nothing;

alter table cpq_pricing_policy enable row level security;
drop policy if exists "permissive_all_cpq_pricing_policy" on cpq_pricing_policy;
create policy "permissive_all_cpq_pricing_policy" on cpq_pricing_policy for all using (true) with check (true);

-- ---------------------------------------------------------------------------
-- Roles & permissions
--
-- Real data model, not yet real security: RLS on every table below is the
-- same permissive-until-a-real-identity-layer-exists pattern used everywhere
-- else in this schema (see the note at the top of the file). What's real
-- here is the DATA — roles, their per-module capabilities, the user
-- directory, and role assignments — and the app-level capability checks that
-- read it (see role_context.js). True enforcement needs actual
-- authentication (SSO), which is intentionally sequenced last since it can't
-- be tested without a real identity provider to connect to. Until then,
-- "who's using the app" is a client-side role-context switcher standing in
-- for login — the same honest, provisional pattern as every other
-- open-access banner in this app.
--
-- app_users.active mirrors what real SSO/JIT provisioning will eventually
-- drive: a user deactivated here (or, later, deprovisioned in AD) loses
-- access. No self-serve sign-up path exists or is planned — accounts are
-- only ever created by an admin here, or later, automatically on a
-- successful SSO login.
-- ---------------------------------------------------------------------------
create table if not exists roles (
  id            uuid primary key default gen_random_uuid(),
  name          text not null unique,
  description   text,
  -- Platform admin roles can manage Roles & permissions and SSO configuration
  -- themselves — deliberately a separate flag from any single module
  -- capability, so "who can approve deals" and "who can grant access" stay
  -- two different questions, per least-privilege.
  is_admin      boolean not null default false,
  sort_order    int not null default 0,
  active        boolean not null default true,
  created_at    timestamptz not null default now()
);

-- One row per (role, module) — module ids mirror this app's nav ids (demand,
-- cpq, cpq-config, plan, studio, delivery, reporting, engagement, roles,
-- sso). A module with no row for a role means no access at all, not
-- "everything off" needing to be spelled out — keeps a brand-new role's
-- footprint at zero until someone deliberately grants it something.
create table if not exists role_capabilities (
  id            uuid primary key default gen_random_uuid(),
  role_id       uuid not null references roles(id) on delete cascade,
  module        text not null,
  can_view      boolean not null default false,
  can_create    boolean not null default false,
  can_edit      boolean not null default false,
  can_approve   boolean not null default false,
  can_export    boolean not null default false,
  unique (role_id, module)
);
create index if not exists idx_role_capabilities_role_id on role_capabilities(role_id);

create table if not exists app_users (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  email         text not null unique,
  active        boolean not null default true,
  created_at    timestamptz not null default now()
);

create table if not exists user_roles (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references app_users(id) on delete cascade,
  role_id       uuid not null references roles(id) on delete cascade,
  unique (user_id, role_id)
);
create index if not exists idx_user_roles_user_id on user_roles(user_id);

alter table roles enable row level security;
alter table role_capabilities enable row level security;
alter table app_users enable row level security;
alter table user_roles enable row level security;

drop policy if exists "permissive_all_roles" on roles;
create policy "permissive_all_roles" on roles for all using (true) with check (true);
drop policy if exists "permissive_all_role_capabilities" on role_capabilities;
create policy "permissive_all_role_capabilities" on role_capabilities for all using (true) with check (true);
drop policy if exists "permissive_all_app_users" on app_users;
create policy "permissive_all_app_users" on app_users for all using (true) with check (true);
drop policy if exists "permissive_all_user_roles" on user_roles;
create policy "permissive_all_user_roles" on user_roles for all using (true) with check (true);

-- Seed the 9 roles agreed for this app (reconciled against both the
-- Roles & permissions mockup's original 6 and Quote & approvals' 4-stage
-- chain, which named two approver roles — Deal desk, Operations capacity —
-- that had no home in the original 6). See CPQ_requirements_scope.md.
insert into roles (name, description, is_admin, sort_order)
select * from (values
  ('Account executive', 'Builds and submits quotes — the primary day-to-day CPQ user.', false, 1),
  ('Solutions engineer', 'Supports technical configuration; not an approver.', false, 2),
  ('Deal desk / Sales ops', 'First-line approver on eligibility exceptions and deal-shape review.', false, 3),
  ('Pricing & finance', 'Owns discount/margin approval authority, pricing policy, and unit cost.', false, 4),
  ('Implementation PM', 'Owns delivery planning and operations-capacity approval.', false, 5),
  ('VP Sales', 'Final countersign on every approved quote, regardless of trigger.', false, 6),
  ('Engagement manager', 'Owns the client relationship post-sale.', false, 7),
  ('Executive / portfolio', 'Cross-org visibility and reporting; not a day-to-day approver.', false, 8),
  ('Platform admin', 'Owns Roles & permissions and SSO configuration.', true, 9)
) as v(name, description, is_admin, sort_order)
where not exists (select 1 from roles where roles.name = v.name);

-- Seed a starting capability matrix per role. Editable afterward from the
-- real Roles & permissions page — this is a sensible default, not a fixed
-- rule.
insert into role_capabilities (role_id, module, can_view, can_create, can_edit, can_approve, can_export)
select r.id, v.module, v.can_view, v.can_create, v.can_edit, v.can_approve, v.can_export
from (values
  ('Account executive',      'demand',     true,  false, false, false, false),
  ('Account executive',      'cpq',        true,  true,  true,  false, false),
  ('Account executive',      'plan',       true,  false, false, false, false),
  ('Account executive',      'reporting',  true,  false, false, false, false),

  ('Solutions engineer',     'demand',     true,  false, false, false, false),
  ('Solutions engineer',     'cpq',        true,  false, true,  false, false),
  ('Solutions engineer',     'plan',       true,  false, true,  false, false),
  ('Solutions engineer',     'studio',     true,  false, false, false, false),

  ('Deal desk / Sales ops',  'cpq',        true,  false, true,  true,  false),
  ('Deal desk / Sales ops',  'cpq-config', true,  false, false, false, false),
  ('Deal desk / Sales ops',  'reporting',  true,  false, false, false, false),

  ('Pricing & finance',      'cpq',        true,  false, false, true,  false),
  ('Pricing & finance',      'cpq-config', true,  false, true,  true,  false),
  ('Pricing & finance',      'reporting',  true,  false, false, false, true),

  ('Implementation PM',      'plan',       true,  false, true,  false, false),
  ('Implementation PM',      'studio',     true,  false, true,  false, false),
  ('Implementation PM',      'delivery',   true,  false, true,  true,  false),
  ('Implementation PM',      'reporting',  true,  false, false, false, false),

  ('VP Sales',                'cpq',        true, false, false, true,  false),
  ('VP Sales',                'reporting',  true, false, false, false, true),
  ('VP Sales',                'engagement', true, false, false, false, false),

  ('Engagement manager',     'engagement', true,  true,  true,  false, false),
  ('Engagement manager',     'demand',     true,  false, false, false, false),
  ('Engagement manager',     'cpq',        true,  false, false, false, false),
  ('Engagement manager',     'reporting',  true,  false, false, false, false),

  ('Executive / portfolio',  'reporting',  true,  false, false, false, true),
  ('Executive / portfolio',  'demand',     true,  false, false, false, false),
  ('Executive / portfolio',  'cpq',        true,  false, false, false, false),
  ('Executive / portfolio',  'delivery',   true,  false, false, false, false),
  ('Executive / portfolio',  'engagement', true,  false, false, false, false),

  ('Platform admin',         'roles',      true,  true,  true,  true,  true),
  ('Platform admin',         'sso',        true,  true,  true,  false, false)
) as v(role_name, module, can_view, can_create, can_edit, can_approve, can_export)
join roles r on r.name = v.role_name
where not exists (
  select 1 from role_capabilities x where x.role_id = r.id and x.module = v.module
);

-- A handful of illustrative users so the role-context switcher and the Roles
-- & permissions page aren't empty on first load. Real accounts will come
-- from SSO/JIT provisioning once that's built — these are seed placeholders
-- only, matching the "informed placeholder pending real data" pattern used
-- for pricing tier volume ranges and the discount cap/margin floor.
-- Jordan Reyes added alongside the original 4 (see the 2026-08-21 Integration
-- Studio work) — none of the original seed users held the Implementation PM
-- role, which is Integration Studio's actual view+edit+export owner, leaving
-- no seeded acting-as option that could edit it.
insert into app_users (name, email)
select * from (values
  ('Dana Mercer', 'dana.mercer@classvaluation.com'),
  ('Ray Tolbert', 'ray.tolbert@classvaluation.com'),
  ('Priya Anand', 'priya.anand@classvaluation.com'),
  ('Marcus Webb', 'marcus.webb@classvaluation.com'),
  ('Jordan Reyes', 'jordan.reyes@classvaluation.com')
) as v(name, email)
where not exists (select 1 from app_users where app_users.email = v.email);

insert into user_roles (user_id, role_id)
select u.id, r.id from app_users u, roles r
where (u.email, r.name) in (
  ('dana.mercer@classvaluation.com', 'Solutions engineer'),
  ('ray.tolbert@classvaluation.com', 'Account executive'),
  ('priya.anand@classvaluation.com', 'Pricing & finance'),
  ('marcus.webb@classvaluation.com', 'Platform admin'),
  ('jordan.reyes@classvaluation.com', 'Implementation PM')
)
and not exists (
  select 1 from user_roles x where x.user_id = u.id and x.role_id = r.id
);

-- ---------------------------------------------------------------------------
-- sso_config — placeholder for a real SAML SSO connection (Supabase Auth
-- supports SAML 2.0, which works with Entra ID/AD via ADFS, Okta, and other
-- enterprise IdPs). Singleton row, same pattern as cpq_pricing_policy above.
-- Deliberately inert: `enabled` stays false and nothing reads this table to
-- actually authenticate anyone yet — real SSO wiring is sequenced last,
-- since it needs a real identity provider to test against, which this
-- project doesn't have yet. This just gives the eventual IT admin somewhere
-- real to paste the connection details when that time comes, instead of a
-- rebuild.
-- ---------------------------------------------------------------------------
create table if not exists sso_config (
  id            smallint primary key default 1 check (id = 1),
  enabled       boolean not null default false,
  idp_name      text,
  entity_id     text,
  sso_url       text,
  certificate   text,
  updated_at    timestamptz not null default now()
);
insert into sso_config (id) values (1) on conflict (id) do nothing;

alter table sso_config enable row level security;
drop policy if exists "permissive_all_sso_config" on sso_config;
create policy "permissive_all_sso_config" on sso_config for all using (true) with check (true);

-- =============================================================================
-- Integration Studio (Module 04) — Task Library + per-client task instances.
-- See MODULE_SPECS.md for the original design (Standard Offering Library,
-- Custom Configuration Canvas, Effort Roll-up, JIRA Mapping, Document
-- Generation) and the 2026-08-21 decision to unify Standard/Custom into one
-- configurable task library rather than two disconnected lists: every task
-- template can be eligible for the OOO section, the Custom section, or both.
-- A client's task set can freely mix OOO and Custom items (confirmed
-- 2026-08-21) — offering_type marks how each task entered the list, not a
-- mode the whole client is locked into. Safe to re-run — every add is
-- IF NOT EXISTS.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- integration_task_templates — the configurable library behind Integration
-- Studio, admin-curated (Task Library screen). Mirrors the cpq_products
-- catalog-vs-line-item pattern already used by CPQ: templates are edited
-- centrally, but a client's own tasks (below) are independent copies, so a
-- later template edit never rewrites a client's already-committed scope.
-- ---------------------------------------------------------------------------
create table if not exists integration_task_templates (
  id                uuid primary key default gen_random_uuid(),
  title             text not null,
  description       text,
  phase             text,              -- free-text grouping, e.g. Discovery, Mapping, Testing, Go-live
  estimated_weeks   numeric,           -- effort estimate — same unit Plan Builder's timeline already uses
  eligible_ooo      boolean not null default true,   -- shows up as a selectable item in the Standard Offering Library
  eligible_custom   boolean not null default true,   -- shows up as a startable item in the Custom Configuration Canvas
  sort_order        int not null default 0,
  active            boolean not null default true,
  created_at        timestamptz not null default now()
);
create index if not exists idx_itt_active on integration_task_templates(active);
-- RLS enabled immediately after creation (not batched further down) so the
-- Supabase SQL editor's "creates a table without enabling RLS" check never
-- flags it — same permissive-until-Roles-&-Permissions-exists pattern as
-- every other table in this schema.
alter table integration_task_templates enable row level security;
drop policy if exists "permissive_all_integration_task_templates" on integration_task_templates;
create policy "permissive_all_integration_task_templates" on integration_task_templates for all using (true) with check (true);

-- ---------------------------------------------------------------------------
-- client_integration_tasks — one row per task actually in play for a given
-- client's onboarding. Created either by selecting a template (OOO, or a
-- Custom item started from the library) or from scratch (pure Custom
-- requirement) — template_id is kept only as a provenance pointer, never a
-- live reference the UI re-reads from. The Custom-only fields are nullable
-- and only meaningful when offering_type = 'custom', per the Custom
-- Configuration Canvas fields in MODULE_SPECS.md. jira_key/jira_pushed_at
-- are set once exported/pushed and never written back to by anything JIRA
-- returns later — Studio stays the system of record for intent, JIRA for
-- execution (MODULE_SPECS.md's explicit one-directional design principle;
-- drift, if it ever needs surfacing, is a read-only comparison, not a sync).
-- ---------------------------------------------------------------------------
create table if not exists client_integration_tasks (
  id                    uuid primary key default gen_random_uuid(),
  client_id             uuid not null references clients(id) on delete cascade,
  template_id           uuid references integration_task_templates(id) on delete set null,
  offering_type         text not null check (offering_type in ('ooo','custom')),
  title                 text not null,
  description           text,
  phase                 text,
  estimated_weeks       numeric,
  status                text not null default 'not_started' check (status in ('not_started','in_progress','blocked','done')),
  systems_touched       text,
  acceptance_criteria   text,
  confidence            text check (confidence in ('high','medium','low')),
  client_dependency     text,
  jira_key              text,
  jira_pushed_at        timestamptz,
  sort_order            int not null default 0,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
create index if not exists idx_cit_client_id on client_integration_tasks(client_id);

drop trigger if exists trg_client_integration_tasks_updated_at on client_integration_tasks;
create trigger trg_client_integration_tasks_updated_at
  before update on client_integration_tasks
  for each row execute function set_updated_at();

alter table client_integration_tasks enable row level security;
drop policy if exists "permissive_all_client_integration_tasks" on client_integration_tasks;
create policy "permissive_all_client_integration_tasks" on client_integration_tasks for all using (true) with check (true);

-- ---------------------------------------------------------------------------
-- integration_requirement_docs — version history of generated requirement
-- docs per client, same append-only version-snapshot pattern as Plan
-- Builder's baseline/version history. snapshot freezes the full task list at
-- generation time so a later task edit never silently rewrites a doc a
-- client has already been sent.
-- ---------------------------------------------------------------------------
create table if not exists integration_requirement_docs (
  id            uuid primary key default gen_random_uuid(),
  client_id     uuid not null references clients(id) on delete cascade,
  version       int not null default 1,
  snapshot      jsonb not null,
  generated_by  text,
  created_at    timestamptz not null default now()
);
create index if not exists idx_ird_client_id on integration_requirement_docs(client_id);

-- Access in the app itself is gated on the 'studio' module capability (see
-- role_capabilities above — Solutions engineer has view, Implementation PM
-- has view+edit).
alter table integration_requirement_docs enable row level security;
drop policy if exists "permissive_all_integration_requirement_docs" on integration_requirement_docs;
create policy "permissive_all_integration_requirement_docs" on integration_requirement_docs for all using (true) with check (true);

-- ---------------------------------------------------------------------------
-- Seed a starting task library so the module isn't empty on first load —
-- a realistic set for AMC/appraisal-platform integrations, editable from
-- Task Library at any time. Effort figures are informed placeholders (same
-- "seeded until real data exists" pattern as pricing tier volume ranges).
-- ---------------------------------------------------------------------------
insert into integration_task_templates (title, description, phase, estimated_weeks, eligible_ooo, eligible_custom, sort_order)
select * from (values
  ('LOS/POS connectivity setup', 'Connect the client''s loan origination or point-of-sale system to Class''s order API using the standard integration package.', 'Discovery', 1, true, true, 1),
  ('SSO / user provisioning', 'Configure single sign-on and user account provisioning for the client''s team.', 'Discovery', 1, true, true, 2),
  ('Standard order workflow configuration', 'Configure order routing, product eligibility, and status-update webhooks using default settings.', 'Mapping', 1.5, true, true, 3),
  ('Fee schedule setup', 'Load the client''s standard or tiered pricing into the ordering workflow.', 'Mapping', 1, true, true, 4),
  ('Standard reporting setup', 'Enable the client''s default operational and compliance reporting package.', 'Mapping', 0.5, true, true, 5),
  ('UAT — standard workflow', 'Client user acceptance testing against the standard order-to-delivery workflow.', 'Testing', 1, true, true, 6),
  ('Go-live readiness review', 'Final checklist review and go-live scheduling.', 'Go-live', 0.5, true, true, 7),
  ('Custom field mapping', 'Map non-standard client system fields to Class''s order schema.', 'Mapping', 2, false, true, 8),
  ('Custom webhook / callback development', 'Build a bespoke status-callback integration for a client system with no standard connector.', 'Mapping', 3, false, true, 9),
  ('Legacy system data migration', 'Migrate historical order or client data from a legacy platform.', 'Discovery', 2.5, false, true, 10)
) as v(title, description, phase, estimated_weeks, eligible_ooo, eligible_custom, sort_order)
where not exists (select 1 from integration_task_templates where integration_task_templates.title = v.title);

-- ---------------------------------------------------------------------------
-- jira_config — placeholder for a real JIRA Cloud/Server API connection,
-- same singleton/inert pattern as sso_config above: gives a future Platform
-- admin somewhere real to paste a project-scoped API token when one exists.
-- The JIRA Mapping screen's Excel/CSV export works today with no row here at
-- all; the "Push to JIRA" button checks enabled + the three required fields
-- before ever attempting a live call, and explains what's missing instead of
-- silently failing, matching the SSO configuration honesty pattern.
-- ---------------------------------------------------------------------------
create table if not exists jira_config (
  id                 smallint primary key default 1 check (id = 1),
  enabled            boolean not null default false,
  base_url           text,        -- e.g. https://classvaluation.atlassian.net
  project_key        text,        -- e.g. INTOPS
  api_email           text,
  api_token          text,
  issue_type_epic    text not null default 'Epic',
  issue_type_story   text not null default 'Story',
  updated_at         timestamptz not null default now()
);
insert into jira_config (id) values (1) on conflict (id) do nothing;

alter table jira_config enable row level security;
drop policy if exists "permissive_all_jira_config" on jira_config;
create policy "permissive_all_jira_config" on jira_config for all using (true) with check (true);

-- ---------------------------------------------------------------------------
-- client_integration_status — the PM-triggered handoff record from
-- Integration Studio to Delivery (added 2026-08-21, after the module first
-- shipped). Deliberately NOT automatic (e.g. "all tasks done" or "JIRA
-- pushed") — a PM might push some tasks to JIRA while still negotiating a
-- Custom requirement, so only an explicit "Move to Delivery" action is a
-- reliable signal. One row per client, created lazily on first move (a
-- missing row means 'planning', the implicit default — most clients never
-- need a row at all). Moving to Delivery freezes the plan (Studio's own UI
-- disables task mutation once status = 'in_delivery' — see
-- fragments/studio_module.js) so Delivery becomes the one place execution
-- changes happen from then on; everything already committed (tasks, JIRA
-- links, requirement docs) stays exactly as a historical record of what was
-- decided during onboarding. "Move back to Planning" is a real, supported
-- undo (moved_back_at/by), not a one-way door — mistakes happen, and Delivery
-- not being real yet (still a static mockup) makes an easy correction more
-- important, not less.
-- ---------------------------------------------------------------------------
create table if not exists client_integration_status (
  id                    uuid primary key default gen_random_uuid(),
  client_id             uuid not null references clients(id) on delete cascade,
  status                text not null default 'planning' check (status in ('planning','in_delivery')),
  moved_to_delivery_at  timestamptz,
  moved_to_delivery_by  text,
  moved_back_at         timestamptz,
  moved_back_by         text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  unique (client_id)
);
create index if not exists idx_cis_client_id on client_integration_status(client_id);

drop trigger if exists trg_client_integration_status_updated_at on client_integration_status;
create trigger trg_client_integration_status_updated_at
  before update on client_integration_status
  for each row execute function set_updated_at();

alter table client_integration_status enable row level security;
drop policy if exists "permissive_all_client_integration_status" on client_integration_status;
create policy "permissive_all_client_integration_status" on client_integration_status for all using (true) with check (true);

-- Implementation PM is Integration Studio's primary day-to-day owner (see
-- role_capabilities above), so needs to actually download the JIRA
-- import file and the requirement doc it generates — the original seed
-- predates this feature and left can_export off for every 'studio' row.
-- Corrective UPDATE, same pattern as the family-correction UPDATEs above.
update role_capabilities set can_export = true
where module = 'studio' and role_id = (select id from roles where name = 'Implementation PM');

-- ---------------------------------------------------------------------------
-- Delivery (added 2026-08-21, same day as the Move-to-Delivery handoff) —
-- real data behind what was a static mockup. Design context: Delivery was
-- originally meant to be a read-mostly cockpit over live JIRA work, but
-- there's no real JIRA connection yet, and even once there is one, JIRA's
-- own scope can drift from what Integration Studio committed at handoff
-- (engineers split stories, add work) — so "% of JIRA done" and "% of the
-- Studio plan done" are two honestly different numbers. Rather than fake a
-- JIRA-shaped stat, this cockpit is built entirely on data Class Value OS
-- already has for real:
--   - Progress is computed at render time from client_integration_tasks
--     (the same frozen plan Move-to-Delivery committed) — not stored here,
--     so it never goes stale. Labeled "plan completion", not "JIRA progress".
--   - Risk (the AT RISK / BLOCKED / ON TRACK signal, and the sort) is also
--     computed, from open/escalated blockers + progress vs. an implied or
--     PM-set pace — never hand-typed, so it can't disagree with the blocker
--     list sitting right next to it.
--   - Blockers and the go-live checklist are the two things that genuinely
--     need a human either way: "is this stuck on our side or the client's"
--     and "were 25 pilot orders actually completed" aren't things a ticket
--     system reliably knows on its own, JIRA or not.
-- ---------------------------------------------------------------------------

-- client_integration_status gets three additions: an optional PM-set target
-- go-live date (used to compute the "expected pace" baseline honestly — if
-- unset, the baseline falls back to the plan's own total estimated effort as
-- an implied duration from moved_to_delivery_at, and the UI says so rather
-- than pretending a target was confirmed), and the third lifecycle state —
-- 'in_engagement' — for the one transition Delivery's checklist gates.
-- Moving to Engagement is deliberately one-way from here (no "move back"
-- button, unlike Planning<->Delivery): by the time every checklist item is
-- attested, walking it back is an Engagement Mgmt conversation, not a
-- Delivery-screen misclick to undo.
alter table client_integration_status add column if not exists target_go_live_at date;
alter table client_integration_status add column if not exists moved_to_engagement_at timestamptz;
alter table client_integration_status add column if not exists moved_to_engagement_by text;
alter table client_integration_status drop constraint if exists client_integration_status_status_check;
alter table client_integration_status drop constraint if exists chk_cis_status;
alter table client_integration_status add constraint chk_cis_status
  check (status in ('planning','in_delivery','in_engagement'));

-- delivery_blockers — manual by design, not a JIRA mirror even once JIRA is
-- connected: the client-side/Class-side split and "who owns unsticking this"
-- are judgment calls a Delivery PM makes, not a field JIRA's issue model
-- reliably carries. linked_jira_key is an optional, purely informational
-- reference for later — nothing here ever reads status back from a ticket.
create table if not exists delivery_blockers (
  id           uuid primary key default gen_random_uuid(),
  client_id    uuid not null references clients(id) on delete cascade,
  side         text not null check (side in ('client','class')),
  title        text not null,
  owner_team   text,                -- e.g. "Client IT", "Operations", "Engineering"
  status       text not null default 'new' check (status in ('new','open','escalated','resolved')),
  linked_jira_key text,
  opened_at    timestamptz not null default now(),
  resolved_at  timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists idx_delivery_blockers_client_id on delivery_blockers(client_id);

drop trigger if exists trg_delivery_blockers_updated_at on delivery_blockers;
create trigger trg_delivery_blockers_updated_at
  before update on delivery_blockers
  for each row execute function set_updated_at();

alter table delivery_blockers enable row level security;
drop policy if exists "permissive_all_delivery_blockers" on delivery_blockers;
create policy "permissive_all_delivery_blockers" on delivery_blockers for all using (true) with check (true);

-- delivery_checklist_templates / delivery_checklist_items — same
-- template-vs-instance split used for integration_task_templates /
-- client_integration_tasks: the fixed go-live checklist is configurable
-- institution-wide (templates), but each client gets its own copied,
-- independently-checkable instance the moment their Delivery workspace is
-- first opened — editing a template later never rewrites an already-checked
-- client's history.
create table if not exists delivery_checklist_templates (
  id          uuid primary key default gen_random_uuid(),
  label       text not null,
  sort_order  int not null default 0,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

alter table delivery_checklist_templates enable row level security;
drop policy if exists "permissive_all_delivery_checklist_templates" on delivery_checklist_templates;
create policy "permissive_all_delivery_checklist_templates" on delivery_checklist_templates for all using (true) with check (true);

insert into delivery_checklist_templates (label, sort_order)
select v.label, v.sort_order from (values
  ('All epics closed or descoped with approval', 1),
  ('Pilot orders completed end-to-end', 2),
  ('Client training attested', 3),
  ('Operational / panel capacity confirmed', 4),
  ('Invoicing and billing configuration verified', 5)
) as v(label, sort_order)
where not exists (select 1 from delivery_checklist_templates where delivery_checklist_templates.label = v.label);

create table if not exists delivery_checklist_items (
  id           uuid primary key default gen_random_uuid(),
  client_id    uuid not null references clients(id) on delete cascade,
  template_id  uuid references delivery_checklist_templates(id) on delete set null,
  label        text not null,
  sort_order   int not null default 0,
  checked      boolean not null default false,
  checked_by   text,
  checked_at   timestamptz,
  created_at   timestamptz not null default now(),
  unique (client_id, template_id)
);
create index if not exists idx_delivery_checklist_items_client_id on delivery_checklist_items(client_id);

alter table delivery_checklist_items enable row level security;
drop policy if exists "permissive_all_delivery_checklist_items" on delivery_checklist_items;
create policy "permissive_all_delivery_checklist_items" on delivery_checklist_items for all using (true) with check (true);
