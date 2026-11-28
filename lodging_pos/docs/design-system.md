# Design system v2 — lodging_pos

The build spec for the v2 redesign. Decisions and their reasons live in
`docs/ui-redesign-brief.md`; designs in Figma file `CVc42Uc4UyoQr366bP3Bca`,
page "Redesign v2 — Nov 2026" (node 22:447).

**Status (12 Nov 2026): not built.** Until a part ships, `docs/design.md`
describes what is built. Each section below names the PR that builds it;
when that PR merges, this file becomes the truth for that part and the
matching section of design.md is marked superseded.

| PR | Branch | Builds |
|---|---|---|
| 1 | `story/ui-1-docs` | This file, `.ux-profile.md`, pointers |
| 2 | `story/ui-2-tokens` | Colours, type, motion tokens; Manrope 400 |
| 3 | `story/ui-3-shell` | Top bar, breakpoints, focused flows, phone Reports hidden |
| 4 | `story/ui-4-category-colours` | `bed_categories.colour`, swatch menu in Prices |
| 5 | `story/ui-5-bed-board` (+ `ui-5b-bed-board-fixes`) | Now strip, chips, room cards, v2 tiles; the fixes: Now strip as a summary, no board search, top bar labels never cut |
| 6 | `story/ui-6-check-in` | Check-in restyle, summary card, confirm line |
| 7 | `story/ui-7-cash` | Cash (takes over Shifts), close shift |
| 8 | `story/ui-8-receipts-voids` | Receipts, void on receipt (the bed panel's Void stay came with PR 5), Voids removed |
| 9 | `story/ui-9-owner-phone` | Phone Today (with Drawer should hold), Money, Beds, Prices, More |
| — | `story/ui-floating-nav` | The floating top bar (asked 28 Nov) |

PR 5 waits for the owner to confirm the quiet occupied tile and the
category colours. Screens not designed yet take the new tokens and shell
and keep their layout.

## Principles

The 14 principles in the brief are binding. The ones that most often
decide a build question:

- **Problems first**: what needs action, then totals, then detail.
- **Blind where it must be**: a receptionist never sees a cash total or a
  hero card. Every existing "receptionist never sees totals" test stays.
- **Hierarchy from size and space**: three weights (400, 500, 600), none
  above 600.
- **Fewer words**: no explanatory sentences on screen; no visible page
  title that only repeats the active tab (keep a semantic heading).
- **Redesign never removes function** (principle 14): anything a screen
  does today that a design doesn't show is kept and restyled, unless the
  brief lists it under Dropped.

## Colour (PR 2; categories PR 4)

`LodgingColors` keeps its existing tokens; each colour has one meaning.

| Token | Hex | Meaning |
|---|---|---|
| `marine` | `#0B2E59` | Brand and action: primary buttons, active tab and indicator, Ready border, hero card, links, focus ring |
| `marineTint` | `#EAF1FA` | Occupied bed (quiet), selected chip |
| `red` | `#D62839` | Overstay and urgent only |
| `butter` | `#F7E3A1` | Needs cleaning, warnings, count badges, offline |
| `green` (new) | `#1E7B4F` | Good: online, money up, count matched, saved |
| `greenTint` (new) | `#E6F4EC` | Background for good notes |
| `butterTint` (new) | `#FDF6DE` | Soft warning background (Figma `status/butter-tint`) |

**Retired:**
- `gold` `#C9962E` (M-Pesa on money bars). Money split bars use two shades of one hue: M-Pesa `marine`, cash `marineTint` with a marine outline. The phone's 14-day bars: today solid marine, earlier days `marineTint` with a marine outline (until PR 9 restyles Money).
- `navActive` (the sidebar's active row) went with the sidebar in PR 3. `navText` and `navMuted` stay for text on the marine gate panels; `syncOnline` for the phone's header.
- Brand colours stay for the wordmark only: `brandCream`, `brandGoldOnDark`, `brandGoldOnLight`.

**Never used:**
- cream on surfaces;
- red for count badges;
- gradients;
- shadows on cards (menus may have a soft shadow, alpha ≤ 0.08).

**Category colours**: a palette key per category, stored on
`bed_categories.colour`, with a stripe colour (3:1 on white) and a label
text colour (4.5:1 on white). `test/app/theme/contrast_test.dart` checks
every pair.

| Key | Stripe | Label text | Seed category |
|---|---|---|---|
| `gold` | `#B8862B` | `#7A5A12` | VIP |
| `violet` | `#5B4B9A` | `#5B4B9A` | Deluxe |
| `teal` | `#1F7A86` | `#1F7A86` | Comfort |
| `slate` | `#6B7A90` | `#4A5568` | Normal |
| `plum` | `#8A3F7A` | `#8A3F7A` | spare (5th) |
| `bronze` | `#6E5B3E` | `#6E5B3E` | spare (6th) |

Category colour appears only on room cards (4 px stripe and the label) and
category charts. The label always stays: colour is never the only signal.

**Hero card:**
- At most one per screen: marine background, white money, light labels.
- Buttons on it: white primary, outlined secondary.
- Never on a receptionist screen.

**Trends:** `▲ 8% vs usual Wed` in green, `▼` in red-text. Always arrow plus number, never colour alone.

### Category colour data (PR 4)

- **Desk (schema v12):** `bed_categories.colour` text, not null, default `slate`, checked against the palette keys.
  - The migration fills it in by seed id: `SeedIds.vip` gold, `deluxe` violet, `comfort` teal, `normal` slate. Any other category gets slate.
  - It needs a migration test.
- **New category:** `addCategory` gives it the first unused key in palette order, or `slate` once all six are used.
- **Change:** the owner picks from a swatch menu on the category row in Prices (`editPrices`).
  - Written as `category.update` through `writeWithAudit` and the outbox; not cloud-first, since a colour needs no clash check.
- **Cloud:** a migration adds the column with the same check, plus a BEFORE INSERT/UPDATE trigger that keeps the old value or `slate` when the key is missing.
  - Why: `jsonb_populate_record` gives NULL for a missing key, and outbox rows queued before the desk upgraded have none. Same pattern as `20261110000100_cash_drawer_defaults.sql`.
  - pgTAP tests cover it.
- **Pull:** none. The desk is the only writer of the colour.
- **Phone:** adds `colour` to the columns it reads where categories are shown (PR 9).

## Type (PR 2)

Manrope (interface) and IBM Plex Mono (money, receipt numbers, codes).
Weights 400, 500 and 600 only. PR 2 adds `manrope-regular.ttf` (400) with
its source in `assets/fonts/README.md`. The 700 and 800 files are removed
in PR 3 from the app's Manrope family (done); they stay as plain assets for
the receipt PDF's headings. Minimum size 12.

| v2 style (`LodgingType`) | Size / weight | Replaces |
|---|---|---|
| `pageTitle` | 24/600 | `pageTitle` 24/800, `heroTitle` 36/800, `cardTitle` 28/800 (panel and card headings) |
| `sectionTitle` | 18/600 | `sectionTitle` 17/800 |
| `body` | 16/400 | `body` 14/500 |
| `bodyMedium` | 16/500 | `bodyStrong` 14/700 |
| `secondary` | 14/400 | `small` 13/500, `cardHeading` 13/800 caps (card headings, now sentence case, still muted) |
| `secondaryMedium` | 14/500 | `fieldLabel` 13/700, `button` 15/800, `nav` 14/600 |
| `meta` | 12/500 | `capsLabel` 11/800 caps, `smallStrong` 12/700 |
| `moneyHero` | mono 30/600 | `moneyHero` 30/600 |
| `money` | mono 18/600 | `moneyLarge` 22/600, `stepperValue` 22/600 |
| `moneySmall` | mono 14/500 | `mono` 13/500, `monoStrong` 14/600 |

`button` 15/800 and `nav` 14/600 are replaced by `secondaryMedium`
(14/500) on buttons and tabs:
- Buttons (`v2/Button`): 44 px tall, 16 px horizontal padding.
- Top tabs (`v2/Top tab`): 64 px tall, 12 px padding, 18 px icon, 8 px gap
  between icon and label.

**The wordmark is a logo, not UI text.** Pirata One and IM Fell English SC
stay exempt from the three-weight rule and the type scale; their sizes
stay in `wordmark_style.dart`.

**Removed names:** `heroTitle`, `cardTitle`, `bodyStrong`, `small`,
`smallStrong`, `fieldLabel`, `cardHeading`, `capsLabel`, `button`, `nav`,
`mono`, `monoStrong`, `moneyLarge`, `stepperValue`.

**Policy tests (PR 2):** no `FontWeight` above w600 anywhere in `lib/`
except the receipt PDF (`receipt_print_style.dart`); the scale itself has
nothing below 12 and no letter-spacing (`test/app/theme/type_scale_test.dart`).
Caps headings and status labels become sentence case ("Needs your
attention", "Ready", "Waiting for owner approval"). Receipt marks stay in
capitals, as on paper: RECEIPT, REFUND, VOID, COPY.

## Motion (PR 2 tokens; used from PR 3)

`LodgingMotion` (`lib/app/theme/lodging_motion.dart`), read with
`LodgingMotion.of(context)`. Its tokens don't vary by theme, so it is two
constants (`standard`, `instant`) picked by reduced motion, not a
`ThemeExtension`.

| Moment | Animation | Tokens |
|---|---|---|
| Tab change | Indicator slides; content out, new content fades in and rises 8 px | indicator 200 ms ease-out; out 120 ms ease-in; in 180 ms ease-out |
| Open a flow (check-in, drawer count, a decision) | Fade + 16 px slide in the direction of travel; back reverses | 250 ms ease-out / 200 ms ease-in |
| Menu (Setup ▾, 768 menu) | Fade + 4 px drop | open 150 ms ease-out, close 120 ms ease-in |
| Bed panel (dialog) | Slides in from the right; scrim fades | 220 ms ease-out; scrim 150 ms |
| Counts and badges | Cross-fade | 150 ms |

**Rules:**
- Only opacity and transform animate.
- The top bar never moves.
- Input is never blocked.
- No bounce, and money never counts up.
- Esc closes menus and panels and returns focus to the control that opened them.

**Reduced motion:**
- When `MediaQuery.disableAnimationsOf(context)` is true, `LodgingMotion.of` returns zero durations and no offsets: changes are instant, opacity only.
- PR 3 checks on the desk PC that Windows' "Show animations" reaches Flutter. If it doesn't, a desk setting (`settingDefaults`) turns motion off.

**How (PR 3):**
- `DeskShell` stays a `ShellRoute`, so the top bar keeps its state.
- Routes inside it use `pageBuilder: CustomTransitionPage`, with one page type for tabs and one for flows. Each route is marked tab or flow, so the slide goes the right way.
- The indicator is an `AnimatedPositioned` over the measured tab.
- Menus are an `OverlayPortal` with fade and slide transitions.
- The bed panel keeps `showBedPanel`'s dialog, with its own transition.
- Counts use `AnimatedSwitcher`.

## Layout and responsive (PR 3)

Breakpoints come from one pure function, unit-tested at 767, 768, 1279 and 1280:

| Width | Name | Desk |
|---|---|---|
| < 768 | narrow | Room grid 2 columns, Now strip stacked |
| 768–1279 | medium | Room grid 4 (landscape) or 3 (portrait); Now strip side by side from 1024, stacked below |
| ≥ 1280 | wide | Room grid 6; Now strip side by side; content capped at 1280 px and centred, top bar full width |

**Never:**
- horizontal page scroll (wide tables scroll inside their card);
- text below 12;
- targets below 44 px (36 px for compact table actions and chips).

**Tests:**
- `screen_layout_test.dart` runs every screen at 1366×768, 1024×768 and 768×1024 (`deskSizes`), with the real fonts and a pixel ratio of 1. Bed board column counts per width come with PR 5.
- The narrow layout (below 768, not drawn) isn't tested yet.

**Tokens (built in PR 3):** `Sizes.topBar` 64, `tabIndicator` 3, `tabIcon` 18, `avatar` 36, `menuWidth` 240, `menuIcon` 20, `drawerWidth` 304, `drawerRow` 48, `focusRing` 2 and `focusGap` 2, `contentMax` 1280; `Radii.tab` 8; `WordmarkSize.topBar` 22 (the sidebar's 30 is gone, with `Sizes.sidebarWidth`). The category stripe (4 px) comes with PR 5.

## Desk navigation (built in PR 3)

Code: `lib/app/shell/` (`desk_shell.dart` with its parts `top_bar.dart`, `shell_menus.dart`, `nav_drawer.dart`; the pure rules in `shell_layout.dart`).

**The top bar:**
- Floating (story/ui-floating-nav): 12 px clear of the window's top and sides (`Sizes.topBarMargin`), 64 px tall, white, radius 16 (`Radii.floatingBar`), a 1 px `line` border all round and a soft shadow (`LodgingShadows.floatingBar`: ink 6%, 16 blur, 4 down); 8 px inside its border (`Sizes.topBarInset`), the wordmark 8 px further in. The page starts under it. It never moves; pages change under it.
- Tabs 8 px apart (`tabSpacing`); 16 px either side of the divider before the user. With these, a role's tabs need no more room than before the bar floated, so they fold into the drawer at the same widths as before.
- Left: the UB40 wordmark (`LodgingWordmark`, Pirata One, the lodging name from settings, name only) in marine, about 22 px tall, with the role subtitle under it in `meta`, muted: "Front desk", "Supervisor" or "Owner". The wordmark is a logo, exempt from the type rules.
- Tabs (Figma `v2/Top tab`): 44 px pills, radius 8, centred in the bar; 12 px padding, an 18 px Lucide icon, 8 px gaps, the label in `secondaryMedium`, then a butter count badge and, for a menu tab, a 16 px chevron.
  - Default: ink-soft text, muted icon. Active: marine text and icon, and the 3 px marine indicator that slides between tabs (`tabIndicator`, 200 ms).
  - Hover (mouse only): the app background, ink text.
- Right, in order:
  - the backup pill (butter, only when the main backup failed or is overdue; a supervisor's tap opens Prices & settings);
  - the sync status (below);
  - a divider;
  - the user button: initials avatar (marine-tint for a receptionist, butter for the supervisor, marine with white initials for the owner), the name and "Shift since 07:02" or the role;
  - Lock (44 px, the app background, a marine lock).

**Sync status** (`syncBarText` in `core/sync/sync_status_text.dart`), all opening the Cloud sync panel:

| State | Look |
|---|---|
| Online | Green dot, "Online" |
| Syncing (online, changes still waiting) | Muted dot, "Syncing · 3", counting down |
| Uploading | Muted dot, "Uploading 3,400 of 12,880" |
| Offline | Butter pill, "Offline · 3 waiting" |
| Sync not set up, Not connected, Owner sign-in needed, N records not in the cloud, PC clock 12 min slow | Butter pill |
| Sync problem | Red-tint pill, red text: the one urgent sync state |

The full sentence ("Online · synced 2 min ago") stays in the drawer and the Cloud sync panel.

**The user menu:** clicking the avatar and name opens a menu in the Setup ▾ style with Close shift (only with this user's own shift open) and Change my password (the owner). A supervisor without a shift of their own has nothing to open.

**Menus** (Setup ▾, More ▾, the user menu; `showShellMenu`): a 240 px white card, 1 px line border, soft shadow (alpha 0.08), 44 px rows with 20 px icons, the hovered row marine-tint, the current page's row marine-tint with marine text. They drop 4 px as they fade in (150 ms) and fade out (120 ms). Escape or a tap outside closes them; focus goes back to the tab.

**Collapsing:** no tab label and no role line under the wordmark is ever cut or ellipsized. Widths are measured with the real text scale (`MediaQuery.textScaler`, so Windows text scaling counts) and rounded up to whole pixels; every text style sets letter spacing 0, so what is drawn is what was measured (a null spacing took Material's 0.1–0.5 px a letter and cut labels, 25 Nov). When space runs short the user's name hides first; then the tabs collapse into a menu button left of the wordmark (`barLayout`), the name staying hidden; the avatar, the status and Lock stay.

**The drawer** (`showNavDrawer`): 304 px from the left, full height, white, a 1 px line on its right and a soft shadow, over the 35% ink scrim.
- Head: the wordmark and role, and Close (X, 44 px).
- Rows: 48 px, a 20 px icon and `bodyMedium`, radius 8; the active row marine-tint with marine text and a 3 px marine bar on its left; badges at the right.
- Groups (Setup, the temporary More) are plain sections: a `meta` label, then their pages.
- Foot (above a 1 px line): the full sync sentence, the avatar, name and shift or role, the user menu's rows, then a full-width "Lock screen".
- It slides in (220 ms) and out (200 ms) as the scrim fades (150 ms). It closes on X, the scrim, Escape or choosing a page; focus stays inside while it's open and returns to the menu button.

**Groups:** rarely used pages sit under a tab with a menu (`NavGroup`). Future pages (reports, expenses, stock) join a group once a role passes about 6 tabs. **More ▾** (Shifts, Voids) is temporary, for the supervisor and the owner, and goes in PR 8.

**Focused flows** (close shift, sign-in, change password, first run) have no navigation and sit outside the shell (`FocusedFlow`). Close shift has its own way back: "Back to beds", or "Back to Shifts" when closing someone else's shift.

**Keyboard focus:** a 2 px marine ring, 2 px outside the control (`FocusRing`), shown only for the keyboard. In PR 3 it is on the tabs, Lock, the user and menu buttons, the menus and drawer rows, the status pills, `AppButton` and `SegmentedChoice`; each screen's own controls get it when the screen is restyled.

**Motion between pages** (`deskPage` in `lib/app/page_transitions.dart`): a tab's page fades out, then the new one fades in rising 8 px; a flow (check-in, a drawer count, a refund decision) slides 16 px in from the right and back. Side panels (`showSidePanel`) slide in from the right over the scrim.

**Reduce motion:** Windows' "Show animations" doesn't reach Flutter, so the supervisor has a "Reduce motion" switch in Prices & settings (`reduce_motion`, stored on this desk PC; settings are never pulled). On, the app runs as if the system asked for reduced motion: everything switches at once.

**Icons:** Lucide (`lucide_icons_flutter` 4.0.1, MIT; the font is ISC), bundled and offline.

**Permissions** still drive every item (`NavItem.permissions`, `Routes.permissions`). Tabs, menu rows and drawer rows keep the `nav.<route>` keys; tests use `tapNav` and `tapUserMenu`.

| Role | Desk tabs (home first) | Built in |
|---|---|---|
| Receptionist | Beds, Receipts, Guests, Refunds | PR 3 |
| Supervisor | Beds, Receipts, Guests, Refunds, Cash, More ▾ (Shifts, Voids), Setup ▾ (Rooms & beds, Prices & settings, Staff) | PR 3; More ▾ goes in PR 8 |
| Owner | Today, Cash, Prices, Staff, More ▾ (Shifts, Voids); Receipts (view and void; no printing) comes in PR 8 | PR 3; Receipts in PR 8 |

**Removed as destinations:**
- Shifts, merged into Cash (PR 7). Cash takes its open shifts with Close, its needs-review rows and its voided-after-close marks.
- Voids, now actions: Void stay in the bed panel (PR 5, the supervisor) and Void on the receipt view (PR 8). The Voids screen goes in PR 8.
- The phone's Reports placeholder, hidden until AD-9 (PR 3).

Until AD-11, Cash's "Review" opens the existing approve/reject box.

## Components

- **Bed tiles** (PR 5):
  - Ready: white with a 1.5 px marine border.
  - Occupied: marine-tint with a field border (quiet).
  - Overstay: red.
  - To clean: butter with a dashed butter border.
  - As built: one line, 44 px tall (a hit target): "Ready"; the guest's surname and the paid-until weekday ("Otieno · Thu"), or the time when it's today ("Kamau · 11:30"); "Kamau · 2 h" past checkout; "To clean", or "To clean · Mary" once someone has it. Screen readers hear the full name and paid-until.
- **Room card** (PR 5): white, with a 4 px category stripe along the top, the room number, and the category label in its text colour. A room whose beds are in two categories gets a stripe in two halves and both labels.
- **Now strip** (PR 5, fixed 25 Nov; brief "Bed board — fixes after the first build"): a summary, never a list.
  - Overstay and To clean cards, each with a 28 px tinted icon circle (red or butter), the title and the count; a card shows only when its count is above 0, and with both at 0 the strip is gone.
  - Overstay: up to 3 rows, oldest first, 44 px and tappable (the bed panel, where Extend and Check out are): "A9 A · Bobe" left, how long right in red text ("2 h" under a day, then "32 days"). No buttons on the rows. More than 3: the title line reads "Overstay 11 · Show all", and "Show all" (a 44 px target) turns on the Overstay chip; no "+ N more" row.
  - To clean: 36 px butter chips that hug their text, 8 px apart, wrapping, at most 2 lines; when they don't fit, the last is "+ 6 more", which turns on the To clean chip. A chip opens that bed's cleaning panel.
  - Side by side, the same height, in a window 1024 wide or more; stacked below. The room grid's first row is always on the first screen (layout tests with 26 overstays and 26 beds to clean, at text scale 1, 1.25 and 1.5).
  - "Due out" is dropped.
- **Menus**: white card, 1 px line border, soft shadow (alpha ≤ 0.08), 44 px rows, hovered row marine-tint.
- **Buttons**: Primary (marine), Secondary (white, field border), Danger, per `v2/Button`.
- **Fields and filter chips**: per `v2/Field` and `v2/Filter chip`.
- **Icons**: per `v2/Icon/*`. They are 24 px line icons.

## Screens (each built in its PR)

| Screen | Figma frame | Notes |
|---|---|---|
| Bed board (PR 5) | Desk · Bed board — top nav (receptionist), — 1024 wide, — 768 wide | See below |
| Check-in (PR 6) | Desk · Check-in (full), Check-in · variants | See below |
| Close shift (PR 7) | Desk · Close shift — count / — second count | Blind; one large cash field; a mismatch shows no amount |
| Cash (PR 7) | Desk · Cash — top nav (supervisor), …, Setup open | Marine drawer hero (should hold, last check, last collection, Collect cash, Count drawer); To review; History; plus what Shifts did |
| Receipts (PR 8) | Desk · Receipts (receptionist) | See below |
| Owner Today, phone (PR 9) | Phone · Owner Today | See below |

**Bed board:**
- Date and time; New check-in. (The "Guest or receipt" search, its receipt results and "/" were dropped on 25 Nov: guests on Guests, receipts on Receipts.)
- Now strip, filter chips with counts (All, Ready, Occupied, Overstay, To clean) and a last chip "Category ▾" whose menu narrows the board to one category, the room grid (6 columns at 1366, 4 at 1024, 3 at 768).
- The Now strip as described under Components.
- A Ready tile goes straight to check-in (no Ready panel); the check-in's bed shows "Cleaned 08:15 · Mary" when it was cleaned through the desk.
- Shortcuts: N for new check-in (not while a field has the cursor), Esc to close.

**Bed panel (PR 5, Figma "Bed panel · states"):**
- The 440 px side panel with a head (bed "106 A", category and price in the category's colour, status badge, Close), a scrolling body and the actions at the foot.
- Occupied: the guest (masked phone), checked in, paid until, nights, receipts (number, method, amount); Extend stay and Check out; "Void this stay" for the supervisor (`voidRecords`).
- Check out: early (nights paid and used, the refund card, "Check out and request KES …") or on time; Back.
- Extend: nights with the new checkout, the check-in price, Cash or M-Pesa, a confirm line, "Extend and print receipt". During an overstay the panel opens here with the red banner ("2 h past 10:00 · paid to Wed 11 Nov"), and the second button charges the nights started and checks out with the same payment.
- To clean (the cleaning panel): the butter banner with the last checkout, the housekeeper, Assign cleaning and Mark clean (already cleaned: both at once); once assigned, Mark clean and Reassign.
- Void stay: the Story A rules as built (`void_rules.dart`, `VoidsRepository.voidStay`): the receipts it voids, the other bed's stay when one payment paid both, the bed after ("To clean"), a reason; the rule that stops it (e.g. you checked the guest in yourself) shows instead of the button.

**Check-in (PR 6, Figma "Desk · Check-in (full)" and "Check-in · variants"; as built):**
- A form card (Bed, Guest, Nights, Payment) and a 360 px summary card. The frame's state fits 1366×768 without scrolling; longer states scroll inside the form card while the summary stays put. Side by side from about 860 px of content; narrower (768), the summary sits under the form.
- Bed: the chosen bed as a row with a 1.5 px marine border, a letter box, "104 A" and "Comfort · KES 600 a night · cleaned 08:15 · Mary" in the category's colour, and Change. With no bed yet: "Choose a bed" and Choose. Change opens the bed chooser (`showShellCard`, the menu card style): "Ready beds · 6", Ready and clean beds only (BR-5) by category, dearest first, each an 80×44 mono chip, the chosen one solid marine; "Only Ready and clean beds are listed."
- Whole room: a switch under the bed row for 2-bed rooms, off at the start, disabled with the reason ("· 104 B has a guest"). On: "107 A + 107 B · KES 500 a night each", or "KES 700 + KES 600 a night" at two prices; the summary says "2 beds × 2 nights × KES 500 · one receipt", or one line per bed ending "· one receipt". Two stays, one payment (BR-4).
- Guest: one search box (phone or ID number, as you type). Matches list with masked phones and IDs, then "New guest with this phone" (families share phones). The chosen guest: a marine-tint row with a check, the name, the **full** phone (to confirm with the guest), the masked ID, "3 stays", and "Not this guest". No match: "No guest with this phone or ID — new guest", then Phone and Full name side by side (Phone filled when the search was a phone, ID number when it was an ID), "ID (optional)" National ID / Passport / Alien ID (none chosen until tapped) and ID number. The shared-phone notice as before. A registered ID: "This National ID is already registered to Grace Wanjiru · 0722 ••• 310." with "Use this guest". The new guest is registered by the check-in's own save.
- Nights: the stepper (typable, 1–30) and "Out Fri 13 Nov, 10:00".
- Payment: Cash / M-Pesa, 48 px, none chosen at the start; the chosen one solid marine with white text. "M-Pesa code" only for M-Pesa.
- Summary: Total (Money hero), the price lines, the confirm line (grey and naming the first thing missing: "Choose a bed", "Find or add the guest", "Add the new guest’s name and phone", "Choose Cash or M-Pesa"; then "M-Pesa · KES 1,200 · out Fri 10:00"), any refusal, "Save and print receipt" (off until all is chosen), Cancel.
- No open shift of your own: a centred card instead of the form: butter clock circle, "Open your shift first", "Check-ins and payments need an open shift.", Open shift (with `openShift`; returns to the same bed) and Back to beds.
- After saving (not redesigned): "Checked in" with the receipt and Print, Back to bed board, Check in another guest. No print dialog opens by itself.
- Gone: the step pills, the "← Bed board" link (Cancel), the check-in / check-out-by box, "The bed becomes Occupied only after this is saved.", "Still to choose: …" (now the grey confirm line), the M-Pesa helper text.

**Receipts:**
- Search by receipt number or phone.
- A table: receipt, guest, bed, method, amount, time, Print copy.
- No totals.
- For voiders: Void on the receipt view. The owner sees view and void, with no printing.

**Owner Today (phone):**
- Order: Needs you, Collected today (marine hero), Beds now, Drawer should hold, This month.
- Drawer should hold is new: computed on the phone with the desk's drawer rules, with a test that it matches the desk.
- Then Money, Beds, Prices and More, restyled.

Not designed yet:
- refunds, guests, setup screens and the owner's desk Today;
- phone Money, Beds, Prices and More;
- the 768 menu drawer;
- the bar's offline, hover and focus states.

## Dropped (do not build)

- The "Due out by 10:00" card and its rule. Occupied tiles still show the guest and paid-until.
- The receptionist's monthly takings PDF (FD-12): it breaks the blind count.