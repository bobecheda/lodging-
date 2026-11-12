# UI redesign brief — lodging_pos (v2)

Status: designed in Figma, awaiting owner review and staff test. Build plan agreed with Claude Code 12 Nov 2026 (9 PRs, story/ui-1 … ui-9). UB40 goes live after the redesign (decided 12 Nov 2026; see Timeline).
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
- Left: wordmark "UB40" in marine + role subtitle in muted ("Front desk" / "Supervisor" / "Owner").
- Tabs: icon + label; default = ink-soft text, muted icon; active = marine text and icon, plus a 3 px marine indicator under the tab (the indicator slides between tabs). Count badges in butter. Hover = surface/app background. Keyboard focus = 2 px marine outline.
- Groups of rarely used pages are a tab with a dropdown menu (Setup ▾). Future pages (reports, expenses, stock) go into a dropdown group, not new tabs, once a role passes ~6 tabs.
- Right: online dot (green) + "Online" muted — offline shows a butter label "Offline · N waiting"; divider; initials avatar (36 px circle: marine-tint for receptionists, butter for the supervisor) + user name + shift/role; Lock button (surface background, marine icon).
- Tabs collapse into the menu button whenever they don't fit (not only below 768) — e.g. the supervisor's six tabs at 1024.
- Focused flows (close shift, sign-in) have no navigation. Phone keeps its bottom bar.
- The sidebar option is kept in Figma under "Not chosen — sidebar option" for reference only.

