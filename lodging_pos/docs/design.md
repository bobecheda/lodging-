# Design spec — lodging_pos

Source of truth: the "Lodging POS — Key Screens" design canvas (screenshots in `docs/design/`). This file is the part Claude Code builds from. Target screen: laptop, 1366×768. Admin phone app: 390 wide.

## Colours

The owner's colours are marine blue, bright red and butter yellow. Each one has **one meaning**; never use a colour for anything outside its meaning.

| Token | Hex | Used for |
|---|---|---|
| `marine` | `#0B2E59` | Navigation background, primary buttons, links, **occupied** beds |
| `marine600` | `#12457F` | Hover/pressed on marine |
| `marineTint` | `#EAF1FA` | Selected backgrounds, bed letter boxes, category chips |
| `marineTintStrong` | `#F4F8FD` | Selected card/option background (with 1.5px marine border) |
| `red` | `#D62839` | **Overstay** and urgent alerts only. Never for ordinary or primary buttons |
| `redDark` | `#B01C2C` | Red borders, red text on white |
| `redText` | `#7A0F1B` | Text inside red-tint alerts; destructive outline buttons |
| `redTint` | `#FDECEE` | Alert background (border `#F3B7BE`) |
| `butter` | `#F7E3A1` | **Needs cleaning**, offline indicator, warnings |
| `butterBorder` | `#B8962A` | Dashed border on butter tiles |
| `butterText` | `#3D3100` | All text on butter |
| `ink` | `#0F1B2D` | Body text |
| `inkSoft` | `#3A4556` | Secondary text on white |
| `muted` | `#5B6577` | Labels, captions (passes 4.5:1 on white and on `surface`) |
| `disabled` | `#8A93A3` | Disabled text only |
| `line` | `#DDE3EC` | Card borders, table rules |
| `lineSoft` | `#EEF1F5` | Inner dividers |
| `fieldBorder` | `#C9D5E6` | Input and secondary button borders |
| `surface` | `#F5F7FA` | App background |
| `white` | `#FFFFFF` | Cards, inputs |
| `navText` | `#E4ECF7` / `navMuted` `#C9D8EC` | Text on the marine sidebar |

Light theme only for the MVP. Build colours as a `ThemeExtension` (`LodgingColors`) plus a hand-written `ColorScheme` — no `ColorScheme.fromSeed`.

## Bed status styles

Status is never shown by colour alone: each has a label and a distinct border style.

| Status | Background | Border | Text | Label |
|---|---|---|---|---|
| Ready (available + clean) | white | 1.5px **solid** marine | ink | `READY` (marine) |
| Occupied | marine | 1.5px solid marine | white | `IN USE` + guest name · "until 22:15" |
| Overstay | red | 1.5px solid `redDark` | white | `OVERSTAY` in a white pill with redDark text + "paid to 10:00" |
| Needs cleaning | butter | 1.5px **dashed** `butterBorder` | butterText | `TO CLEAN` + "Needs cleaning · assign" |

Overstays are also listed in a red-tint alert bar at the top of the bed board, with **Renew** (red filled) and **Check out** (white, redText outline) buttons.

## Typography

- **Manrope** for all interface text. Weights: 800 headings and labels-in-caps, 700 labels and buttons, 600 secondary, 500 body.
- **IBM Plex Mono** (500/600) for receipt numbers, M-Pesa codes, money totals and counts.
- Bundle both fonts as assets (no `google_fonts` package — the desk is often offline).
- Sizes: page title 24/800 · section title 17/800 · card heading caps 13/800, letter-spacing 0.06em, muted · body 14 · small 12–13 · large money 22–30 mono.
- Minimum text size 11 (caps labels only), otherwise 12.

## Shape and spacing

- Radius: cards 12–14, inputs and buttons 10, chips 999, bed tiles 8, small badges 4–6.
- Spacing scale: 4, 6, 8, 10, 12, 14, 16, 18, 20, 24, 28, 32.
- Touch/click targets ≥ 44px tall for buttons and inputs (36px allowed for compact table actions and filter chips).
- No shadows, no gradients. Cards are white with a 1px `line` border.

## Layout

- **Desk shell:** left sidebar 232px, marine background. Top: logo (placeholder until designed) + lodging name + "Front desk". Nav items 14/600 `navText`; active item = 14% white background, white 700 text, small butter dot. Bottom: sync status pill, user name + role + "shift since HH:MM", "Lock screen" outline button.
- **Admin-only nav group** under a caps label `SETUP · OWNER ONLY`: Rooms & beds, Prices & settings, Users & staff. Hidden for receptionists.
- **Sync pill:** offline = butter background, butterText, "Offline · N changes waiting". Online = 12% white, "Online · synced N min ago".
- Content area: padding 24×28, background `surface`.
- **Bed board grid:** room cards in `auto-fill, minmax(250px, 1fr)`, gap 12; each card lists its 1–2 bed tiles stacked. 12 rooms fit on 1366×768 without scrolling.
- **Bed panel:** clicking a bed opens a 440px right-hand panel over a dimmed board (scrim `rgba(15,27,45,0.35)`).

## Components

