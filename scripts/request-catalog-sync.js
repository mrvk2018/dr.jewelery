/**
 * Ставит sync_tasks.sync_requested=true (то же, что Edge sync-catalog из админки).
 * Запуск на складском ПК, где уже есть .env с SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY.
 *
 *   node scripts/request-catalog-sync.js
 *
 * Далее sync-daemon подхватит флаг и выполнит node sync.js (полный ETL).
 * Или сразу: npm run sync  (после установки флага этим скриптом или вручную).
 */

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const ws = require('ws');
const { createClient } = require('@supabase/supabase-js');

const SYNC_TASK_ID = 'catalog_sync';

async function main() {
  const url = process.env.SUPABASE_URL?.trim();
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();
  if (!url || !key) {
    throw new Error('SUPABASE_URL и SUPABASE_SERVICE_ROLE_KEY обязательны в .env');
  }

  const supabase = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
    realtime: { transport: ws },
  });

  const { error } = await supabase
    .from('sync_tasks')
    .update({
      sync_requested: true,
      updated_at: new Date().toISOString(),
    })
    .eq('id', SYNC_TASK_ID);

  if (error) throw error;

  console.log(
    `[request-catalog-sync] ${SYNC_TASK_ID}: sync_requested=true. ` +
      'Убедитесь, что на этом сервере запущен npm run sync:daemon (или выполните npm run sync).',
  );
}

main().catch((err) => {
  console.error('[request-catalog-sync] fatal:', err);
  process.exit(1);
});
