# Lodging Management System — PRD

Version 1.0 · Oct 13, 2026 · @Bobe cheda

## Product summary

A front desk and admin system for a lodging that charges guests per bed, per night, with checkout at 10:00. The front desk app works offline on the reception PC; the owner manages and monitors the business from his phone or PC, from anywhere.

**Problem**

- Guests are charged per bed, not per room, and rooms hold one or two beds of different prices. Tracking this on paper is slow and error-prone.
- The owner cannot see occupancy, takings or stock unless he is on site.
- Cash and M-Pesa takings cannot be reconciled against beds actually let, so revenue can go missing unnoticed.
- The internet at the lodging is unreliable, so a cloud-only system would stop the front desk.

**Solution**

Every let bed is tied to a guest, a payment, a receptionist and a shift. The system enforces pricing, checkout times, overstay and cleaning rules, keeps an append-only audit trail, and gives the owner a live dashboard of revenue, expenses, profit and occupancy.

The detailed data model and architecture are in the companion doc, *Lodging Management System — Requirements & Plan*.

## Goals and success metrics

Success is measured over the first three months after go-live. There is no digital baseline today, so the first month sets it.

| Goal | Metric | Target |
| --- | --- | --- |
| No unrecorded lets | Beds flagged as used without a stay | 0 unexplained per month |
| Cash matches records | Shift cash variance | Under 1% of shift takings |
| Overstays charged | Overstays resolved by renewal or checkout | 100% |
| Fast front desk | Time to check in a returning guest | Under 1 minute |
| Fast front desk | Time to check in a new guest | Under 2 minutes |
| Works through outages | Front desk downtime caused by internet | 0 |
| Owner visibility | Delay before desk data reaches the dashboard, while online | Under 5 minutes |
| Owner adoption | Days per week the owner opens the dashboard | 5 or more |
| Profitability insight | Months with expenses fully recorded | Every month from month 2 |

## Users

Three roles log in (owner, supervisor, receptionist); housekeepers and guests appear in the system but do not use it. Until 21 Oct 2026 the supervisor was called "admin".

| User | Who | Device | Needs |
| --- | --- | --- | --- |
| Receptionist | 1 now, 2 in shifts later; moderate computer skills | Front desk PC, often offline | Check guests in fast, take payment, print or share receipts, see which beds are free and clean |
| Owner | The business owner; often away from the lodging | Phone, online (sprint 2) | See takings and profit, catch missing money, approve refunds and price changes, manage supervisors |
| Supervisor | Runs the lodging day to day | Front desk PC | Set up rooms, beds, settings and staff; void mistakes; close shifts left open; everything a receptionist does |
| Housekeeper | Cleaning staff; does not log in | None | Picked from a list when assigned a bed |
| Guest | Walk-in customer | None | A fair charge and a receipt |

## Scope

The MVP covers walk-in guests end to end, cash and Paybill with manual codes, and the owner's dashboard; reservations and integrations come after.

| In the MVP | After the MVP |
| --- | --- |
| Walk-in check-in, renewal, checkout | Phone bookings, Booked status, deposits, no-show rule |
| Cash and Paybill (M-Pesa code typed in) | Automatic M-Pesa confirmation via Daraja |
| Receipts on screen and PDF | Thermal receipt printer |
| Bed board with occupancy and cleanliness | Overstay fines, if the owner decides on them |
| Shifts and cash-up, voids, audit trail | Second receptionist working in shifts (model already built in) |
| Housekeeping assignment, inventory stock in and out, expenses |  |
| Offline front desk with cloud sync; admin app on phone and PC |  |
| Dashboard and monthly PDF reports |  |

## Front desk stories

Each story lists the conditions that must all hold before it counts as done.

**FD-1 Log in and open a shift.** As a receptionist, I want to log in and open my shift so that my takings are counted separately.

- Login works with no internet, using the last synced credentials.
- No check-in or payment is possible without an open shift.
- Opening a shift records the opening cash float.

**FD-2 See the bed board.** As a receptionist, I want to see every bed's status at once so that I know what I can let.

- Each bed shows room, label, category, price, occupancy (Available, Occupied, Overstay) and cleanliness (Clean, Not cleaned).
- Occupied beds show the guest name and paid-up time.
- Can filter by category, occupancy and cleanliness.
- Overstay beds are highlighted and listed at the top.
- Shows the time of the last successful sync.

**FD-3 Register or find a guest.** As a receptionist, I want to find a returning guest by ID number or phone so that check-in is fast.

