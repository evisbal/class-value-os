# Class Value OS

Static front-end preview for Class Valuation's internal Value OS platform, plus the fully-functional Class Plan Builder tool.

## Files

- `index.html` — Class Value OS shell. Sidebar navigation across all 11 screens (System map, My work, Demand Management, Value CPQ, Plan Builder, Integration Studio, Delivery, Status Reporting, Engagement Management, Roles & Permissions, System states). Every screen except Plan Builder is a **static mockup** — real design-system sample data, no backend, no persistence.
- `class-plan-builder.html` — the real, fully-functional Class Plan Builder application. Works standalone (open it directly) or embedded inside `index.html`'s Plan Builder module via `<iframe src="class-plan-builder.html">`. Saves projects to the browser's `localStorage` under the key `classPlanBuilder.projects.v1`.
- `.nojekyll` — tells GitHub Pages to serve these files as-is, skipping Jekyll processing (not needed for a plain static site, and Jekyll's `{{ }}` template syntax would otherwise conflict with nothing here, but this is standard practice and avoids build-time surprises).

No build step, no framework, no dependencies to install. Both files are self-contained HTML/CSS/JS.

## Deploying to GitHub Pages

1. Create a new repository on GitHub (public — Pages is free for public repos; private repos need GitHub Pro/Team/Enterprise for Pages).
2. Push these files to the repo's default branch (`main`), at the repo root:
   ```bash
   git init
   git add .
   git commit -m "Initial deploy: Class Value OS + Class Plan Builder"
   git branch -M main
   git remote add origin https://github.com/<your-username>/<your-repo>.git
   git push -u origin main
   ```
3. In the repo on GitHub: **Settings → Pages → Build and deployment → Source: "Deploy from a branch"** → Branch: `main`, folder `/ (root)` → Save.
4. GitHub gives you a URL like `https://<your-username>.github.io/<your-repo>/`. It auto-redeploys on every push to `main` — no extra workflow file needed for this simple case.

That's the whole "auto deploy" setup — GitHub Pages watches the branch and rebuilds automatically on every push once step 3 is done once.

## What is and isn't functional

Everything here is plain client-side HTML/CSS/JS — none of it depends on Claude, Cowork, or any AI service to run, **except one button**:

- Inside Class Plan Builder, the **"Process document(s)"** button (part of "Upload & Process") calls `window.cowork.askClaude(...)` to auto-fill fields from an uploaded file. That bridge only exists inside Cowork. Outside it (like here, on GitHub Pages), the button is still there but shows *"AI extraction is not available in this view"* instead of crashing — everything else in the app (manual entry, RACI, comms plan, risk register, versioning, PDF/markdown export, localStorage save) works exactly the same.
- To make that button work in a real deployment, it needs to call the Anthropic API directly. That requires a small backend or serverless function (a Cloudflare Worker, Vercel/Netlify function, or similar) to hold the API key — an API key can never be safely placed in client-side code that anyone can view-source.

## Do you need Supabase?

Not for this deployment. Supabase (or any database) only becomes relevant once you build the real backend behind Class Value OS — shared, multi-user data for clients, demands, quotes, plans, JIRA sync, etc. Right now:

- Class Value OS's 10 other modules are static previews with no data layer at all.
- Class Plan Builder persists to each browser's own `localStorage` — not shared across devices or users.

Add a database later, when you're ready to build the real backend module by module, as you described. It's not a prerequisite for getting this front end live and testable in a browser today.

## Local testing before you push

Don't just double-click the HTML files — some browsers restrict `localStorage` on `file://` URLs. Serve them locally instead:

```bash
python3 -m http.server 8000
# then open http://localhost:8000/
```
