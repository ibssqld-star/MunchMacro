# MacroMunch

Macro + calorie tracker where hitting your goals earns treats to feed a collectible pet.
Bluetooth food-scale support, meal-prep batching, shopping list, body-weight tracking,
and an AI coach that can log food from a photo.

## Repo layout

```
index.html          ← the app (single self-contained file, deployed by Vercel)
vercel.json         ← headers: enables Web Bluetooth, prevents stale caching
supabase/
  schema.sql        ← run once in the Supabase SQL Editor
  functions/coach/  ← Edge Function proxying Anthropic (holds the API key)
src/
  PandaMacros.dc.html   ← the editable source; index.html is generated from it
SHIPPING.md         ← deploy steps
```

`index.html` is **generated** — edit `src/PandaMacros.dc.html` and re-bundle, never hand-edit it.

## Deploy

Vercel is wired to this repo, so **push to `main` and it deploys**.

```bash
git add -A && git commit -m "…" && git push
```

First-time setup and the Supabase side are in [SHIPPING.md](./SHIPPING.md).

## Configuration

`index.html` contains a `window.MACROMUNCH_CONFIG` block:

```js
window.MACROMUNCH_CONFIG = {
  coachUrl: 'https://xxxx.supabase.co/functions/v1/coach',
  anonKey:  'eyJhbGci...',
};
```

Only the Supabase **anon** key belongs here — it's designed to be public and RLS protects the data.
The `service_role` key must never be committed or shipped to the browser.

## Notes

- **Web Bluetooth needs Chrome or Edge over HTTPS.** It does not exist on Safari or iOS —
  the app works there, you just type amounts instead of weighing.
- Scale protocol (Ultrean UL-KS09): service `0xFFFF`, characteristic `0xFF02`, weight sent as
  length-prefixed ASCII digits at byte 7. Standard SIG Weight Measurement (`0x2A9D`) is used as a
  fallback for body scales.
- Data currently persists per-browser via `localStorage`. Cloud sync lands when the Supabase
  tables are wired up.
