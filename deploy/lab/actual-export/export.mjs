// Export every transaction of an Actual Budget file as CSV, byte-for-byte what Actual's own
// "Export" menu produces (the same `transactions-export-query` handler the UI calls), plus
// each account's balance so the import can be checked against it.
//
//   ACTUAL_SERVER_URL=http://127.0.0.1:5006 ACTUAL_PASSWORD_FILE=./pw ACTUAL_SYNC_ID=<sync id> \
//     node export.mjs ./actual-export.csv
//
// Read-only: the budget is downloaded into a throwaway cache directory and never synced back.
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import * as api from '@actual-app/api';

function secret(name) {
  const file = process.env[`${name}_FILE`];
  return file ? readFileSync(file, 'utf8').trim() : process.env[name];
}

const out = process.argv[2] || 'actual-export.csv';
const serverURL = process.env.ACTUAL_SERVER_URL;
const password = secret('ACTUAL_PASSWORD');
const syncId = process.env.ACTUAL_SYNC_ID;
const budgetPassword = secret('ACTUAL_BUDGET_PASSWORD');
if (!serverURL || !password || !syncId) {
  console.error('Set ACTUAL_SERVER_URL, ACTUAL_PASSWORD (or ACTUAL_PASSWORD_FILE) and ACTUAL_SYNC_ID.');
  process.exit(2);
}

const cache = mkdtempSync(join(tmpdir(), 'actual-export-'));
try {
  const actual = await api.init({ dataDir: cache, serverURL, password });
  await api.downloadBudget(syncId, budgetPassword ? { password: budgetPassword } : undefined);

  const csv = await actual.send('transactions-export-query', { query: api.q('transactions').serialize() });
  writeFileSync(out, csv, { mode: 0o600 });

  const accounts = await api.getAccounts();
  console.log(`Wrote ${out}. Balances to check after importing into Sure:`);
  for (const account of accounts.sort((a, b) => a.name.localeCompare(b.name))) {
    const balance = (await api.getAccountBalance(account.id)) / 100;
    const flags = [account.offbudget ? 'off-budget' : 'on-budget', account.closed ? 'closed' : null].filter(Boolean);
    console.log(`  ${account.name.padEnd(28)} ${balance.toFixed(2).padStart(14)}  (${flags.join(', ')})`);
  }
  await api.shutdown();
} finally {
  rmSync(cache, { recursive: true, force: true });
}