- **Primary button:** marine fill, white 700–800 text, radius 10, height 44–50.
- **Secondary button:** white, 1px `fieldBorder`, marine text.
- **Destructive/urgent:** red fill only for overstay actions; otherwise white with `redText` and `#E8A0A9` border (e.g. Disable user).
- **Inputs:** white, 1px `fieldBorder`, radius 10, height 44–48, label above in 13/700. Focused/selected: 1.5px marine.
- **Money input:** "KES" prefix in mono muted, value in mono 600.
- **Segmented choice (Cash / Paybill):** two equal radio cards; selected = 1.5px marine border + `marineTintStrong` + marine 800 text.
- **Stepper (nights):** − / value (mono 22) / +, buttons 44×44. Label "Nights", helper "Checkout is 10:00".
- **Info note:** `marineTint` background, marine text, info icon. **Warning chip:** butter. **Error:** `redTint` + `redText`.
- **Icons:** simple 2px-stroke line icons (Material Symbols Rounded outline or Lucide). No emoji.

## Screens (artboard names on the canvas)

| Story | Artboard | Key points |
|---|---|---|
| FD-1 | Sign in and screen lock | Split screen: marine brand panel left, form right. Lock version shows a butter "Screen locked after 10 minutes idle" chip and "The open shift is kept." Username field empty. |
| FD-1 | Open or resume shift | Centred card. Opening float in a large mono money input. Resume shows open-since and taken-so-far. Blocked shows "X's shift must be closed first" with Sign out / View bed board only. |
| FD-2 | Bed board | Title + date/time, guest search, "New check-in" primary. Overstay alert bar. Filter chips with counts (All, Ready, Occupied, Overstay, Needs cleaning). Room grid. |
| FD-3/4/5 | Check-in | Step pills (Bed ✓, Guest ✓, Stay & payment, Receipt). Three cards: Bed (shows why Bed B can't be added), Guest (search by phone/ID, returning guest card with masked ID), Stay & payment (nights stepper, "Check-in Thu 19:00" and "Check out by Fri 16 Oct, 10:00", total in mono, Cash/Paybill, M-Pesa code with "each code can be used once", "Save and issue receipt", note "The bed becomes Occupied only after this is saved"). |
| FD-6 | Receipt | 400 wide. Black-and-white friendly (future thermal printer). Logo + lodging name, RECEIPT + number in mono, guest/room/category/from/check-out-by rows, nights × price, total, paid by, M-Pesa code, served by. Footer: "Checkout is at 10:00." Reprints show "COPY". Refund receipts use the same layout titled REFUND, with a negative amount. |
| FD-7/8 | Bed panel — overstay | Red banner with minutes past grace. Guest, paid-so-far rows with receipt numbers. Extend card: nights stepper, "New checkout Sat 17 Oct, 10:00", price labelled "(check-in price)", Cash/Paybill, primary button "Extend and issue receipt". Checkout after grace: "Charge 1 night and check out" (confirmed by owner). |
| FD-8 | Bed panel — early checkout | Occupied bed with prepaid nights left. Shows nights paid, nights used (the current night counts as used), nights to refund and the refund amount — calculated, not editable. Button "Check out and request refund of KES 1,500". Marine-tint note: "The night in progress is not refunded. The owner must approve the refund before it is paid." After approval, a "Refunds to pay" list on the desk shows the guest, amount and phone; "Pay refund" asks Cash drawer or M-Pesa (Paybill account, with code) and prints the REFUND receipt. Butter chip on pending refunds: "Waiting for owner approval". |
| AD-7 | Refund approval (owner) | In the owner's "Needs your attention" list and on an admin screen on the desk: guest, stay, nights used / refunded, amount, requested by and when. Two buttons: "Approve" (marine) and "Reject" (white, redText outline) which asks for a reason. Amount is read-only. |
| FD-9 | Bed panel — needs cleaning | Butter banner with last checkout time, housekeeper dropdown, "Assign cleaning", then "Mark clean · sheets and towels changed". |
| AD-2 | Rooms and beds | Table: room, floor, bed chips ("A · Deluxe"), status (ACTIVE / butter "CLOSED · REPAIRS"), Edit. Side form edits a room: number, floor, bed A/B with category selects. Deactivate disabled with red-tint reason when a bed has a guest. Note: "Changing a category affects new check-ins only." |
| AD-3 | Prices and settings | Category table with KES money inputs; changed row highlighted with "was 700". Info note on price locking. Settings: lodging name, checkout time (default 10:00, "every guest leaves by this time the day after arrival"), grace minutes (0–180), lock after (1–60), receipt prefix (1–4 letters) — each with its range under the field. Prices are "per night". |
| AD-4 | Users and housekeepers | User rows with status (ACTIVE, butter "MUST SET PASSWORD", DISABLED greyed), Reset password, Disable (not on own row). "Add a receptionist" form: full name, username, temporary password. Housekeepers list + add form (name, optional phone). Phone numbers masked in lists. |
| AD-5 | Owner dashboard (phone) | Marine header with sync time. Cards: collected today (cash/paybill split), beds right now (4 tiles in status styles), needs your attention (overstay, cash variance, bed cleaned with no stay), month revenue − expenses = profit, beds sold by category bars. Bottom nav: Today, Reports, Audit, Settings. |

## Copy rules

- Plain English, short sentences. Amounts always `KES 1,200`. Times 24-hour `11:24`; dates `Thu 15 Oct`.
- Say what happens and what to do: "Bed B has a guest right now. Check them out first."
- Mask personal data in lists: phone `0722 ••• 310`, ID `••••3921`.
