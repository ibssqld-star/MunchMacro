// MacroMunch — AI coach proxy
// Deploy:  supabase functions deploy coach
// Secret:  supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
//
// Keeps the Anthropic key server-side. The browser never sees it.
//
// Request body (sent verbatim by the app):
//   { system: string, messages: Message[], max_tokens?: number }
//   Message.content is EITHER a string OR an array of blocks
//   (food photos arrive as { type:'image', source:{ type:'base64', media_type, data } }).
//
// Response: { text: string }
//
// IMPORTANT: return the model's text UNMODIFIED. Replies may end with directives
// (@@LOG:[…]@@ / @@PREP:[…]@@ / @@SHOP:[…]@@) that the client parses to write rows.
// Trimming or reformatting the body will silently break logging-by-chat.

const ALLOWED_ORIGINS = [
  "http://localhost:3000",
  "http://localhost:5173",
  // add your deployed origin, e.g. "https://macromunch.vercel.app"
];

function corsHeaders(origin: string | null) {
  const allow = origin && ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0];
  return {
    "Access-Control-Allow-Origin": allow,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, content-type, apikey",
    "Vary": "Origin",
  };
}

const json = (body: unknown, status: number, origin: string | null) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...corsHeaders(origin) },
  });

Deno.serve(async (req) => {
  const origin = req.headers.get("origin");

  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(origin) });
  if (req.method !== "POST") return json({ error: "POST only" }, 405, origin);

  // --- require a signed-in user ---
  const auth = req.headers.get("authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json({ error: "missing bearer token" }, 401, origin);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (supabaseUrl && anonKey) {
    const who = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: { authorization: auth, apikey: anonKey },
    });
    if (!who.ok) return json({ error: "invalid session" }, 401, origin);
  }

  const key = Deno.env.get("ANTHROPIC_API_KEY");
  if (!key) return json({ error: "ANTHROPIC_API_KEY not configured" }, 500, origin);

  let body: { system?: string; messages?: unknown; max_tokens?: number };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid JSON" }, 400, origin);
  }

  const messages = body.messages;
  if (!Array.isArray(messages) || messages.length === 0) {
    return json({ error: "messages[] required" }, 400, origin);
  }
  // guard against oversized photo payloads
  if (JSON.stringify(messages).length > 6_000_000) {
    return json({ error: "payload too large — compress the image" }, 413, origin);
  }

  try {
    const upstream = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": key,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-haiku-4-5",
        max_tokens: Math.min(Math.max(body.max_tokens ?? 600, 64), 4096),
        system: body.system ?? "",
        messages, // passed through untouched — string OR block-array content
      }),
    });

    if (!upstream.ok) {
      const detail = await upstream.text();
      console.error("anthropic error", upstream.status, detail);
      return json({ error: "coach upstream error", status: upstream.status }, 502, origin);
    }

    const data = await upstream.json();
    // Concatenate text blocks verbatim — no trimming, no rewriting.
    const text = (data.content ?? [])
      .filter((b: { type: string }) => b.type === "text")
      .map((b: { text: string }) => b.text)
      .join("");

    return json({ text }, 200, origin);
  } catch (err) {
    console.error(err);
    return json({ error: "coach failed" }, 500, origin);
  }
});
