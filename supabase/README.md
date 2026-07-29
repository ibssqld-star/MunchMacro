# MacroMunch — Supabase setup

Everything needed for the backend of its **own dedicated project** (not the company one).

```
supabase/
  schema.sql               ← run once in the SQL Editor
  functions/coach/index.ts ← AI coach proxy (keeps the Anthropic key server-side)
```

---

## Step 1 — Create the project

1. supabase.com → **New project**. Name it `macromunch`.
2. Pick a region near you, save the DB password somewhere safe.
3. Wait for it to finish provisioning (~2 min).

## Step 2 — Run the schema

1. Left sidebar → **SQL Editor** → **New query**.
2. Paste all of `supabase/schema.sql` → **Run**.
3. You should see `Success`. Check **Table Editor** — you'll have 7 tables:
   `profile`, `food_log`, `daily_state`, `meal_preps`, `shopping_items`, `body_log`, `user_foods`.

It's safe to re-run if you change something — it's all guarded.

**What the schema gives you beyond tables:**
- **RLS on every table** — a user can only ever read/write their own rows.
- **Auto-profile on signup** — a `profile` row (goals, treats, level, XP) is created by trigger.
- **`claim_goal(goal_key, payout)`** — awards treats *once per goal per day*, so a refresh can't farm rewards.
- **`spend_treats(amount)`** — atomic, so double-clicking Feed can't overdraw.
- **`food_log` delete trigger** — deleting a meal-prep serving frees that serving again automatically.
- **`today_totals` view** — pre-summed macros per day for the dashboard.

## Step 3 — Turn on email auth

**Authentication → Providers → Email** → enable. Turn on **magic link** (no passwords to manage).
For local testing you may want to disable "Confirm email".

## Step 4 — Deploy the coach function

Needs the Supabase CLI (`npm i -g supabase`).

```bash
supabase login
supabase link --project-ref <your-project-ref>

# store the Anthropic key as a secret — never in the client
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...

supabase functions deploy coach
```

Then open `supabase/functions/coach/index.ts` and add your deployed site origin to
`ALLOWED_ORIGINS` (localhost entries are already there), and redeploy.

## Step 5 — Send me the keys

From **Project Settings → API**:

- **Project URL** — `https://xxxx.supabase.co`
- **anon public key** — safe in the browser, RLS still protects the data

⚠️ Never share or ship the **service_role** key — it bypasses RLS entirely.

Once I have those I'll wire the app up, with in-memory fallback so it keeps working offline.

---

## Notes

- **Currency is `treats`**, not `bamboo` — species-neutral so you can add non-panda pets later.
- **The Bluetooth scale needs no backend** — it's Web Bluetooth in the browser. It does require
  Chrome/Edge over HTTPS (never Safari/iOS), which is the main reason to deploy rather than
  run from the in-chat preview.
- **The base food list** ships in the client. `user_foods` is only for custom + starred foods.
- **The coach must return text unmodified** — replies can end with `@@LOG` / `@@PREP` / `@@SHOP`
  directives the app parses to write rows. Don't add trimming or formatting to that function.