## Colour system (v2)
| Colour | Token | Meaning |
|---|---|---|
| Marine #0B2E59 | brand/marine | Brand and action only: primary buttons, active tab, Ready border, hero card background, links, focus |
| Light blue #EAF1FA | brand/marine-tint | Occupied bed (quiet), selected chip |
| Red #D62839 | status/red | Overstay and urgent only |
| Butter #F7E3A1 | status/butter | Needs cleaning, warnings, count badges, offline |
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
| Dropdown menu (Setup ▾, 768 menu) | Fade + 4 px drop from the tab | Open 150 ms ease-out, close 120 ms ease-in |
| Bed panel (dialog) | Slides in from the right; scrim fades | 220 ms ease-out; scrim 150 ms |
| Counts and badges | New number cross-fades | 150 ms |
Rules: only opacity and transform animate (never width, height or layout). The top bar never moves (DeskShell stays a ShellRoute). Input is never blocked during an animation. No bounce, no counting-up money. Reduced motion (Windows "Show animations" off → MediaQuery.disableAnimations; if Windows doesn't pass it through, a desk setting): switch instantly, opacity only. Esc closes menus and panels and returns focus to the control that opened them.

## Responsive (desk app window; also the web/PC builds)
Breakpoints: narrow < 768, medium 768–1279, wide ≥ 1280.
- Wide (≥ 1280): full top bar; room grid 6 columns; Now strip = Overstay and To clean side by side. On very wide screens the page content is capped at 1280 px and centred; the top bar stays full width.
- Medium, landscape (~1024): room grid 4 columns; the overstay card stacks guest above its buttons; tabs keep labels if they fit.
- Medium, portrait (768): tabs collapse into a menu button (same destinations in a drawer); user name hidden, avatar and Lock stay; Now strip = Overstay full width, To clean below it; room grid 3 columns.
- Narrow (< 768, not drawn): room grid 2 columns, Now strip stacked, search becomes an icon button.
- Never: horizontal page scroll, text below 12 px, hit targets below 44 px. Wide tables scroll inside their card.

## Navigation (end state, includes AD-11)
| Role | Where | Home | Rest |
|---|---|---|---|
| Receptionist | Desk | Beds | Receipts, Guests, Refunds. Shift controls in the user area. |
| Supervisor | Own phone/PC (owner app, supervisor role) | Decisions | Beds, Cash, Staff (read-only), Audit |
| Supervisor | Desk, on site | Beds | Receipts, Guests, Refunds, Cash, Setup ▾ (Rooms & beds, Prices & settings, Staff) |
| Owner | Phone | Today | Money, Beds, Prices, More (Cash, Audit, Staff, Password) |
| Owner | Desk | Today | Cash, Receipts (view and void; no printing), Prices, Staff |

Removed as destinations: Shifts (merged into Cash), Voids (action on the receipt view and the bed panel), phone Reports placeholder (hidden until AD-9).
"Decisions" is one shared queue, filtered by permission (supervisor and owner). Until AD-11, Cash "Review" opens the existing approve/reject box.

## Screens designed (Figma frame names)
- Desk · Bed board — top nav (receptionist) — plus "— 1024 wide" and "— 768 wide". Now strip: Overstay, To clean. Filter chips. Room grid with category stripes.
- Desk · Receipts (receptionist): search by receipt number or phone; table (receipt, guest, bed, method, amount, time, Print copy). No totals.
- Desk · Check-in: Guest / Nights / Payment; summary with total and confirm line above "Save and print receipt". No default payment method. Today's bed chooser, "let the whole room", search by ID number and the "Open shift" note are kept (principle 14) and restyled.
- Desk · Close shift — count / — second count: blind; one large cash field; mismatch message has no amount.
- Desk · Cash — top nav (supervisor) and "…, Setup open": marine drawer hero (should hold / last check / last collection + Collect cash / Count drawer); To review; History (drawer chain). Takes over Shifts: open shifts with Close, needs-review rows, voided-after-close marks.
- PC · Needs your decision (supervisor): split pane queue + detail; Approve refund / Reject. (Built with AD-11.)
- Phone · Owner Today: Needs you → Collected today (marine hero) → Beds now → Drawer should hold (new: computed on the phone with the desk's drawer rules, tested to match) → This month.

## Bed-board search ("Guest or receipt")
The board filters in memory as today (room number exact, occupant name part, phone start). Under the box, up to 5 matching receipts (existing receipts query). A name never searches receipts. Digits alone = room; a receipt needs the prefix (R-418) or 5+ digits.

## Dropped (do not build)
- "Due out by 10:00" card and its business rule — removed by Bobe, 12 Nov 2026. Occupied tiles still show the guest and paid-until, as today.
- Receptionist monthly takings PDF (FD-12) — breaks the blind count.

## Type and components (v2 tokens in Figma)
- Text styles v2/*: Page title 24/600, Section title 18/600, Body 16/400, Body medium 16/500, Secondary 14/400, Secondary medium 14/500, Meta 12/500 (meta only), Money hero 30 mono/600, Money 18 mono/600, Money small 14 mono/500. Manrope (add the 400 file) + IBM Plex Mono.
- Bed tiles: Ready = white + 1.5 marine border; Occupied = marine-tint + field border (quiet); Overstay = red; To clean = butter, dashed.
- Menus: white card, 1 px line border, soft shadow (alpha ≤ 0.08), 44 px rows, hovered row marine-tint.
- Components: v2/Icon/* (incl. menu), v2/Top tab (Default/Active; Label, Icon, Badge, Count, Dropdown), v2/Bed tile, v2/Button (Primary/Secondary/Danger), v2/Filter chip, v2/Field. (v2/Nav item and v2/Nav group belong to the archived sidebar option.)

## Open decisions
- Owner to confirm: quieter occupied tile (changes his original "occupied = solid marine" rule) and the category colours (gold / violet / teal / slate). PR 5 waits on this; PR 1–4 don't.

## Timeline (decided 12 Nov 2026)
- UB40 goes live after the redesign, so the staff are trained once, on v2. The Tue 17 Nov freeze is cancelled.
- PRs 2–9 in order, one at a time, all merged by about Mon 7 Dec 2026; then a staff test on the v2 build, fixes, regression, the release tag and docs/go-live.md. Go-live about mid-December 2026.
- AD-11 comes after go-live.
- Design gates: the 768 menu drawer and the top bar's offline/hover/focus states before PR 3; the bed panel states (and the owner's OK on the occupied tile and category colours) before PR 5; the full check-in before PR 6. A PR reached before its design arrives stops until it does; no layout is invented.

## Next
1. Owner review; clickable test with receptionist and supervisor (5 tasks: check in, extend, check out, close shift, find a receipt).
2. Design the remaining screens in this style: bed panel states (incl. Void stay), full check-in (bed chooser, whole room, ID search), refunds, guests, setup screens, owner desk Today, owner phone Money/Beds/Prices/More, supervisor Beds/Staff/Audit; the 768 menu drawer; offline, hover and focus states of the bar.
3. Build: story/ui-1-docs → ui-2-tokens → ui-3-shell → ui-4-category-colours → ui-5-bed-board → ui-6-check-in → ui-7-cash → ui-8-receipts-voids → ui-9-owner-phone (~16 working days).
