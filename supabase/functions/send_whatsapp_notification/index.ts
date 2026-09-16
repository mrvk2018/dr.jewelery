import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type OrderLineItem = {
  sku: string;
  warehouse_item_id: string;
  weight: string | number;
  size: string | number;
  price_krw: number;
  unit_price_krw: number;
  quantity: number;
  stones: string;
  image_url?: string;
};

type OrderNotificationPayload = {
  recipient: string;
  order_id: string;
  total_amount_krw?: number;
  seller_code?: string;
  items: OrderLineItem[];
};

const SEPARATOR = "------------------------";

function formatWeightForMessage(weight: string | number): string {
  const raw = String(weight).trim();
  if (!raw) return "—";
  if (/g$/i.test(raw) || raw.includes("г")) return raw;
  return `${raw}г`;
}

function formatLineBlock(item: OrderLineItem): string {
  const size = String(item.size).trim() || "—";
  const weight = formatWeightForMessage(item.weight);
  const stones = item.stones?.trim() || "—";
  const qtySuffix = item.quantity > 1 ? ` (×${item.quantity})` : "";

  return [
    `Артикул (SKU): ${item.sku}${qtySuffix}`,
    `Размер: ${size} | Вес: ${weight}`,
    `Вставки: ${stones}`,
    `Цена: ${item.price_krw} KRW`,
  ].join("\n");
}

function buildWhatsAppMessageText(payload: OrderNotificationPayload): string {
  const lines: string[] = [
    `🛍️ Новый заказ №${payload.order_id}!`,
    SEPARATOR,
  ];

  for (const item of payload.items) {
    lines.push(formatLineBlock(item));
    lines.push(SEPARATOR);
  }

  if (payload.total_amount_krw != null) {
    lines.push(`Всего к оплате: ${payload.total_amount_krw} KRW`);
  }

  if (payload.seller_code?.trim()) {
    lines.push(`👤 Продавец (Промокод): ${payload.seller_code.trim()}`);
  }

  return lines.join("\n");
}

Deno.serve(async (req: Request): Promise<Response> => {
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
    const body = (await req.json()) as OrderNotificationPayload;

    console.log("send_whatsapp_notification payload:", {
      recipient: body.recipient,
      order_id: body.order_id,
      total_amount_krw: body.total_amount_krw,
      items_count: body.items?.length ?? 0,
    });

    if (!body.order_id || !Array.isArray(body.items) || body.items.length === 0) {
      return new Response(
        JSON.stringify({ error: "order_id and non-empty items are required" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    for (const item of body.items) {
      console.log("Ссылка на фото:", item.image_url);
    }

    const messageText = buildWhatsAppMessageText(body);
    console.log("Сформированный текст для WhatsApp:", messageText);

    const botToken = Deno.env.get("TELEGRAM_BOT_TOKEN");
    const chatId = Deno.env.get("TELEGRAM_CHAT_ID");

    if (!botToken?.trim() || !chatId?.trim()) {
      console.warn("Telegram credentials missing. Logging message only.");
    } else {
      const telegramUrl =
        `https://api.telegram.org/bot${botToken}/sendMessage`;

      try {
        const telegramResponse = await fetch(telegramUrl, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            chat_id: chatId,
            text: messageText,
          }),
        });

        if (!telegramResponse.ok) {
          const errorText = await telegramResponse.text();
          console.error(
            "Telegram sendMessage HTTP error:",
            telegramResponse.status,
            errorText,
          );
        }
      } catch (fetchError) {
        console.error("Telegram sendMessage fetch failed:", fetchError);
      }
    }

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("send_whatsapp_notification parse error:", error);
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
