# Migrating from Actual Budget to Sure

One-time move of your Actual history into Sure, then SimpleFIN straight into Sure. Actual is
retired afterwards; nothing keeps the two in sync.

Every step below was run end to end against a real Actual server and this fork: balances, transfer
pairing and the SimpleFIN overlap behave as described. Numbers in the checks come from that run.

## What carries over, and how

| In Actual | In Sure |
|---|---|
| Accounts | Accounts you create first, with the right type (see step 3) |
| Transactions (payee, date, notes, cleared) | Transactions, locked against bank-sync overwrites |
| `Group` + `Category` | Parent category + subcategory (created on import) |
| Split transaction | One transaction per split line; the parent row is skipped |
| Starting balance | The account's **opening balance** (not income, not an expense) |
| Transfer between two accounts | Both legs imported; Sure pairs them into a Transfer after the import sync |
| Categorized transfer to an off-budget loan (mortgage payment) | Paired as a *loan payment* — still counted as an expense, as in Actual |

Two differences in how Sure reports, which are Sure's design rather than import defects:

- **Refunds** (a positive amount in an expense category) count as income in Sure's income
  statement. Actual nets them against the category. Budgets per category still net them.
- **Balance adjustments in off-budget investment accounts** ("Market change", reconciliation
  rows) are income/expense transactions in Sure. Actual kept them outside the budget. Open one and
  tick **One-time** to keep it out of budget analytics, or leave them if you want them counted.

## 1. Freeze Actual

1. Run a final bank sync in Actual. Note the date: this is your **cutover date**.
2. Stop entering transactions in Actual from here on.

## 2. Export

**Either** Actual's UI: open **All accounts**, then the **⋯** menu → **Export**. This downloads the
CSV Sure expects (`Account,Date,Payee,Notes,Category_Group,Category,Amount,Split_Amount,Cleared`).

**Or** headless, which also prints each account's balance for the checks in step 5:

```bash
cd deploy/lab/actual-export && npm install
printf '%s' 'ACTUAL_SERVER_PASSWORD' > pw && chmod 600 pw
ACTUAL_SERVER_URL=https://actual.example.lan ACTUAL_PASSWORD_FILE=./pw ACTUAL_SYNC_ID=<Settings → Advanced → Sync ID> \
  node export.mjs actual-export.csv      # add ACTUAL_BUDGET_PASSWORD_FILE for an end-to-end encrypted budget
shred -u pw
```

It downloads the budget into a temporary directory that is deleted afterwards, never writes back
to Actual, and writes the CSV with mode 600. It is your full financial history: keep it off shared
drives and delete it once the import is verified.

## 3. Create the accounts in Sure first

Create one Sure account per Actual account **before** importing, with the matching type and a
balance of 0 — the import sets the opening balance from Actual's starting balance. Accounts the
import creates on its own are always *Depository*, which is wrong for cards and loans.

| Actual account | Sure type |
|---|---|
| Checking, savings, cash | Depository |
| Credit card | Credit card |
| Mortgage, car loan, student loan (usually off-budget) | Loan |
| 401k, brokerage, IRA (off-budget) | Investment |
| House, car (off-budget, value tracking) | Property / Vehicle |

Use the exact Actual account names; the import matches on name.

## 4. Import

**Imports → New import → Actual Budget**, upload the CSV, then:

1. **Categories**: leave the suggested "Create" for each `Group: Category`.
2. **Accounts**: map every Actual account name to the account you created in step 3.
3. **Publish.** Sure then syncs the family, which pairs transfers and applies your rules.

A wrong import is undone with **Revert** on the import: it removes every imported transaction and
the opening balances the import created (an opening balance that already existed is left as the
import set it).

## 5. Check before connecting the bank

For each account, Sure's balance must equal Actual's to the cent (the export tool printed them).
Liabilities read with the opposite sign: Actual shows a mortgage as `-294000.00`, Sure as a Loan of
`294,000.00` owed; an overpaid card is `+910.00` in Actual and a Credit card at `-910.00` in Sure.

Also check:

- **Transfers → count** matches the transfers you had in Actual (card payments, mortgage payments,
  moves to savings). Unpaired ones show as ordinary income/expense; pair them from the transaction
  (**Match transfer**) — usually a leg whose account you didn't import.
- No category called *Starting Balances* exists, and there are no `$0` "(SPLIT INTO n)" entries.

## 6. Connect SimpleFIN in Sure

A SimpleFIN setup token can be claimed once, and Actual already claimed yours. In the SimpleFIN
Bridge, create a **new** setup token for Sure (and revoke Actual's access afterwards, step 7).

1. **Settings → Bank sync → SimpleFIN**, paste the token. Sure discovers your bank accounts.
2. On the account setup screen, choose **Skip this account** for every account you already
   imported. Choosing a type there would create a *second*, empty account next to the imported one.
3. For each imported account: open its **⋯** menu on the Accounts page → **Link with provider** →
   SimpleFIN → pick the matching SimpleFIN account. (This fork adds the option for Loans too, so an
   imported mortgage can be linked in place.)
4. Once every account is linked, press **Sync** on the SimpleFIN connection (or wait for the next
   scheduled sync). Linking alone doesn't apply anything: SimpleFIN already fetched and stored the
   history in step 1, and the next sync writes it into the linked accounts.

What that sync does with history: Sure asked SimpleFIN for as much as it serves (typically
60–90 days), so it re-sends days you already imported. Each re-sent transaction is matched onto the
imported one on the same account, date and exact amount and linked to it, instead of being added
twice; the imported transaction keeps Actual's payee and category. Verified: SimpleFIN re-sending
`TRADER JOE'S #552 PORTLAND OR` linked onto the imported `Trader Joes / Groceries` entry, and a
genuinely new transaction was added alongside it. Late-posting transactions from just before the
cutover are therefore caught rather than lost.

After the first sync, review what could not be matched exactly:

- **Split transactions**: the import brought in the split lines; the bank re-sends one total, which
  matches none of them and is added as a new transaction. Sure does not flag it (its duplicate
  suggestions only cover pending transactions), so find it yourself: filter the account to the
  overlap window and look for bank totals on the dates of your splits. Delete it, since the split
  lines already account for the money.
- **Transactions you re-dated or re-amounted in Actual** (the bank's version differs): same — the
  bank's copy is added alongside; delete whichever you don't want.

The fewer splits and edits in the last 90 days before the cutover, the less there is to clean up.

## 7. Retire Actual

1. Keep a backup: Actual **Settings → Export data** (a `.zip` of the whole budget).
2. In the SimpleFIN Bridge, revoke the access Actual was using.
3. Stop the `actual` container and archive its volume.