- Search by ID or passport number, or phone, returns matches as I type.
- New guest requires full name and phone; ID type (National ID, Passport, Alien ID) and number are optional.
- An ID (type and number), when entered, cannot be registered twice; the same number under a different ID type is a different document.

**FD-4 Check a guest in.** As a receptionist, I want to let a bed for a number of nights so that the guest gets a bed and the money is recorded.

- Only beds that are Available and Clean can be chosen.
- Choosing both beds of a 2-bed room creates two stays on one receipt.
- Entering the number of nights shows the total and the checkout date and time (always 10:00).
- The bed becomes Occupied only after payment is saved; cancelling leaves it Available.
- The price used is the category price at that moment and does not change later.
- A check-in is for 1 to 30 nights (typed or stepped).
- Saving re-checks what the screen showed: if the price, the bed's category or the checkout date changed meanwhile (e.g. the screen opened before midnight and was saved after), nothing is saved and the screen says what changed.
- A new guest is registered in the same transaction as the check-in, so a cancelled or failed check-in leaves no stray guest.
- The payment goes into the user's own open shift. A supervisor with no shift of their own can open one from the check-in screen ("Open shift") and comes back to the check-in; signing in as admin never forces the shift screen.

**FD-5 Take payment.** As a receptionist, I want to record cash or Paybill so that every let is paid. *Done with FD-4: the payment is part of the check-in transaction.*

- Method is Cash or Paybill; Paybill requires the M-Pesa transaction code.
- An M-Pesa code already used is rejected with a message showing where it was used.
- The amount must equal the total due.

**FD-6 Issue a receipt.** As a receptionist, I want a receipt for each payment so that the guest has proof.

