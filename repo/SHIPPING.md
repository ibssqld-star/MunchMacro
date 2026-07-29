# Deploying MacroMunch — GitHub → Vercel + Supabase

GitHub is the source of truth. Vercel watches the repo and deploys on every push; Supabase is
set up once from the CLI.

---

## Part 1 — Push to GitHub

Lay the repo out so Vercel needs **no** configuration (app files at the root):

```
index.html          ← from deploy/index.html
vercel.json         ← from deploy/vercel.json
README.md
SHIPPING.md
.gitignore
supabase/
src/PandaMacros.dc.html
```

```bash
# in an empty folder with those files
git init
git add -A
git commit -m "MacroMunch: initial"
git branch -M main
git remote add origin git@github.com:<you>/macromunch.git
git push -u origin main
```

> If you'd rather keep `index.html` inside `deploy/`, that's fine — just set Vercel's
> **Root Directory** to `deploy` in step 2.

---

## Part 2 — Connect Vercel to the repo

1. vercel.com → **Add New Project** → **Import Git Repository** → pick `macromunch`.
2. **Framework Preset: Other.** Leave Build Command and Output Directory **empty** — it's a static
   file, there's nothing to build.
3. Root Directory: leave as `./` (or `deploy` if you kept that layout).
4. **Deploy.**

From now on **every push to `main` deploys automatically**, and pull requests get preview URLs.

You'll have `https://<project>.vercel.app` on HTTPS — which is what makes the **Bluetooth scale
pair** (Chrome/Edge only; Web Bluetooth doesn't exist on Safari/iOS).

### What `vercel.json` is doing
- `Permissions-Policy: bluetooth=(self)` — without this some Chrome builds silently block
  `requestDevice()` and no pairing prompt ever appears.
- `Cache-Control: no-cache` on `index.html` — so a redeploy shows up instead of serving a stale copy.

Everything works at this point except the AI coach.

---

## Part 3 — Supabase

Detailed version in `supabase/README.md`. Short version:

1. **New project** named `macromunch` — its own project, not the company one.
2. **SQL Editor** → paste all of `supabase/schema.sql` → **Run**. You get 7 tables with RLS,
   auto-profile-on-signup, and `claim_goal` / `spend_treats` so rewards can't be farmed by refreshing.
3. **Authentication → Providers → Email** → enable magic link.
4. Deploy the coach function:

```bash
supabase login
supabase link --project-ref <project-ref>
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
supabase functions deploy coach
```

5. **Add your Vercel URL to CORS** — in `supabase/functions/coach/index.ts` add
   `"https://<project>.vercel.app"` to `ALLOWED_ORIGINS`, commit, then
   `supabase functions deploy coach` again.
   *This is the most common reason the chat works locally but fails in production.*

---

## Part 4 — Wire them together

Edit the config block in `index.html` (and in `src/PandaMacros.dc.html` so it survives re-bundling):

```js
window.MACROMUNCH_CONFIG = {
  coachUrl: 'https://xxxx.supabase.co/functions/v1/coach',
  anonKey:  'eyJhbGci...',
};
```

Commit and push — Vercel redeploys and the coach comes alive.

⚠️ **anon key only.** `service_role` bypasses RLS; never commit it or ship it to a browser.

---

## Making changes later

`index.html` is generated. Edit `src/PandaMacros.dc.html`, I re-bundle it, then:

```bash
git add -A && git commit -m "…" && git push
```

Vercel deploys automatically.

---

## Where things stand

**Live after Part 2:** the whole app — logging, quantities, frequents, custom foods, meal prep
with tick-off servings, shopping list, body weight, pets/treats/XP, the Bluetooth scale, and data
persisting per-browser with a proper daily rollover (intake and water reset; meal preps, shopping,
weigh-ins and pet progress carry over).

**Live after Part 3:** the AI coach — logging food by chat, reading food photos, stocking meal prep,
filling the shopping list.

**Still to build:** cloud sync and accounts, so your phone and laptop share one food log. Send me
the project URL + anon key and I'll wire the tables in. Until then, each browser keeps its own copy —
don't clear site data.
