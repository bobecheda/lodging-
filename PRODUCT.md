# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

One Flutter codebase, two apps: the **desk** (Windows, `lodging_pos/lib/main.dart`) and the **owner's app** (Android and web, `lodging_pos/lib/main_owner.dart`). Each surface should follow its platform's expectations where they help (desktop top bar and keyboard on the desk; phone navigation and touch on the owner's app) while keeping one brand.

## Users

Three roles sign in. Housekeepers and guests appear in the data but never use the app.

- **Receptionist** (one today, two in shifts later). Works the front desk PC, often offline. Checks guests in and out, takes cash or M-Pesa, prints receipts, sees which beds are free and clean. Moderate computer skills: wording must be plain and every next step obvious.
- **Supervisor.** Runs the lodging day to day on the same desk PC. Does everything a receptionist does, plus setup (rooms, beds, prices, settings, staff), voids, drawer checks and collections, shift oversight and cash reviews.
- **Owner.** Often away from the lodging. Mostly reads the phone app in short glances, on the go and on mobile data: takings, beds, what needs attention. Approves refunds and price changes, decides cash reviews, manages supervisors. Also signs in on the desk (today: Today, Shifts, Cash, Voids, Prices, Staff; after the v2 redesign: Today, Cash, Receipts for viewing and voiding, Prices, Staff), but never takes money there and never has a shift.

## Product Purpose

A front desk and owner system for a lodging that charges **per bed, per night, checkout 10:00**. Every bed that is let is tied to a guest, a payment, a receptionist and a shift, so the owner can see occupancy and takings from anywhere and catch missing money.

Success, over the first three months after go-live (planned for 20 Nov 2026; the owner is confirming whether go-live or the v2 redesign comes first), is measured in `lodging_pos/docs/prd.md`:
- no unexplained lets;
- shift cash variance under 1% of takings;
- every overstay charged;
- check-in under 1 minute for a returning guest and under 2 for a new one;
- zero desk downtime caused by the internet;
- the owner opens the dashboard 5 or more days a week.

## Positioning

A money-control system disguised as a simple front desk. Prices, refunds and statuses are calculated by the system, never typed. Records are append-only and corrected only by visible voids. The cash drawer is one running ledger with blind counts, co-signed checks and owner reviews. The desk keeps working with no internet and syncs to the owner's phone when it can.

## Operating Context

- **The desk:** a laptop-sized screen; every screen must fit **1366×768**. The internet is unreliable, so every desk screen works offline. It locks itself after an idle timeout, and the receptionist's shift stays open across the lock.
- **The owner's app:** online only, reads the cloud, stores nothing on the phone. Layouts must fit 360×640 and 412×915.
- **Money:** cash in one drawer, plus M-Pesa through a paybill with the code typed in. Receipts are shown on screen, printed, or saved as an 80 mm PDF.
- **Daily rituals:**
  - a shift is opened and closed with a blind count;
  - surprise drawer checks happen about twice a week, and the owner collects cash weekly;
  - the owner decides refunds and price requests;
  - a paper desk sheet (`lodging_pos/docs/desk-sheet.md`) covers corrections.
- **Navigation:** today the desk uses a fixed 232 px sidebar with role-filtered items; the phone has a five-tab bottom bar (Today, Money, Beds, Prices, More). The v2 redesign (`lodging_pos/docs/ui-redesign-brief.md`, `lodging_pos/docs/design-system.md`) replaces the sidebar with a light top bar that collapses into a menu when the tabs don't fit, merges Shifts into Cash, moves voiding onto the receipt and the bed panel, and hides the phone's Reports placeholder. Every desk screen must then work from 768 to 1920 px wide.
- **Desk input:** mouse-and-keyboard only is **not confirmed**. Don't assume the desk has no touchscreen.

## Capabilities and Constraints

- **Built:**
  - Desk: bed board, check-in with payment, extend, checkout, refund requests and payouts, receipts and REFUND receipts, guests, housekeeping assignment, shifts with a blind close, drawer ledger, checks and collections, cash reviews, voids, setup (rooms and beds, prices and settings, users and staff), daily local backup, cloud sync, owner's Today.
  - Phone: Today, Money, Beds, Prices, and under More: Shifts, Audit trail, Staff, Change password.
- **Not built yet (after go-live):** expenses, monthly reports (Reports is a placeholder row on the phone), inventory, reservations, automatic M-Pesa confirmation, thermal printer.
- **Permissions:** every screen and action is gated by one permission map, never by comparing roles. Hiding a screen is never the only lock.
- **A receptionist never sees a total:** no shift figures, drawer balances or review outcomes on any receptionist screen, receipt list or PDF.
- **Privacy:**
  - Lists show phones and ID numbers masked (`0722 ••• 310`, `••••3921`).
  - The owner's app never downloads ID numbers, full phones or payout phones.
- **Terms:**
  - Bed statuses: Ready, In use (occupied), Overstay, To clean.
  - Payment methods are `cash` and `paybill`, labelled "M-Pesa".
  - Amounts: `KES 1,200`, whole shillings.
  - Times are 24-hour (`07:02`); dates look like `Thu 15 Oct`; everything is in Nairobi time.
- **Language:** English only. No second language is planned.
- **Theme:** light only for the MVP.

## Brand Commitments

- **The lodging:** UB40. Its name comes from settings and is shown by the wordmark (Pirata One with a gold offset shadow, "Lodging" in IM Fell English SC). The app icon is a cream "UB" on a marine rounded square (`lodging_pos/assets/brand/`).
- **The owner's three colours, each with one meaning:**
  - marine: navigation, primary actions, occupied beds;
  - red: overstay and urgent alerts only;
  - butter: needs cleaning, offline, warnings.
- **v2 colour system (agreed 12 Nov 2026, not built):** marine becomes brand and action only, with occupied beds in quiet marine-tint (owner to confirm); green means good (online, money up, count matched); each room category has a colour key (VIP gold, Deluxe violet, Comfort teal, Normal slate, two spares); gold means VIP only, and the old M-Pesa gold is retired. Details: `lodging_pos/docs/design-system.md`.
- **Status is never shown by colour alone.**
- **Voice:** plain English and short sentences. Say what happens and what to do next ("Bed B has a guest right now. Check them out first."). No emoji.
- **The current visual system** is specified in `lodging_pos/docs/design.md` and implemented in `lodging_pos/lib/app/theme/`. The v2 system that replaces it, PR by PR, is in `lodging_pos/docs/design-system.md`; UX review context in `lodging_pos/.ux-profile.md`. Neither is recorded as DESIGN.md.
- **A redesign never removes a function** unless the brief lists it under Dropped.

## Evidence on Hand

- **Requirements and rules:** `lodging_pos/docs/prd.md` (stories and acceptance criteria) and `lodging_pos/docs/schema.md`; business rules are in the `lodging-rules` skill.
- **Design canvas:** screenshots in `lodging_pos/docs/design/` (bed board, bed panel, check-in, receipt, sign-in and lock, open shift, setup screens, colours and type, owner dashboard).
- **Owner-app Figma:** https://www.figma.com/design/CVc42Uc4UyoQr366bP3Bca (screens 01 Today to 07 More).
- **Brand assets** (`lodging_pos/assets/brand/`) and bundled fonts (`lodging_pos/assets/fonts/`, with sources).
- **Redesign v2 Figma:** the same file, page "Redesign v2 — Nov 2026" (node 22:447); decisions in `lodging_pos/docs/ui-redesign-brief.md`.
- **Absent:** no real usage data, timings or variance figures yet, since the desk hasn't gone live. No testimonials or user research. Don't invent any.

## Product Principles

1. **Split by role.** Receptionist screens are optimised for speed: everyday work never gains a step. Supervisor and owner screens are optimised for control: an extra check is acceptable where money is at stake.
2. **The system calculates; people confirm.** No screen lets anyone type a price, refund or status the rules already decide.
3. **Nothing disappears.** Corrections are visible voids, decisions name who made them, and closed records never change.
4. **The desk never waits for the internet.** Offline is the normal state, shown calmly and never as an error.
5. **Show each role only what it needs.** A receptionist sees no totals; the owner's phone sees no personal data it doesn't need.

## Accessibility & Inclusion

- Text and captions pass 4.5:1 contrast on white and on the app background (`muted` `#5B6577` is the floor).
- Status always has a label and a distinct border style as well as colour.
- Click and touch targets are at least 44 px; compact table actions and filter chips may be 36 px.
- Minimum text size is 12, or 11 for caps labels only (v2: 12 everywhere, no caps labels).
- v2 motion honours reduced motion (Windows "Show animations" off): changes are instant.
- Plain wording for users with moderate computer skills.
