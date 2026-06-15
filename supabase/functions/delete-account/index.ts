import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get("authorization")
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    const SUPABASE_URL           = Deno.env.get("SUPABASE_URL")!
    const SUPABASE_ANON_KEY      = Deno.env.get("SUPABASE_ANON_KEY")!
    const SUPABASE_SERVICE_KEY   = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!

    // ── 1. Verify caller identity ────────────────────────────────────────────
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    })
    const { data: { user }, error: authErr } = await userClient.auth.getUser()
    if (authErr || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    // ── 2. Run pre-checks via RPC ────────────────────────────────────────────
    const { data: checkResult, error: checkErr } = await userClient.rpc("check_can_delete_account")
    if (checkErr) {
      return new Response(JSON.stringify({ error: checkErr.message }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }
    if (!checkResult?.can_delete) {
      return new Response(
        JSON.stringify({ error: checkResult?.details ?? "Cannot delete account at this time." }),
        { status: 422, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    // ── 3. Delete public data via RPC ────────────────────────────────────────
    const { error: deleteDataErr } = await userClient.rpc("delete_account_data")
    if (deleteDataErr) {
      return new Response(JSON.stringify({ error: deleteDataErr.message }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    // ── 4. Delete auth.users row using admin API ─────────────────────────────
    const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)
    const { error: deleteAuthErr } = await adminClient.auth.admin.deleteUser(user.id)
    if (deleteAuthErr) {
      // Public data is already deleted at this point — log but don't expose error detail
      console.error("Auth user deletion failed:", deleteAuthErr.message)
      return new Response(
        JSON.stringify({ error: "Account data removed but auth deletion failed. Contact support." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    })
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    })
  }
})
