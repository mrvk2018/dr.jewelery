import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/** Официальный REST Toss (Basic Auth + secret key). Документация: https://docs.tosspayments.com */
const TOSS_CONFIRM_URL =
  "https://api.tosspayments.com/v1/payments/confirm";

const DEFAULT_TOSS_TEST_SECRET =
  "test_sk_ZzYySjdYVk1XbU9kWm40Ym9wNlFSTXpO";

type ConfirmPaymentBody = {
  paymentKey?: string;
  orderId?: string;
  amount?: number;
};

/** Соответствует public.order_drafts (миграция 022). */
type OrderDraftRow = {
  id: string;
  user_id: string;
  product_id: string;
  calculated_amount: number;
  status: string;
  payload?: Record<string, unknown> | null;
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function tossAuthorizationHeader(secretKey: string): string {
  const trimmed = secretKey.trim();
  return `Basic ${btoa(`${trimmed}:`)}`;
}

function parseAmount(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return Math.trunc(parsed);
  }
  return null;
}

async function confirmWithToss(
  secretKey: string,
  paymentKey: string,
  orderId: string,
  amount: number,
): Promise<
  | { ok: true; data: unknown }
  | { ok: false; status: number; body: unknown }
> {
  const response = await fetch(TOSS_CONFIRM_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: tossAuthorizationHeader(secretKey),
    },
    body: JSON.stringify({ paymentKey, orderId, amount }),
  });

  let body: unknown = null;
  try {
    body = await response.json();
  } catch {
    body = { raw: await response.text().catch(() => "") };
  }

  if (!response.ok) {
    return { ok: false, status: response.status, body };
  }
  return { ok: true, data: body };
}

function orderRowFromDraft(draft: OrderDraftRow) {
  const payload = draft.payload ?? {};
  const pick = (key: string): string | undefined => {
    const fromPayload = payload[key];
    if (typeof fromPayload === "string" && fromPayload.trim()) {
      return fromPayload.trim();
    }
    return undefined;
  };

  return {
    id: draft.id,
    user_id: draft.user_id,
    product_name: pick("product_name") ?? "Заказ",
    amount: draft.calculated_amount,
    status: "paid",
    customer_name: pick("customer_name") ?? "Покупатель",
    shipping_postal_code: pick("shipping_postal_code") ?? "",
    shipping_road_address: pick("shipping_road_address") ?? "",
    shipping_detail_address: pick("shipping_detail_address") ?? "",
    recipient_name: pick("recipient_name") ?? "",
    recipient_phone: pick("recipient_phone") ?? "",
    ...(pick("seller_code") ? { seller_code: pick("seller_code") } : {}),
    ...(pick("seller_name") ? { seller_name: pick("seller_name") } : {}),
  };
}

async function markDraftFailed(
  supabase: ReturnType<typeof createClient>,
  draftId: string,
) {
  await supabase
    .from("order_drafts")
    .update({ status: "failed" })
    .eq("id", draftId);
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ success: false, error: "Method not allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim();
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
  const tossSecret = Deno.env.get("TOSS_TEST_SECRET_KEY")?.trim() ||
    DEFAULT_TOSS_TEST_SECRET;

  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse(
      { success: false, error: "Server configuration error" },
      500,
    );
  }

  let body: ConfirmPaymentBody;
  try {
    body = (await req.json()) as ConfirmPaymentBody;
  } catch {
    return jsonResponse({ success: false, error: "Invalid JSON body" }, 400);
  }

  const paymentKey = body.paymentKey?.trim();
  const orderId = body.orderId?.trim();
  const paidAmount = parseAmount(body.amount);

  if (!paymentKey || !orderId || paidAmount === null || paidAmount <= 0) {
    return jsonResponse(
      {
        success: false,
        error: "paymentKey, orderId and positive amount are required",
      },
      400,
    );
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    const { data: draftRow, error: draftError } = await supabase
      .from("order_drafts")
      .select("*")
      .eq("id", orderId)
      .maybeSingle();

    if (draftError) {
      console.error("order_drafts select failed:", draftError.message);
      return jsonResponse({ success: false, error: draftError.message }, 500);
    }

    if (!draftRow) {
      return jsonResponse(
        { success: false, error: "Order draft not found" },
        404,
      );
    }

    const draft = draftRow as OrderDraftRow;
    const expectedAmount = parseAmount(draft.calculated_amount);

    if (expectedAmount === null) {
      return jsonResponse(
        { success: false, error: "Draft has invalid calculated_amount" },
        500,
      );
    }

    if (paidAmount !== expectedAmount) {
      await markDraftFailed(supabase, orderId);
      return jsonResponse(
        {
          success: false,
          error: "Попытка подмены цен!",
          code: "AMOUNT_MISMATCH",
        },
        400,
      );
    }

    const tossResult = await confirmWithToss(
      tossSecret,
      paymentKey,
      orderId,
      paidAmount,
    );

    if (!tossResult.ok) {
      await markDraftFailed(supabase, orderId);
      return jsonResponse(
        {
          success: false,
          error: "Toss payment confirmation failed",
          tossStatus: tossResult.status,
          details: tossResult.body,
        },
        tossResult.status >= 400 && tossResult.status < 600
          ? tossResult.status
          : 502,
      );
    }

    const { error: confirmDraftError } = await supabase
      .from("order_drafts")
      .update({ status: "confirmed" })
      .eq("id", orderId);

    if (confirmDraftError) {
      return jsonResponse(
        { success: false, error: confirmDraftError.message },
        500,
      );
    }

    const { error: orderError } = await supabase.from("orders").insert(
      orderRowFromDraft(draft),
    );

    if (orderError) {
      return jsonResponse(
        {
          success: false,
          error: "Payment confirmed but order persist failed",
          details: orderError.message,
        },
        500,
      );
    }

    // TODO(prod): в одной транзакции Supabase пометить купленные SKU как `sold`:
    // const productIds = (draft.payload?.line_item_ids as string[]) ?? [draft.product_id];
    // await supabase.rpc("mark_products_sold_after_payment", {
    //   p_draft_id: orderId,
    //   p_product_ids: productIds,
    // });
    // -- SQL внутри RPC:
    // -- BEGIN;
    // -- UPDATE public.products SET status = 'sold', updated_at = now()
    // --   WHERE id = ANY(p_product_ids) AND status IN ('active', 'reserved');
    // -- UPDATE public.order_drafts SET status = 'fulfilled' WHERE id = p_draft_id;
    // -- COMMIT;

    return jsonResponse({ success: true, toss: tossResult.data });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await markDraftFailed(supabase, orderId).catch(() => undefined);
    return jsonResponse({ success: false, error: message }, 500);
  }
});
