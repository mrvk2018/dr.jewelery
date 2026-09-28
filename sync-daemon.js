/**
 * Polls sync_tasks.sync_requested; runs full sync.js ETL when admin triggers sync-catalog.
 *
 * Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (same as sync.js)
 */

require('dotenv').config();

const { spawn } = require('child_process');
const path = require('path');
const ws = require('ws');
const { createClient } = require('@supabase/supabase-js');

const POLL_INTERVAL_MS = Number(process.env.SYNC_DAEMON_POLL_MS || 10_000);
const SYNC_TASK_ID = 'catalog_sync';
const SYNC_SCRIPT = path.join(__dirname, 'sync.js');

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function requireEnv() {
  const url = process.env.SUPABASE_URL?.trim();
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();
  if (!url || !key) {
    throw new Error(
      'Задайте SUPABASE_URL и SUPABASE_SERVICE_ROLE_KEY в .env (service_role).',
    );
  }
  return { url, key };
}

function createSupabase() {
  const { url, key } = requireEnv();
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
    realtime: { transport: ws },
  });
}

async function fetchSyncRequested(supabase) {
  const { data, error } = await supabase
    .from('sync_tasks')
    .select('sync_requested')
    .eq('id', SYNC_TASK_ID)
    .maybeSingle();

  if (error) throw error;
  return Boolean(data?.sync_requested);
}

function runSyncWorker() {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [SYNC_SCRIPT], {
      cwd: __dirname,
      stdio: 'inherit',
      env: process.env,
    });

    child.on('error', reject);
    child.on('close', (code, signal) => {
      if (signal) {
        reject(new Error(`sync.js terminated by signal ${signal}`));
        return;
      }
      resolve(code ?? 1);
    });
  });
}

async function waitForFlagCleared(supabase) {
  while (await fetchSyncRequested(supabase)) {
    await sleep(2000);
  }
}

async function runDaemon() {
  const supabase = createSupabase();

  console.log(
    `[sync-daemon] started — poll every ${POLL_INTERVAL_MS / 1000}s, task id=${SYNC_TASK_ID}`,
  );

  while (true) {
    try {
      const requested = await fetchSyncRequested(supabase);

      if (!requested) {
        await sleep(POLL_INTERVAL_MS);
        continue;
      }

      console.log('[sync-daemon] sync_requested=true — spawning sync.js (full ETL)…');
      const exitCode = await runSyncWorker();

      if (exitCode === 0) {
        if (await fetchSyncRequested(supabase)) {
          console.log('[sync-daemon] waiting for sync_requested=false after sync.js…');
          await waitForFlagCleared(supabase);
        }
        console.log('[sync-daemon] cycle complete — sync_requested=false');
      } else {
        console.warn(
          `[sync-daemon] sync.js exit code ${exitCode}; sync_requested likely still true — retry after sleep`,
        );
      }
    } catch (err) {
      console.error('[sync-daemon] loop error:', err instanceof Error ? err.message : err);
    }

    await sleep(POLL_INTERVAL_MS);
  }
}

runDaemon().catch((err) => {
  console.error('[sync-daemon] fatal:', err);
  process.exit(1);
});
