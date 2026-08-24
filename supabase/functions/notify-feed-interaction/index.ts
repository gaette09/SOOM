// Setup type definitions for built-in Supabase Runtime APIs
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "jsr:@supabase/supabase-js@2"

// Sandbox by default — flip via the APNS_ENVIRONMENT secret once the app
// ships to TestFlight/App Store, never hardcode the host.
const APNS_HOST = Deno.env.get("APNS_ENVIRONMENT") === "production"
  ? "api.push.apple.com"
  : "api.sandbox.push.apple.com"

interface TriggerPayload {
  table: "feed_reactions" | "feed_comments"
  record: {
    id: string
    post_id: string
    user_id: string
    reaction_type?: string
    body?: string
  }
}

function isAuthorized(req: Request): boolean {
  const expected = Deno.env.get("WEBHOOK_SECRET")
  const provided = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "")
  return !!expected && provided === expected
}

function base64url(bytes: Uint8Array): string {
  let binary = ""
  for (const b of bytes) binary += String.fromCharCode(b)
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}

let cachedSigningKey: CryptoKey | null = null

async function apnsSigningKey(): Promise<CryptoKey> {
  if (cachedSigningKey) return cachedSigningKey
  const pem = Deno.env.get("APNS_AUTH_KEY")!
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "")
  const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0))
  cachedSigningKey = await crypto.subtle.importKey(
    "pkcs8",
    bytes.buffer,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  )
  return cachedSigningKey
}

// Not cached across requests — see ROADMAP.yaml's notifications-infrastructure
// node for the known gap (re-signed every call, fine at this traffic level).
async function makeApnsJwt(): Promise<string> {
  const teamId = Deno.env.get("APNS_TEAM_ID")!
  const keyId = Deno.env.get("APNS_KEY_ID")!
  const key = await apnsSigningKey()
  const header = base64url(new TextEncoder().encode(JSON.stringify({ alg: "ES256", kid: keyId })))
  const payload = base64url(
    new TextEncoder().encode(JSON.stringify({ iss: teamId, iat: Math.floor(Date.now() / 1000) })),
  )
  const signingInput = `${header}.${payload}`
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  )
  return `${signingInput}.${base64url(new Uint8Array(signature))}`
}

Deno.serve(async (req) => {
  if (!isAuthorized(req)) {
    return new Response("unauthorized", { status: 401 })
  }

  const payload = (await req.json()) as TriggerPayload
  const actorId = payload.record.user_id
  const postId = payload.record.post_id
  const notificationType = payload.table === "feed_reactions" ? "reaction" : "comment"

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  )

  const { data: post } = await supabase
    .from("feed_posts")
    .select("user_id")
    .eq("id", postId)
    .single()

  // No post found, or the actor reacted to/commented on their own post —
  // self-interactions never notify (batch4 plan's minimum safety net).
  if (!post || post.user_id === actorId) {
    return new Response(JSON.stringify({ skipped: true }), {
      headers: { "Content-Type": "application/json" },
    })
  }

  const recipientId = post.user_id as string
  const body = notificationType === "reaction"
    ? "누군가 회원님의 운동에 응원을 보냈어요."
    : "누군가 회원님의 운동에 댓글을 남겼어요."

  await supabase.from("notifications").insert({
    recipient_id: recipientId,
    actor_id: actorId,
    type: notificationType,
    post_id: postId,
    body,
  })

  const { data: tokens } = await supabase
    .from("device_tokens")
    .select("token")
    .eq("user_id", recipientId)

  const jwt = await makeApnsJwt()
  const bundleId = Deno.env.get("APNS_BUNDLE_ID")!

  const results = []
  for (const { token } of tokens ?? []) {
    const response = await fetch(`https://${APNS_HOST}/3/device/${token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": bundleId,
        "apns-push-type": "alert",
      },
      // post_id sits alongside `aps` (not inside it) — that's where APNs
      // puts custom payload data, and where the client reads it back from
      // UNNotificationResponse.notification.request.content.userInfo for
      // the tap-to-deep-link route (batch 5).
      body: JSON.stringify({
        aps: { alert: { title: "SOOM", body }, sound: "default" },
        post_id: postId,
      }),
    })
    console.log(`[notify-feed-interaction] APNs status=${response.status} token=${token.slice(0, 8)}...`)
    results.push({ tokenPrefix: token.slice(0, 8), status: response.status })
  }

  return new Response(JSON.stringify({ recipientId, notificationType, results }), {
    headers: { "Content-Type": "application/json" },
  })
})
