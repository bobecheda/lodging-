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
| 5 | `story/ui-5-bed-board` | Now strip, chips, room cards, v2 tiles, search |
| 6 | `story/ui-6-check-in` | Check-in restyle, summary card, confirm line |
| 7 | `story/ui-7-cash` | Cash (takes over Shifts), close shift |
| 8 | `story/ui-8-receipts-voids` | Receipts, void on receipt and bed panel, Voids removed |
| 9 | `story/ui-9-owner-phone` | Phone Today (with Drawer should hold), Money, Beds, Prices, More |

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
- `gold` `#C9962E` (M-Pesa on money bars). Money split bars use two shades of one hue: M-Pesa `marine`, cash `marineTint` with a marine outline.
- `navText`, `navMuted`, `navActive` and `syncOnline` (the marine sidebar's colours) go with the sidebar in PR 3.
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
in PR 3, when the sidebar's last 700 override goes. Minimum size 12.

| v2 style (`LodgingType`) | Size / weight | Replaces |
|---|---|---|
| `pageTitle` | 24/600 | `pageTitle` 24/800, `heroTitle` 36/800 |
| `sectionTitle` | 18/600 | `sectionTitle` 17/800, `cardTitle` 28/800 |
| `body` | 16/400 | `body` 14/500 |
| `bodyMedium` | 16/500 | `bodyStrong` 14/700 |
| `secondary` | 14/400 | `small` 13/500 |
| `secondaryMedium` | 14/500 | `fieldLabel` 13/700, `cardHeading` 13/800 caps (now sentence case) |
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

**Policy tests (PR 2):** no `FontWeight` above w600 and no size below 12
outside the wordmark and the receipt PDF (`receipt_print_style.dart`).
Caps headings become sentence case, so tests that look for the old caps
text change with them.

## Motion (PR 2 tokens; used from PR 3)

A `LodgingMotion` `ThemeExtension`, read with `LodgingMotion.of(context)`.

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
| < 768 | narrow | Room grid 2 columns, Now strip stacked, search as an icon button |
| 768–1279 | medium | Room grid 4 (landscape) or 3 (portrait); overstay card stacks guest above buttons |
| ≥ 1280 | wide | Room grid 6; Now strip side by side; content capped at 1280 px and centred, top bar full width |

**Never:**
- horizontal page scroll (wide tables scroll inside their card);
- text below 12;
- targets below 44 px (36 px for compact table actions and chips).

**Tests:**
- `screen_layout_test.dart` runs every screen at 1366×768, 1024×768 and 768×1024, using `ValueVariant` and `tester.view.physicalSize` with a pixel ratio of 1.
- The narrow layout is checked for overflow only.

**Spacing, radii and targets** are unchanged (`Space`, `Radii`, `Sizes`). `Sizes.sidebarWidth` is removed in PR 3; new tokens:
- the 64 px top bar;
- the 3 px indicator;
- the 36 px avatar;
- the 4 px category stripe;
- the 1280 px content cap.

## Desk navigation (PR 3)

**The top bar:**
- 64 px, white, with a 1 px `line` bottom border.
- Left: the UB40 wordmark (`LodgingWordmark`, Pirata One, the lodging name from settings) in marine, about 22 px tall, with the role subtitle under it in `meta` (12/500), muted: "Front desk", "Supervisor" or "Owner". A new `WordmarkSize` for the top bar replaces the sidebar's 30.
- Tabs:
  - Each tab has an icon and a label.
  - Default: ink-soft text, muted icon. Active: marine, with a 3 px marine indicator.
  - Count badges in butter.
  - Hover is `surface`; keyboard focus is a 2 px marine outline.
- Right:
  - online dot (green) with "Online" in muted, or a butter "Offline · N waiting";
  - a divider;
  - initials avatar: marine-tint for a receptionist, butter for the supervisor;
  - the user's name, with their shift or role;
  - Lock.

**Collapsing:** tabs collapse into a menu button (the same destinations in a drawer) **whenever they don't fit**, not only below 768. At 768 the user name hides; the avatar and Lock stay.

**Groups:** rarely used pages sit under a tab with a menu (Setup ▾). Future pages (reports, expenses, stock) join a menu group once a role passes about 6 tabs.

**Focused flows** (close shift, sign-in, change password, first run) have no navigation and sit outside the shell. The phone keeps its bottom bar.

**Permissions** still drive every item (`NavItem`, `Routes.permissions`). Tabs, menu rows and the drawer keep the `nav.<route>` keys, and a test helper opens Setup or the menu when needed.

| Role | Desk tabs (home first) | Built in |
|---|---|---|
| Receptionist | Beds, Receipts, Guests, Refunds | PR 3 |
| Supervisor | Beds, Receipts, Guests, Refunds, Cash, Setup ▾ (Rooms & beds, Prices & settings, Staff) | PR 3; Shifts and Voids leave in PR 7 and PR 8 |
| Owner | Today, Cash, Receipts (view and void; no printing), Prices, Staff | Receipts in PR 8 (new permission and tests) |

**Removed as destinations:**
- Shifts, merged into Cash (PR 7). Cash takes its open shifts with Close, its needs-review rows and its voided-after-close marks.
- Voids, now an action on the receipt view and the bed panel (PR 8).
- The phone's Reports placeholder, hidden until AD-9 (PR 3).

Until AD-11, Cash's "Review" opens the existing approve/reject box.

## Components

- **Bed tiles** (PR 5):
  - Ready: white with a 1.5 px marine border.
  - Occupied: marine-tint with a field border (quiet).
  - Overstay: red.
  - To clean: butter with a dashed butter border.
  - Every tile keeps its status label and the guest and paid-until text.
- **Room card** (PR 5): white, with a 4 px category stripe along the top, the room number, and the category label in its text colour.
- **Now strip** (PR 5):
  - Overstay and To clean alert cards, each with a 32 px tinted icon circle (red or butter).
  - "Due out" is dropped.
- **Menus**: white card, 1 px line border, soft shadow (alpha ≤ 0.08), 44 px rows, hovered row marine-tint.
- **Buttons**: Primary (marine), Secondary (white, field border), Danger, per `v2/Button`.
- **Fields and filter chips**: per `v2/Field` and `v2/Filter chip`.
- **Icons**: per `v2/Icon/*`. They are 24 px line icons.

## Screens (each built in its PR)

| Screen | Figma frame | Notes |
|---|---|---|
| Bed board (PR 5) | Desk · Bed board — top nav (receptionist), — 1024 wide, — 768 wide | See below |
| Check-in (PR 6) | Desk · Check-in | See below |
| Close shift (PR 7) | Desk · Close shift — count / — second count | Blind; one large cash field; a mismatch shows no amount |
| Cash (PR 7) | Desk · Cash — top nav (supervisor), …, Setup open | Marine drawer hero (should hold, last check, last collection, Collect cash, Count drawer); To review; History; plus what Shifts did |
| Receipts (PR 8) | Desk · Receipts (receptionist) | See below |
| Owner Today, phone (PR 9) | Phone · Owner Today | See below |

**Bed board:**
- Date and time; the "Guest or receipt" search; New check-in.
- Now strip, filter chips with counts, the room grid.
- Shortcuts: N for new check-in, / for search, Esc to close.
- **Search rule:**
  - The board filters in memory as today: room number exact, part of the occupant's name, the start of their phone.
  - Under the box, up to 5 matching receipts.
  - Digits alone mean a room; a receipt needs the prefix (`R-418`) or 5 or more digits.
  - A name never searches receipts.

**Check-in:**
- Guest, Nights, Payment; a summary card with the total; a confirm line above "Save and print receipt".
- No payment method is chosen at the start; this already holds, and a test keeps it.
- Kept and restyled (principle 14): the bed chooser, "let the whole room", search by ID number, the "Open shift" note.

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
- the bed panel (including Void stay);
- the full check-in;
- refunds, guests, setup screens and the owner's desk Today;
- phone Money, Beds, Prices and More;
- the 768 menu drawer;
- the bar's offline, hover and focus states.

## Dropped (do not build)

- The "Due out by 10:00" card and its rule. Occupied tiles still show the guest and paid-until.
- The receptionist's monthly takings PDF (FD-12): it breaks the blind count.