- Generated automatically after payment, with the next sequential number.
- Header shows the lodging name only; body shows receipt number, guest, room and bed, category, nights, check-in, check out by, amount, method, M-Pesa code, receptionist.
- Can be viewed on screen and saved as PDF; reprints are marked "Copy".
- The first print or PDF save is the original; every later one says COPY. Viewing on screen or cancelling the print dialog doesn't count.
- A Receipts screen finds any receipt by its number or the guest's phone (not by name; phones masked) to view, print or save again.
- The receipt shows the room number and bed as let, even after a room is renumbered.
- Footer: "Thank you for staying with us." and "Checkout is at 10:00. After 11:00, one more night is charged." (the stay's checkout time plus the grace setting).

**FD-7 Extend a stay or flag an overstay.** As a receptionist, I want overstays flagged so that no extra time goes unpaid.

- One hour after expected checkout, the bed shows Overstay without anyone acting.
- Extending adds nights from the paid-until 10:00, with a new payment and receipt. Checking out after the grace hour first charges one night.
- Extend is in the bed panel above Check out, and on the overstay bar beside Check out. 1–30 nights, one bed per extension, at the stay's check-in price, paid now (Cash or M-Pesa) into the user's own open shift; the payment form is the confirmation.
- During an overstay the minimum is the nights already started, counted exactly as a late checkout at that moment would (`lateNights`), and the card says why ("At least 3 nights: 3 have started since Fri 10:00."). Within the grace hour the minimum is 1.
- The receipt shows "Charge: Extension · n nights", From the old checkout and Check out by the new one, with the usual footer.
- An early checkout after an extension refunds unstarted nights across all of the stay's charges, at its locked price.
- Overstay clears only by renewal or checkout.

**FD-8 Check a guest out.** As a receptionist, I want to close a stay so that the bed can be cleaned and let again.

- Checkout records the actual time; the bed becomes Available and Not cleaned.
- Early checkout closes the stay at once and creates a refund request for nights not yet started, at the check-in price.
- Checking out after paid-until + grace first charges each night started (normally 1) at the stay's price, with its own payment (Cash or M-Pesa) and a late-checkout receipt.
- What a checkout costs or refunds is worked out again when it's confirmed; if a night or the grace time started meanwhile, nothing is saved and the panel says what changed.
- Checkout needs the user's own open shift (BR-12).
- *Sprint 2, with AD-7:* once the owner approves a refund, the receptionist pays it from the cash drawer or the Paybill account (with the M-Pesa code) and a refund receipt is printed; the payout reduces that shift's cash or Paybill total.

**FD-9 Assign housekeeping.** As a receptionist, I want to assign a dirty bed to a housekeeper so that it gets cleaned.

- Only Not cleaned beds can be assigned; the housekeeper is picked from the supervisor's list.
- Marking the task done sets the bed to Clean and records the time.
- A room shows Not cleaned while any of its beds is Not cleaned.
- A housekeeper with an unfinished cleaning task cannot be deactivated: "Rose has a bed to clean. Finish or reassign it first."
- A cleaning can be reassigned to another housekeeper; "Already cleaned · mark clean" records the task and its completion in one step.
- Closing a bed or room cancels its open cleaning task; the bed stays Not cleaned and needs assigning again when reopened.
- No shift is needed: no money moves.

**FD-10 Record stock movements.** As a receptionist, I want to record stock in and out so that the owner knows what is on hand.

- Each movement has item, direction (in or out), quantity, reason, date.
- Stock out cannot take an item below zero.
- Current stock is shown per item.

**FD-11 Close a shift.** As a receptionist, I want to close my shift with a cash count so that my takings are reconciled.

- Shows expected cash (float + cash payments) and expected Paybill total.
- Requires the counted cash; the variance is saved and shown to the supervisor (and the owner, sprint 2).
- A closed shift cannot be reopened.
- The count is blind: the cash counted is entered before the expected amount is shown. A recount is allowed; the first count is kept beside the final one.
- A short or over variance needs a note (at most 200 characters).
- A supervisor can close someone else's open shift (e.g. left open overnight), recorded as "closed by X for Y's shift"; a blocked receptionist is told who can close it.
- The supervisor's Shifts screen lists shifts with their variance, highlighting any over 1% of the shift's takings, with the recount and the note.

**FD-12 Download my monthly report.** As a receptionist, I want a PDF of my takings for the month.

- Covers only that receptionist's own shifts: takings by day and method, and shift variances.
- Does not show other receptionists' takings, expenses or profit.

## Admin stories

AD-1 to AD-4 run on the desk app as the **supervisor** (sprint 1). The owner's own sign-in and screens (phone, online; every change reaches the desk on its next sync) are sprint 2 stories; "admin app" still names that app.

**AD-1 Log in as admin.** As the owner, I want my own login so that only I can change prices and see the full business.

- Admin login works on phone and PC with internet.
- Admin-only screens are hidden from receptionist accounts, and the cloud refuses admin actions from them.

**AD-2 Set up rooms and beds.** As the owner, I want to add rooms and beds so that the system matches the lodging.

- Add and edit rooms (number, floor) and beds (label, category).
- A room holds one or two beds.
- Rooms and beds can be deactivated for repairs; their history is kept and they leave the bed board.

**AD-3 Set prices and rules.** As the owner, I want to set prices so that the desk always charges correctly.

- Set the price per night for each category; prices can be changed at any time.
- Set the checkout time (10:00) and the grace period (1 hour).
- New prices apply to check-ins after the desk syncs; existing stays keep their price.
- Every change is in the audit trail with old and new values.

**AD-4 Manage users and housekeepers.** As the owner, I want to control who uses the system.

- Create, disable and reset receptionist accounts; a disabled account cannot log in, even offline after the next sync.
- Add and deactivate housekeepers.

**AD-5 See the dashboard.** As the owner, I want a live view of the business so that I can run it from anywhere.

- Today: beds occupied, available, overstay and not cleaned; cash and Paybill collected; open shift.
- Month: revenue, expenses, profit, occupancy by category, revenue per available bed.
- Alerts: overstays, shift variances, beds cleaned with no stay, low stock, voids.
- Shows when the desk last synced.

**AD-6 Record expenses.** As the owner, I want to record expenses so that I see profit, not just revenue.

- Category (laundry, utilities, wages, supplies, repairs, other), amount, date, note.

**AD-7 Void a wrong entry.** As the owner, I want to correct mistakes without hiding them.

- Only a supervisor can void a stay or payment, and a reason is required. Only the owner can approve or reject a refund request (a rejection needs a reason); nobody can approve a refund they requested themselves; the amount cannot be changed.
- The original stays visible, marked void; totals exclude it.

**AD-8 Review the audit trail.** As the owner, I want to see who did what so that I can investigate problems.

- Filter by user, date range and action.
- Entries cannot be edited or deleted by anyone.

**AD-9 Download reports.** As the owner, I want monthly reports so that I can track the business over time.

- Monthly PDF: revenue by day and category, payments by method, occupancy, expenses by category, profit, shift variances, voids, inventory movements.
- Can pick any past month.

**AD-10 Manage inventory items.** As the owner, I want to define stock items so that the desk records the right things.

- Add items with a unit and a low-stock level; see current stock and all movements.

## Business rules

These rules are enforced by the system and override anything a user enters.

| ID | Rule |
| --- | --- |
| BR-1 | Price is per bed, per night. Checkout is always 10:00. Every arrival, at any time, checks out at 10:00 the following day. Arrival time does not change the price. |
| BR-2 | Starting prices per night: VIP KES 1,000, Deluxe 700, Comfort 600, Normal 500. Only the owner changes them; a supervisor asks for a change and the owner approves or rejects it. **Temporary:** until the owner can sign in (sprint 2 owner sign-in story), the supervisor changes prices and adds or closes categories directly. |
| BR-3 | The price is locked at check-in and also applies to extensions and refunds of that stay; a price change affects new check-ins only. |
| BR-4 | One guest per bed. Strangers may share a 2-bed room; one guest may pay for both beds. |
| BR-5 | A bed can be let only when Available and Clean, and becomes Occupied only once payment is saved. |
| BR-6 | Grace period is 1 hour after the 10:00 checkout; from 11:00 the bed shows Overstay. |
| BR-7 | An extension adds nights from the paid-until 10:00. Leaving after the grace hour costs one more night. |
| BR-8 | Early checkout refunds nights not yet started. The night in progress is never refunded. The system calculates the amount; the owner must approve it before it is paid from the cash drawer or the Paybill account, with a refund receipt. |
| BR-9 | Checkout makes the bed Available and Not cleaned; only completed housekeeping makes it Clean. |
| BR-10 | Each M-Pesa transaction code can be used once. |
| BR-11 | Stays, payments and audit entries are never edited or deleted; a supervisor voids with a reason. |
| BR-12 | Payments need an open shift; each shift closes with a cash count and recorded variance. |

## Non-functional requirements

These apply across the whole product.

| Area | Requirement |
| --- | --- |
| Offline | Every front desk story works with no internet. Changes queue locally and sync in order when online, with no duplicates and no loss. |
| Sync | While online, desk changes reach the cloud within 5 minutes; admin settings reach the desk within 5 minutes. |
| Time | Checkout, grace, overstay and refund calculations use the desk PC clock, checked against the server time on each sync; a gap over 5 minutes shows a warning. |
| Performance | Bed board loads in under 2 seconds; guest search returns in under 1 second; receipt PDF in under 3 seconds. |
| Security | Passwords stored hashed; admin actions checked by the cloud, not just hidden in the app; data encrypted in transit; sessions time out after inactivity. |
| Privacy | Guest ID data is personal data under the Data Protection Act 2019: only collected fields, visible to logged-in staff only, exportable only by the owner, kept for a period the owner sets. |
| Integrity | Audit log is append-only; receipt numbers are sequential with no gaps; M-Pesa codes unique. |
| Backup | Cloud database exported regularly; a local backup on the desk PC each day; restore tested before go-live. The desk backs up at start (once a day), every hour it's open if the day still has none, after each shift close and on the owner's "Back up now"; each copy is checked (`integrity_check`, schema version) before it counts; every backup from today and yesterday plus the latest of each day for 30 days are kept; an optional second folder (USB drive) gets a copy too, and a missing drive is only noted on the Backups card. The sidebar warns everyone when the main backup failed or yesterday and today have none. Restore steps and the go-live checklist (restore rehearsal, a Windows password on every account, BitLocker or device encryption) are in `docs/backup-restore.md`. |
| Platforms | Front desk: Windows 10 or later. Admin: Android phone and a modern web browser. |
| Usability | A receptionist can complete check-in after 30 minutes of training; English interface; amounts in KES. |
| Maintainability | Built in Flutter with one codebase for desk and admin; schema changes go through versioned migrations. |

## Release plan (Agile)

The project runs as two-week Scrum sprints adapted for one developer, with the owner as product owner. The core goes live at week 4; the rest of the MVP follows in sprint 3 while the system runs on site.

**Capacity**

- About 70 hours a week, planned at about 105 hours of build work per sprint. The rest covers testing, fixes, meetings with the owner and slack.
- The full MVP is estimated at about 300 hours, so it cannot all fit in 4 weeks. Stories are ranked by value, and lower-priority ones move to sprint 3 rather than squeezing quality.
- Estimates are rough and are re-checked at each sprint planning.

**Sprints**

| Sprint | Dates | Goal | Stories | Est. hours |
| --- | --- | --- | --- | --- |
| 1 | 14–27 Oct | A receptionist can run a full stay offline: check-in, payment, receipt, checkout | Project setup and audit logging, FD-1 to FD-6, FD-8 (refund requests; approval and payout move to sprint 2 with AD-7), FD-9 (assign and mark clean, so a checked-out bed can be let again), AD-1 to AD-4 (on the desk app); then CI, FD-11 shift close, FD-7 extend and the daily local backup, in that order | \~118 |
| 2 | 28 Oct–10 Nov | Money is controlled and the owner can see it from his phone | The owner's sign-in (first run creates the owner; `editPrices` moves to the owner; supervisors request price changes), AD-7 (the owner approves refunds; payout and REFUND receipt at the desk), cloud sync, admin app, AD-5 (today and monthly revenue), Windows installer | \~106 |
| **Go-live** | **11 Nov** | **Core in use at the lodging, alongside paper records for the first week** |  |  |
| 3 | 11–24 Nov | Complete the MVP and fix pilot issues | FD-10, AD-10, AD-6, AD-8 (audit trail screen), AD-9, FD-12, full dashboard metrics, pilot fixes | \~90 |

**Priorities (MoSCoW)**

- **Must (by go-live):** login, shifts, bed board, check-in, payment, receipt, renewal and overstay, checkout, cleaning status, voids, audit logging, sync, basic dashboard.
- **Should (sprint 3):** inventory, expenses, audit trail screen, monthly reports, full dashboard metrics.
- **Could (after MVP):** bookings, Daraja, thermal printer.
- If sprint 1 or 2 runs over, Should items move later; Must items do not.

**Ceremonies**

| Event | When | Who | Purpose |
| --- | --- | --- | --- |
| Sprint planning | First day of each sprint, 1 h | Developer, owner for priorities | Pick stories for the sprint goal |
| Daily check-in | Each day, 10 min | Developer | Log done, next, blocked |
| Mid-sprint check | Day 7, 30 min | Developer and owner | Quick look at progress, answer questions |
| Sprint review | Last day, 1 h | Developer and owner | Demo working software; owner accepts or rejects stories |
| Retrospective | Last day, 30 min | Developer | What to keep and change next sprint |

**Definition of Done**

A story is done only when all of these hold:

- Its acceptance criteria pass.
- It works with the internet off.
- It writes audit entries for its actions.
- It is tested on the lodging's Windows PC (or the same Windows version).
- Code is committed, reviewed and merged, with no known critical bugs.
- The owner has seen it in a sprint review.

After sprint 3: maintenance, then the post-MVP features, starting with bookings.

## Risks, dependencies and assumptions

The main risks are people bypassing the system and the desk PC failing; both have mitigations in the MVP.

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Receptionist lets beds outside the system | Lost revenue | Payment-before-occupancy, cleaned-with-no-stay alerts, shift cash-up |
| Fake or reused M-Pesa codes | Lost revenue | Unique code check now; Daraja confirmation after MVP |
| Desk PC fails or is stolen | Lost unsynced data | Frequent sync when online, daily local backup, cloud restore onto a new PC |
| Long internet outage | Owner's dashboard out of date | Dashboard shows last sync time; desk keeps working |
| PC clock changed | Wrong overstay timing | Clock checked against server on each sync, warning shown, change logged |
| Cloud free-tier limits | Service paused | Paid hosting covered by the maintenance agreement before go-live |
| Staff resist the new system | Records incomplete | Simple screens, training, test week alongside paper |

**Dependencies**

- A Windows PC at the front desk, with internet at least some of the day.
- An Android phone or browser for the owner.
- Cloud hosting account (Supabase).

**Assumptions**

- One front desk PC; a second desk device is out of scope.
- One owner account and one supervisor account; receptionists added by the supervisor.
- No bookings or overstay fines in the MVP. Refunds only for prepaid nights not yet started, and only after the owner's approval. Permissions are checked per action, so roles change by editing only the permission map.

**Open items (sprint 2 owner stories)**

- **First run creates the owner.** On a fresh install, first-run setup should create the owner's account, and the owner then creates the supervisor (`manageSupervisors`). Today first run creates the supervisor; not built yet.
- **Prices move to the owner.** `editPrices` (and adding or closing categories) is the supervisor's only until the owner can sign in; then it moves to the owner, the supervisor gets "request a price change" (`requestPriceChange`) and the owner decides (`decidePriceChange`). Marked `// TEMPORARY` in the permission map.
- **Refund approval from the owner's phone** needs sync; until then requested refunds wait. Payouts stay at the desk.

## Approval

Signing confirms the MVP scope, rules and acceptance criteria above; changes after sign-off are agreed in writing.

Owner: \_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_  Signature: \_\_\_\_\_\_\_\_\_\_\_\_  Date: \_\_\_\_\_\_\_\_\_\_

Developer: \_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_\_  Signature: \_\_\_\_\_\_\_\_\_\_\_\_  Date: \_\_\_\_\_\_\_\_\_\_
