# Using Sure in India

What works for an Indian household out of the box, and how to set it up. Everything
here is also available to other families; nothing is switched on by country alone.

## Currency and number format

Set **Settings → Preferences → Currency** to `INR`. Amounts use Indian digit grouping
(`₹1,23,45,678.00`). Choosing INR also sets the financial year to start in April
(see below) unless you already picked a month.

## Bank statements (CSV import)

Indian banks are not on SimpleFIN, and Account Aggregator access needs an RBI licence,
so the reliable path is the statement CSV your net-banking portal exports.

**Imports → New → Transactions → upload the CSV.** When the file has separate
withdrawal and deposit columns, Sure recognises it and pre-fills the configuration:

| Bank | Recognised headers |
| --- | --- |
| HDFC Bank | `Date, Narration, …, Withdrawal Amt., Deposit Amt., Closing Balance` |
| ICICI Bank | `Transaction Date, Transaction Remarks, Withdrawal Amount (INR ), Deposit Amount (INR )` |
| State Bank of India | `Txn Date, Description, Debit, Credit` |
| Axis Bank | `Tran Date, PARTICULARS, DR, CR` |
| Any other bank | a date, a narration and separate withdrawal/debit + deposit/credit columns |

What the preset sets, all editable before you continue:

- the header row, even below the account summary banks print first
- the date, narration and amount columns (amount type **Separate withdrawal and deposit columns**)
- the date format, detected from the file (`DD/MM/YY`, `DD/MM/YYYY`, `DD MMM YYYY`, …)
- **Clean up bank narrations**: on for the named banks and for INR families

Export as CSV, not XLS or PDF. If your bank only offers XLS, open it and save as CSV; a
changed header only means you map the columns yourself.

### Narration cleanup

Bank narrations become the counterparty's name; the full original narration is kept in
the transaction's notes, so search and rules can still match on UPI IDs or references.

| Narration | Name |
| --- | --- |
| `UPI-SWIGGY-SWIGGY8@YBL-YESB0YBLUPI-512345678901-PAYMENT FROM PHONE` | Swiggy |
| `TO TRANSFER-UPI/DR/512345678901/SWIGGY/YESB/swiggy@ybl/Pay--` | Swiggy |
| `NEFT CR-SBIN0001234-ACME CORP PVT LTD-SALARY SEP-N123456789012` | Acme Corp Pvt Ltd |
| `IMPS-512345678901-JOHN DOE-HDFC-XXXXXXX1234-TRANSFER` | John Doe |
| `NACH-DR-BAJAJ FINANCE LTD-BFL1234567` | Bajaj Finance Ltd |
| `POS 416021XXXXXX1234 AMAZON PAY INDIA` | Amazon Pay India |
| `ATW-416021XXXXXX1234-S1ACMU12-MUMBAI` | ATM cash withdrawal |

UPI, NEFT, RTGS, IMPS, NACH/ACH mandates (SIP, EMI), card POS, ATM and interest credits
are recognised. Anything else is imported as the bank wrote it.

Re-importing an overlapping statement is safe: a row matching an existing imported
transaction on the same account (same date, amount, currency and name) updates it instead
of adding a copy. Narration cleanup is deterministic, so the names match. Transactions that
came from a bank sync are not matched this way.

## Financial year

**Settings → Preferences → Financial year starts in → April.** The period picker then
offers **Current Financial Year** and **Last Financial Year** (shown as `FY 2026-27`). January 1st (the default) hides them, since
they would repeat Current Year.

## Stocks and mutual funds

- NSE and BSE securities price in INR: search the ticker and pick the `XNSE` or `XBOM`
  listing (for example `RELIANCE` on XNSE).
- Mutual fund NAVs come from [MFAPI](https://www.mfapi.in/) (no key needed): search the
  fund by name; it is tracked under its AMFI scheme code.

## Bills and reminders

Bills live under **Bills** and need preview features (**Settings → Preferences →
Preview features**).

**Add a bill** offers common bills as a starting point: credit card, electricity,
broadband, mobile postpaid, mobile recharge (prepaid), DTH, gas (LPG/PNG), water, rent,
society maintenance, loan EMI, insurance premium, school fees and property tax. Each fills
in a cadence and a reminder lead time; you add the amount, the account and the next due
date. Two details:

- **Mobile recharge** repeats every 4 weeks, which matches 28-day plans exactly (use 8 or
  12 weeks for 56- and 84-day plans). Monthly would drift a few days each cycle.
- **Credit card, electricity, gas and water** estimate the amount from the last payment,
  so a varying bill does not keep the first figure you typed.

### Reminders

A reminder is sent when a bill enters its "remind me" window (per bill under **More
options → Remind me**, 3 days by default) and again if it goes overdue. Each is sent once
per bill and due date (snoozing re-arms it), as one digest, between 8 AM and 10 PM in the
family's time zone. Income is never reminded.

Set up under **Settings → Notifications**:

- **Email**: each member opts in and only hears about bills on accounts they can see.
  Needs SMTP on the server (`SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USERNAME`,
  `SMTP_PASSWORD`, `EMAIL_SENDER`).
- **Push to your phone** (family admin): a self-hosted [ntfy](https://ntfy.sh) topic URL
  (`https://ntfy.example.com/bills`, optional `tk_…` access token), or a JSON endpoint
  such as Gotify's `/message` with its app token. **Send test** checks the channel. The push
  lists the bills the admin who set it up can see.

Sure's built-in mobile push uses Apple's APNs for the hosted app only and is off when
self-hosted, which is why reminders go out through email and your own push server.

Security notes for the push channel:

- Bill names and amounts leave the server. Use your own ntfy/Gotify, or an ntfy topic
  protected by an access token, not a guessable public topic.
- The URL and token are encrypted at rest when Active Record encryption is configured,
  and the token is never sent back to the browser.
- Cloud-metadata and link-local addresses are always refused. Private LAN addresses are
  allowed only on self-hosted installs. The connection is pinned to the checked address
  and redirects are not followed.

## Not included

- **Income tax (80C/80D, regimes)**: limits and rules change every budget; tag the
  transactions (`80C`, `80D`) and filter by financial year instead.
- **Account Aggregator / direct bank sync**: requires an RBI-licensed FIU.
