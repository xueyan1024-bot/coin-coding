import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const SPAWN_INTERVAL_S = 0.8   // 与客户端保持一致
const MAX_CLICKS_PER_S = 6     // 人类点击上限

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors })

  const authHeader = req.headers.get("Authorization")
  if (!authHeader) return new Response("Unauthorized", { status: 401 })

  const supa = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { autoRefreshToken: false, persistSession: false } }
  )

  const { data: { user }, error } = await supa.auth.getUser(authHeader.replace("Bearer ", ""))
  if (error || !user) return new Response("Unauthorized", { status: 401, headers: cors })

  const { session_start, session_end, coins_earned, click_timestamps } = await req.json()
  const durationS = (new Date(session_end).getTime() - new Date(session_start).getTime()) / 1000

  if (durationS <= 0 || coins_earned <= 0) {
    return new Response(JSON.stringify({ error: "invalid" }), { status: 400, headers: cors })
  }

  // 防作弊 1：金币总量不能超过理论最大值（掉落速率 × 时长 × 15% 宽容）
  if (coins_earned > Math.ceil(durationS / SPAWN_INTERVAL_S) * 1.15) {
    return new Response(JSON.stringify({ error: "too_many_coins" }), { status: 400, headers: cors })
  }

  // 防作弊 2：点击频率不能超过人类上限
  if (Array.isArray(click_timestamps) && click_timestamps.length > 1) {
    for (let i = 1; i < click_timestamps.length; i++) {
      if (click_timestamps[i] - click_timestamps[i - 1] < 1000 / MAX_CLICKS_PER_S) {
        return new Response(JSON.stringify({ error: "too_fast" }), { status: 400, headers: cors })
      }
    }
  }

  const { error: addErr } = await supa.rpc("add_coins", { p_user_id: user.id, p_amount: coins_earned })
  if (addErr) return new Response(JSON.stringify({ error: addErr.message }), { status: 500, headers: cors })

  return new Response(JSON.stringify({ ok: true }), {
    headers: { ...cors, "Content-Type": "application/json" }
  })
})
