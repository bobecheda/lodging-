# UI redesign brief — lodging_pos (v2)

Status: designed in Figma; build plan agreed with Claude Code 12 Nov 2026 (9 PRs, story/ui-1 … ui-9). PR 1 (docs, #38) and PR 2 (tokens, #39) merged.
Decided 12 Nov 2026: UB40 goes live AFTER the redesign. Staff are trained once, on v2. The Tue 17 Nov freeze is cancelled; the go-live runbook (docs/go-live.md) still applies, run from the tag cut after PR 9.
Figma: file CVc42Uc4UyoQr366bP3Bca, page "Redesign v2 — Nov 2026" (node 22:447). The old screens on Page 1 are kept for comparison.
Prototype flows on that page: "Receptionist" (Bed board ↔ Receipts tabs; New check-in → Check-in → Cancel) and "Supervisor" (Cash: Setup menu opens/closes).

## Principles (agreed with Bobe, 11 Nov 2026)
1. Problems first: every screen opens with what needs action, then totals, then detail.
2. One job per screen: each screen is one named page pattern (list, detail, form, dashboard, inbox, settings…).
3. Colour always does a job: it identifies (room category, person), summarises (one hero number per screen), confirms (green = good) or warns (butter, red). Never decoration. Each colour has one meaning. Normal things stay calm; problems are loudest.
4. Act where the thing is: void from the receipt, extend from the bed, approve on the item, count/collect on the drawer card.
5. The system calculates; people don't.
6. Status is always visible: online/offline, whose shift, who is signed in.
7. Hierarchy from size and space, not boldness: 3 weights max, none above 600.
8. Blind where it must be: a receptionist never sees cash totals anywhere.
9. Fast for repeated work: shortcuts (N new check-in, / search, Esc close), sensible defaults.
10. Prevent the common mistakes: never pre-select the payment method; confirm line above Save.
11. Fewer words: labels and values only. No explanatory sentences on screen; explanations go in training and the desk sheet. Microcopy only where it prevents an error. No visible page title when it only repeats the active tab (keep a semantic heading for screen readers).
12. Motion explains, never decorates: every animation shows where you went or what changed (see Motion).
13. Responsive: every desk screen works from 768 px to 1920 px wide with no horizontal page scroll (see Responsive).
14. Redesign never removes function: anything a screen does today that a design doesn't show is kept and restyled, unless this brief lists it under Dropped.

## Desk navigation: light top bar (decided 11–12 Nov 2026; colour decided by the owner 12 Nov)
- 64 px white bar with a 1 px line border at the bottom.
- Left: the UB40 wordmark (Pirata One, marine, ~22 px tall; a logo, exempt from the 3-weight rule) + subtitle in Meta 12/500 muted showing the signed-in ROLE: "Front desk" (receptionist), "Supervisor", "Owner". Same in the drawer head.
- Tabs: a 44 px tall pill (radius 8) centred in the 64 px bar; icon 18 + label Secondary medium 14/500, padding 12, gap 8. Default = ink-soft text, muted icon; active = marine text and icon, plus a 3 px marine indicator at the bottom edge of the bar under the tab (the indicator slides between tabs). Count badges in butter.
- Icons: Lucide (the Figma v2/Icon set is Lucide), from a bundled icon-font package that works offline.
- Groups of rarely used pages are a tab with a dropdown menu (Setup ▾). Future pages (reports, expenses, stock) go into a dropdown group, not new tabs, once a role passes ~6 tabs.
- Right, in order: status slot (backup warning, then sync); divider; user button (36 px initials avatar + name + shift/role); Lock button (44 px, surface background, marine icon).
- Avatars: receptionist = marine-tint with marine initials; supervisor = butter with butter-text; owner = marine with white initials.
- Tabs collapse into the menu button whenever they don't fit (not only below 768) — e.g. the supervisor's tabs at 1024.
- Focused flows (close shift, sign-in) have no navigation. Phone keeps its bottom bar.
- Buttons: Secondary medium 14/500, height 44, horizontal padding 16.
- The sidebar option is kept in Figma under "Not chosen — sidebar option" for reference only.

## Shell states (PR 3) — Figma "Shell · Top bar states" (node 37:1558) and "Shell · 768 menu open (supervisor)" (node 39:1798)
Top bar:
| State | Look |
|---|---|
| Online (default) | Green dot + "Online" (Meta, muted) |
| Hover (mouse only) | Tab pill gets surface/app background; label turns ink. Never the only cue for anything |
| Keyboard focus | 2 px marine ring outside the pill (radius 8). Same ring on every focusable control, incl. Lock, the user button and the menu button. Parents must not clip it |
| Offline | Sync area becomes a butter pill: dot + "Offline · N waiting" in butter-text (N = outbox rows not yet pushed). Nothing else on the bar changes; work continues |
| Syncing | Muted dot + "Syncing · N", N counting down; back to Online at 0 |
Top tab component (v2/Top tab) has variants Default, Active, Hover, Focus.

Status slot — other states (same slot, today's wording kept short; all open the Cloud sync panel when tapped):
- Warnings (butter pill): not set up, not connected, owner sign-in needed, records not in the cloud, PC clock wrong.
- Uploading: muted, like Syncing.
- Sync problem (rows refused/stuck): red-tint pill with red-text — the one urgent sync state.
- Backup failed or overdue: a separate butter pill to the LEFT of sync ("Backup failed · last Sun 18 Oct"), shown only then; a supervisor's tap opens Prices & settings (Backups); for others it is not tappable.

User button (replaces the sidebar user block): clicking the avatar + name opens a small menu in the Setup ▾ style (white card, 44 px rows):
- "Close shift" — only when this user has an open shift.
- "Change my password" — for users who can change it today (owner).
The drawer footer gets the same rows above "Lock screen".

Menu drawer (when tabs don't fit; drawn at 768 for the supervisor):
- Opens from the menu button (left of the wordmark); slides in from the left, 304 px wide, full height; white, 1 px line border on the right, soft shadow; scrim ink 35% over the page.
- Head: wordmark + role subtitle, Close (X, 44 px).
- Rows: 48 px, icon 20 + Body medium 16/500, radius 8. Active row = marine-tint background, marine text and icon, 3 px marine bar on its left edge. Badges in butter at the row's right.
- Groups (Setup, temporary More) are plain sections in the drawer: Meta label, then its pages as rows (no dropdown inside the drawer).
- Footer (above a 1 px line): status ("Online · synced 1 min ago" / the offline pill), avatar + name + role, then Close shift / Change my password rows when they apply, then full-width Secondary "Lock screen".
- Per role: receptionist = Beds, Receipts, Guests, Refunds; supervisor = Beds, Receipts, Guests, Refunds, Cash, Setup (Rooms & beds, Prices & settings, Staff); owner desk = Today, Cash, Receipts, Prices, Staff. Plus the temporary More section below while it exists.
- Motion: drawer 220 ms ease-out in, 200 ms ease-in out; scrim fades 150 ms. Closes on X, scrim tap, Esc, or choosing a page. Focus is trapped inside while open and returns to the menu button on close.
- While the drawer is used, the top bar keeps: menu button, wordmark, status, avatar, Lock. User name hidden.

Badges:
- Refunds: refunds to pay (as today). Owner's Prices: price requests (as today).
- Cash: reviews still awaiting a decision that THIS user is allowed to decide (so the supervisor never counts his own shifts). Never shown to a receptionist.

Temporary "More ▾" (PR 3 → removed in PR 8): for the supervisor and the owner, holds Shifts and Voids until PR 7 merges Shifts into Cash and PR 8 moves voiding onto the receipt view. Same dropdown style as Setup ▾.

Reduced motion fallback: if Windows "Show animations" doesn't reach Flutter, add a "Reduce motion" switch in Prices & settings (supervisor only), stored per desk PC, applying app-wide.

## Bed panel (PR 5) — Figma "Bed panel · states" (node 42:1947) and "Desk · Bed panel open (overstay)" (node 42:2213)
- A slide-over from the right, 440 px wide, full height, over the ink 35% scrim; soft shadow, no radius on the screen edge. Opens 220 ms ease-out; closes on X, scrim tap or Esc (focus returns to the bed tile). Stays a dialog (showBedPanel); /home?stay= still reopens it.
- Head: bed number (Page title 24/600), category + price under it in the category's label colour (e.g. "Comfort · KES 600 a night"), status pill (Ready marine-tint · Occupied marine-tint · Overstay red/white · To clean butter), Close X 44 px.
- Body: only what the state needs. Actions sit in a footer bar above a 1 px line, full-width buttons, primary first.
- Guest row: neutral avatar circle with a person icon, name (Body medium), phone masked "0722 ••• 310" for everyone at the desk.

| State | Body | Actions |
|---|---|---|
| Ready | No panel (decided 24 Nov): tapping a Ready tile goes straight to check-in, as today. "Cleaned 08:15 · Mary" shows in the check-in bed row instead | — |
| Occupied | Guest; Checked in; Paid until; Nights "6 × KES 500"; Receipts (number · method, amount; tap opens the receipt) | Extend stay (primary) + Check out (secondary) side by side; "Void this stay" as a red-text link below — shown only with voidRecords |
| Check out — early | Guest; Nights paid; Nights used "2 (tonight counts)"; grey box: "Refund · 4 × KES 500", KES 2,000 (Money hero), "Needs approval before it is paid" | "Check out and request KES 2,000" (primary, amount in the label) + Back |
| Check out — on time / late | As today's flow, restyled (late: "Charge 1 night and check out") | — |
| Overstay | Red-tint banner "2 h past 10:00 · paid to Wed 11 Nov"; guest; "Extend": nights stepper + "Out Thu 12 Nov, 10:00"; Price "KES 600 (check-in price)"; Cash / M-Pesa with NONE selected; confirm line (grey until a method is chosen, then e.g. "Cash · KES 600 · out Thu 10:00"); M-Pesa code field appears only for M-Pesa | "Extend and print receipt" (primary, disabled until a method is chosen) + "Charge 1 night and check out" |
| Occupied → Extend | Same Extend block as Overstay, without the banner | Same |
| To clean | Butter-tint banner "Checked out today 09:40"; Housekeeper select | Assign cleaning (primary) + Mark clean (secondary). Once assigned: banner adds "Assigned to Mary · 09:45" and Mark clean becomes primary |
| Void stay (supervisor/owner) | Red-tint banner "Voids the stay and its payments"; guest + "Checked in by Akinyi · Mon 9 Nov"; each payment "R-000412 · Cash  − KES 3,000"; "Bed after void · To clean"; Reason (required) | Void stay (Danger) + Cancel. Refused (with the reason shown) if the user checked the guest in, or the stay has a refund |
- Receptionists never see totals beyond the stay's own payments (blind rule unaffected: these are single-stay figures they already print).

## Bed board — fixes after the first build (decided 25 Nov 2026; overrides earlier bed-board text)
Problem seen on the real build: with 11 overstays and 14 beds to clean, the Now strip filled the screen and the room grid was not visible; To clean chips were full-width bars; tab labels were clipped.

Rule: the Now strip is a SUMMARY, never a list. The room grid must start within the first screen at every width. The strip is at most ~25% of the content height.
- Each card only appears when its count > 0. If both are 0, the strip is gone.
- Both cards: same height, hug their content, side by side (50/50) at ≥ 1024; stacked below that.
- Overstay card: head "Overstay 11" (icon circle + count). Up to 3 rows, oldest first. Row = 44 px, tappable, opens that bed's panel (where Extend / Check out live): "A9 A · Bobe" (Body medium) left, how long right in red-text ("32 days", "2 h"). No buttons on the rows. If more than 3: a last link row "+ 8 more · Show all" that turns on the Overstay filter chip (grid shows only overstays).
- To clean card: head "To clean 14". Bed chips HUG their text (e.g. "A5 A"), 36 px tall, 8 px gaps, wrapping left-to-right, at most 2 lines. A chip opens that bed's panel. If they don't fit in 2 lines, the last chip is "+ 6 more", which turns on the To clean filter.
- Long overstays: under 24 h show hours ("2 h"); from 24 h show days ("32 days").
- Filter chips row and the room grid follow directly; the grid is the main content.

Search on the bed board: DROPPED (decided by Bobe 25 Nov). Remove the "Guest or receipt" box, the receipt results under it, and the "/" shortcut from the board. Finding a guest → Guests tab; finding a receipt → Receipts tab. The header row keeps the date and "New check-in" (N shortcut stays).

Top bar labels must never be clipped or ellipsized. The fit check measures the tabs with the REAL text scale (Windows display scaling, e.g. 125–150%) and folds the tabs into the menu button when they don't fit. Same for the subtitle under the wordmark ("Supervisor" never becomes "Supervis…"): if space is short, the user name hides first, then the tabs fold.

## Check-in (PR 6) — Figma "Desk · Check-in (full)" (node 43:2187) and "Check-in · variants" (node 44:2248)
Form pattern; left card (Bed, Guest, Nights, Payment) + right summary card (360 px). Fits 1366×768 without scrolling.
- Bed: the chosen bed as a row with a 1.5 px marine border: letter box, "104 A", meta line in the category label colour "Comfort · KES 600 a night · cleaned 08:15 · Mary", and "Change" (marine text button, 44 px tall).
  - Change opens the bed chooser: a menu card listing only Ready + clean beds (BR-5), grouped by category (label in category colour + price), each bed an 80×44 chip; the chosen one solid marine.
  - Whole room switch under the bed row, for 2-bed rooms only. Off by default. Disabled with the reason when the other bed isn't Ready ("· 104 B has a guest"). On: the bed row reads "107 A + 107 B · KES 500 a night each"; the summary says "2 beds × 2 nights × KES 500 · one receipt" (BR-4: two stays, one payment).
- Guest: ONE search box for phone or ID number, matching as you type (FD-3).
  - Matches while typing: a list with MASKED phones and IDs. Under the list: "New guest with this phone" (families share phones) — opens the new-guest form with the phone filled and the shared-phone notice.
  - Selected: a marine-tint row with a check, name, the FULL phone (so staff can confirm it with the guest — masking applies to lists and search results only; CLAUDE.md rule unchanged), masked ID ("National ID ••••3921"), stay count, and "Not this guest" to clear. (The Figma frame shows the phone masked — the brief wins.)
  - No match: "No guest with this phone or ID — new guest", then Phone and Full name side by side (Phone is filled when the search was a phone; ID number is filled when it was an ID), then "ID (optional)" as a 3-way choice National ID / Passport / Alien ID (none chosen until tapped) and ID number. If an ID number is typed, a type is required.
  - Duplicate ID: "This National ID is already registered to Grace Wanjiru · 0722 ••• 310." with a "Use this guest" button beside it that selects that guest.
- No bed chosen yet (New check-in from the board): the bed row reads "Choose a bed" with a Choose button that opens the same chooser.
- Whole room with two different prices: "107 A + 107 B · KES 500 + KES 600 a night"; the summary shows one line per bed, then "· one receipt".
- Widths: at 1024 the two columns stay side by side; at 768 the summary moves under the form. Longer states scroll inside the form card while the summary stays put.
- After saving: today's "Checked in" view with the receipt, Print, Back to bed board and Check in another guest, restyled. No print dialog opens by itself.
- Pictures (for when Figma's monthly limit is reached): docs/design/v2-check-in-main.png, v2-check-in-variants.png (the variants picture still shows an old grey "Type the full name" in the empty name field — empty fields have no placeholder), v2-bed-panel-states.png, v2-bed-panel-open.png.
  - No placeholders in empty fields except format hints.
- Nights: stepper + "Out Fri 13 Nov, 10:00".
- Payment: Cash / M-Pesa, none pre-selected; the chosen one turns solid marine with white text (stronger than other selections, because this is the most common mistake). M-Pesa code field only for M-Pesa.
- Summary: Total (Money hero), "2 nights × KES 600", confirm line ("M-Pesa · KES 1,200 · out Fri 10:00"; grey "Choose Cash or M-Pesa" until chosen), Save and print receipt (disabled until bed, guest, nights and method are valid), Cancel.
- No open shift: the page shows a centred card instead of the form — butter clock circle, "Open your shift first", "Check-ins and payments need an open shift.", Open shift (primary, if this user may open one) and Back to beds.

## Colour system (v2)
| Colour | Token | Meaning |
|---|---|---|
| Marine #0B2E59 | brand/marine | Brand and action only: primary buttons, active tab, Ready border, hero card background, links, focus, owner avatar |
| Light blue #EAF1FA | brand/marine-tint | Occupied bed (quiet), selected chip, active drawer row, receptionist avatar |
| Red #D62839 | status/red | Overstay and urgent only (incl. the sync-problem pill, as red-tint) |
| Butter #F7E3A1 (tint #FDF6DE) | status/butter, status/butter-tint | Needs cleaning, warnings, count badges, offline, backup warning, supervisor avatar |
| Green #1E7B4F (tint #E6F4EC) | status/green, status/green-tint | Good: online, money up, count matched, saved |

Room category colours (palette keys, stored on bed_categories.colour; stripe needs 3:1, text needs 4.5:1 on white):
| Key | Stripe | Label text | Seed category |
|---|---|---|---|
| gold | #B8862B | #7A5A12 | VIP |
| violet | #5B4B9A | #5B4B9A | Deluxe |
| teal | #1F7A86 | #1F7A86 | Comfort |
| slate | #6B7A90 | #4A5568 | Normal |
| plum | #8A3F7A | #8A3F7A | spare (5th category) |
| bronze | #6E5B3E | #6E5B3E | spare (6th category) |
New categories take the next unused key; the owner can change it from a swatch menu in Prices. Category colour only appears on room cards (stripe + label) and category charts; the label text always stays, so colour is never the only signal.

Other colour rules:
- Hero card: one per screen at most, marine background with white money and light labels (Cash: "Drawer should hold"; owner Today: "Collected today"). Buttons on a hero card: white primary, outlined secondary. Never on a receptionist screen (blind rule).
- Money split bars (cash vs M-Pesa): two shades of one hue — M-Pesa marine, cash marine-tint with marine outline — never gold (gold belongs to VIP; the old M-Pesa gold #C9962E is retired).
- To-clean tiles keep the butter fill and dashed butter-border; the dash pattern distinguishes them from the VIP stripe.
- Alert cards (bed board Now strip): 32 px tinted icon circle (red for Overstay, butter for To clean) before the title.
- Trends: "▲ 8% vs usual Wed" in green; down trends in red-text with ▼. Arrow + number, never colour alone.
- 60-30-10 still holds: page background ~60%, white cards and bar ~30%, colour ~10%.
- Not used: cream #F5EDD8 on surfaces (too close to butter); red for badges; gradients; shadows on cards.

## Motion (tokens for the build)
| Moment | Animation | Duration / easing |
|---|---|---|
| Tab change | Indicator slides to the new tab; content fades out, new content fades in and rises 8 px | Indicator 200 ms ease-out; content out 120 ms ease-in, in 180 ms ease-out |
| Open a flow (New check-in, a decision, drawer count) | Fade + 16 px slide in the direction of travel; back reverses it | 250 ms ease-out / 200 ms ease-in |
| Dropdown menu (Setup ▾, More ▾, user menu) | Fade + 4 px drop | Open 150 ms ease-out, close 120 ms ease-in |
| Menu drawer (narrow) | Slides in from the left; scrim fades | 220 ms ease-out in, 200 ms ease-in out; scrim 150 ms |
| Bed panel (dialog) | Slides in from the right; scrim fades | 220 ms ease-out; scrim 150 ms |
| Counts and badges | New number cross-fades | 150 ms |
Rules: only opacity and transform animate (never width, height or layout). The top bar never moves (DeskShell stays a ShellRoute). Input is never blocked during an animation. No bounce, no counting-up money. Reduced motion (Windows "Show animations" off → MediaQuery.disableAnimations; fallback: the "Reduce motion" desk setting above): switch instantly, opacity only. Esc closes menus, the drawer and panels and returns focus to the control that opened them.

## Responsive (desk app window; also the web/PC builds)
Breakpoints: narrow < 768, medium 768–1279, wide ≥ 1280.
- Wide (≥ 1280): full top bar; room grid 6 columns; Now strip = Overstay and To clean side by side. On very wide screens the page content is capped at 1280 px and centred; the top bar stays full width.
- Medium, landscape (~1024): room grid 4 columns; the overstay card stacks guest above its buttons; tabs keep labels if they fit.
- Medium, portrait (768): tabs collapse into the menu button and drawer (see Shell states); Now strip = Overstay full width, To clean below it; room grid 3 columns.
- Narrow (< 768, not drawn): room grid 2 columns, Now strip stacked, search becomes an icon button.
- Never: horizontal page scroll, text below 12 px, hit targets below 44 px. Wide tables scroll inside their card.

## Navigation (end state, includes AD-11)
| Role | Where | Home | Rest |
|---|---|---|---|
| Receptionist | Desk | Beds | Receipts, Guests, Refunds. Close shift in the user menu. |
| Supervisor | Own phone/PC (owner app, supervisor role) | Decisions | Beds, Cash, Staff (read-only), Audit |
| Supervisor | Desk, on site | Beds | Receipts, Guests, Refunds, Cash, Setup ▾ (Rooms & beds, Prices & settings, Staff) |
| Owner | Phone | Today | Money, Beds, Prices, More (Cash, Audit, Staff, Password) |
| Owner | Desk | Today | Cash, Receipts (view and void; no printing), Prices, Staff |

Removed as destinations: Shifts (merged into Cash in PR 7), Voids (action on the receipt view and the bed panel in PR 8), phone Reports placeholder (hidden until AD-9). Until then they sit in the temporary More ▾.
"Decisions" is one shared queue, filtered by permission (supervisor and owner). Until AD-11, Cash "Review" opens the existing approve/reject box.

## Screens designed (Figma frame names)
- Desk · Bed board — top nav (receptionist) — plus "— 1024 wide" and "— 768 wide". Now strip: Overstay, To clean. Filter chips. Room grid with category stripes.
- Desk · Receipts (receptionist): search by receipt number or phone; table (receipt, guest, bed, method, amount, time, Print copy). No totals.
- Desk · Check-in: Guest / Nights / Payment; summary with total and confirm line above "Save and print receipt". No default payment method. Today's bed chooser, "let the whole room", search by ID number and the "Open shift" note are kept (principle 14) and restyled.
- Desk · Close shift — count / — second count: blind; one large cash field; mismatch message has no amount.
- Desk · Cash — top nav (supervisor) and "…, Setup open": marine drawer hero (should hold / last check / last collection + Collect cash / Count drawer); To review; History (drawer chain). Takes over Shifts: open shifts with Close, needs-review rows, voided-after-close marks.
- PC · Needs your decision (supervisor): split pane queue + detail; Approve refund / Reject. (Built with AD-11.)
- Phone · Owner Today: Needs you → Collected today (marine hero) → Beds now → Drawer should hold (new: computed on the phone with the desk's drawer rules, tested to match) → This month.
- Shell · Top bar states; Shell · 768 menu open (supervisor).
- Bed panel · states (six panels); Desk · Bed panel open (overstay).
- Desk · Check-in (full); Check-in · variants (bed chooser, whole room on, new guest, no open shift).

## Bed-board search ("Guest or receipt")
The board filters in memory as today (room number exact, occupant name part, phone start). Under the box, up to 5 matching receipts (existing receipts query). A name never searches receipts. Digits alone = room; a receipt needs the prefix (R-418) or 5+ digits.

## Dropped (do not build)
- "Due out by 10:00" card and its business rule — removed by Bobe, 12 Nov 2026. Occupied tiles still show the guest and paid-until, as today.
- Receptionist monthly takings PDF (FD-12) — breaks the blind count.
- Bed-board search box ("Guest or receipt", receipt results, "/" shortcut) — removed by Bobe, 25 Nov 2026. Use the Guests and Receipts tabs.

## Type and components (v2 tokens in Figma)
- Text styles v2/*: Page title 24/600, Section title 18/600, Body 16/400, Body medium 16/500, Secondary 14/400, Secondary medium 14/500, Meta 12/500 (meta only), Money hero 30 mono/600, Money 18 mono/600, Money small 14 mono/500. Manrope (incl. 400) + IBM Plex Mono.
- Bed tiles: Ready = white + 1.5 marine border; Occupied = marine-tint + field border (quiet); Overstay = red; To clean = butter, dashed.
- Menus: white card, 1 px line border, soft shadow (alpha ≤ 0.08), 44 px rows, hovered row marine-tint.
- Components: v2/Icon/* (incl. menu, x), v2/Top tab (Default/Active/Hover/Focus; Label, Icon, Badge, Count, Dropdown), v2/Bed tile, v2/Button (Primary/Secondary/Danger), v2/Filter chip, v2/Field. (v2/Nav item and v2/Nav group belong to the archived sidebar option.)

## Open decisions
- Owner to confirm: quieter occupied tile (changes his original "occupied = solid marine" rule) and the category colours (gold / violet / teal / slate). PR 5 waits on this; PR 3–4 don't.
- AD-11 after go-live (recommended; adding it first pushes go-live into the Christmas period) — owner to confirm.

## Next
1. Build in order, one PR at a time: story/ui-3-shell → ui-4-category-colours → ui-5-bed-board → ui-6-check-in → ui-7-cash → ui-8-receipts-voids → ui-9-owner-phone.
2. Designs still needed: refunds, guests, setup screens, owner desk Today, owner phone Money/Beds/Prices/More. (Bed panel and full check-in done 24 Nov.)
3. Also in flight: story/desk-db-guards (startup checks, high-water mark, build stamp, single-instance lock, location warning, version on screen) — before PR 4.
4. Before go-live (~mid-December): clickable test with the receptionist and supervisor on the v2 build (5 tasks), fixes, regression, tag, then docs/go-live.md.
