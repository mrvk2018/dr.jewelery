import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

type WebhookPayload = {
  type?: string;
  table?: string;
  schema?: string;
  record?: Record<string, unknown>;
  old_record?: Record<string, unknown> | null;
};

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function escapeHtml(value: unknown): string {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

function pickProductName(record: Record<string, unknown>): string {
  const raw = record.name;
  if (raw && typeof raw === "object" && !Array.isArray(raw)) {
    const map = raw as Record<string, unknown>;
    for (const key of ["ru", "ko", "en"]) {
      const text = map[key];
      if (typeof text === "string" && text.trim()) return text.trim();
    }
  }
  if (typeof raw === "string" && raw.trim()) return raw.trim();
  const fallback = record.product_name ?? record.notes ?? record.sku;
  return String(fallback ?? "—").trim() || "—";
}

function readStatus(record: Record<string, unknown> | null | undefined): string {
  if (!record) return "";
  const status = record.product_status ?? record.status;
  return typeof status === "string" ? status.trim().toLowerCase() : "";
}

function isPosSaleStatus(status: string): boolean {
  if (!status) return false;
  return (
    status === "sold" ||
    status === "sold_at_pos" ||
    status === "pos_sold" ||
    status === "cashed_out" ||
    status.includes("sold") ||
    status.includes("выкуп")
  );
}

function buildTransferInsertMessage(record: Record<string, unknown>): string {
  const sender = escapeHtml(record.sender_code);
  const fromStore = escapeHtml(record.from_store);
  const toStore = escapeHtml(record.to_store);
  return (
    "🚚 <b>Запущен трансфер изделия!</b>\n" +
    `Отправил: ${sender}\n` +
    `Маршрут: ${fromStore} ➔ ${toStore}`
  );
}

function buildTransferUpdateMessage(record: Record<string, unknown>): string {
  const sender = escapeHtml(record.sender_code);
  const receiver = escapeHtml(record.receiver_code);
  return (
    "✅ <b>Трансфер успешно принят!</b>\n" +
    `Отправил: ${sender} ➔ Принял(а): ${receiver}\n` +
    "Статус: Доставлен"
  );
}

function buildProductSaleMessage(record: Record<string, unknown>): string {
  const name = escapeHtml(pickProductName(record));
  const sku = escapeHtml(record.sku);
  return (
    "🛍️ <b>Кассовая продажа / Выкуп!</b>\n" +
    `Товар: ${name}\n` +
    `SKU: ${sku}\n` +
    "Статус: Выкуплен на кассе"
  );
}

function shouldNotifyTransferUpdate(
  record: Record<string, unknown>,
  oldRecord: Record<string, unknown> | null | undefined,
): boolean {
  const newReceiver = String(record.receiver_code ?? "").trim();
  const oldReceiver = String(oldRecord?.receiver_code ?? "").trim();
  if (newReceiver && newReceiver !== oldReceiver) return true;

  const newStatus = String(record.status ?? "").trim().toLowerCase();
  const oldStatus = String(oldRecord?.status ?? "").trim().toLowerCase();
  const delivered = new Set(["delivered", "completed", "received", "done"]);
  return delivered.has(newStatus) && newStatus !== oldStatus;
}

function buildNotificationText(payload: WebhookPayload): string | null {
  const table = payload.table?.trim();
  const type = payload.type?.trim().toUpperCase();
  const record = payload.record;
  const oldRecord = payload.old_record ?? null;

  if (!table || !type || !record) return null;

  if (table === "product_transfers") {
    if (type === "INSERT") return buildTransferInsertMessage(record);
    if (type === "UPDATE" && shouldNotifyTransferUpdate(record, oldRecord)) {
      return buildTransferUpdateMessage(record);
    }
    return null;
  }

  if (table === "products" && type === "UPDATE") {
    const next = readStatus(record);
    const prev = readStatus(oldRecord);
    if (isPosSaleStatus(next) && !isPosSaleStatus(prev)) {
      return buildProductSaleMessage(record);
    }
  }

  return null;
}

async function sendTelegramMessage(text: string): Promise<Response> {
  const botToken = Deno.env.get("TELEGRAM_BOT_TOKEN")?.trim();
  const chatId = Deno.env.get("TELEGRAM_CHAT_ID")?.trim();

  if (!botToken || !chatId) {
    console.error("TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID is not configured");
    return new Response(
      JSON.stringify({ ok: false, error: "Telegram env missing" }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  const telegramUrl = `https://api.telegram.org/bot${botToken}/sendMessage`;
  const telegramResponse = await fetch(telegramUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      chat_id: chatId,
      text,
      parse_mode: "HTML",
    }),
  });

  if (!telegramResponse.ok) {
    const errorText = await telegramResponse.text();
    console.error("Telegram API error:", telegramResponse.status, errorText);
    return new Response(
      JSON.stringify({ ok: false, error: errorText }),
      {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const payload = (await req.json()) as WebhookPayload;
    console.log("telegram-logger webhook:", {
      table: payload.table,
      type: payload.type,
    });

    const message = buildNotificationText(payload);
    if (!message) {
      return new Response(JSON.stringify({ ok: true, skipped: true }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return await sendTelegramMessage(message);
  } catch (error) {
    console.error("telegram-logger failed:", error);
    return new Response(JSON.stringify({ error: "Invalid payload" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
