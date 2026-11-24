import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/gate.dart';
import '../../../app/theme/theme.dart';
import '../../../app/widgets/bed_panel_frame.dart';
import '../../../app/widgets/buttons.dart';
import '../../../app/widgets/labeled_field.dart';
import '../../../app/widgets/night_stepper.dart';
import '../../../app/widgets/notes.dart';
import '../../../app/widgets/segmented_choice.dart';
import '../../../app/widgets/side_panel.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/category_colour_keys.dart';
import '../../../core/clock/nairobi.dart';
import '../../../core/contacts/phone.dart';
import '../../../core/money/kes.dart';
import '../../bed_board/domain/bed_board.dart';
import '../../bed_board/presentation/bed_board_providers.dart';
import '../../payments/domain/payment_rules.dart';
import '../../receipts/presentation/receipt_view.dart';
import '../../shifts/domain/shift_rules.dart';
import '../../shifts/presentation/shift_providers.dart';
import '../../voids/domain/void_rules.dart';
import '../../voids/presentation/voids_providers.dart';
import '../data/check_out_repository.dart';
import '../data/extend_repository.dart';
import '../domain/check_in.dart';
import '../domain/check_out.dart';
import '../domain/extend.dart';
import 'check_in_providers.dart';
import 'extend_card.dart';

/// Opens the bed panel for [stayId]: 440 px from the right over the dimmed
/// board, sliding in (docs/ui-redesign-brief.md, "Motion"). Escape or a tap
/// on the scrim closes it.
Future<void> showBedPanel(BuildContext context, String stayId) => showSidePanel(
  context,
  barrierLabel: 'Close the bed panel',
  child: BedPanel(key: ValueKey('panel.$stayId'), stayId: stayId),
);

/// What the panel is showing.
enum _Mode { overview, extend, checkOut, voidStay }

/// The bed panel (v2 PR 5, Figma "Bed panel · states"): a head (bed,
/// category and price, status, close), a body and the actions at its foot.
///
/// - **Occupied:** the guest, check-in, paid until, nights and receipts;
///   Extend stay, Check out, and "Void this stay" for the supervisor.
/// - **Extend (FD-7):** nights, the new checkout, the check-in price, Cash
///   or M-Pesa; during an overstay this is where the panel opens, and the
///   second button charges the nights started and checks out (FD-8).
/// - **Check out (FD-8):** early (the refund to request) or on time.
/// - **Void stay (AD-7):** the Story A rules unchanged (`void_rules.dart`).
class BedPanel extends ConsumerStatefulWidget {
  const BedPanel({super.key, required this.stayId});

  final String stayId;

  @override
  ConsumerState<BedPanel> createState() => _BedPanelState();
}

class _BedPanelState extends ConsumerState<BedPanel> {
  _Mode? _mode;

  // Extend and the late checkout share the nights and the payment.
  int? _nights;
  String? _typed;
  PaymentMethod? _method;
  final _code = TextEditingController();
  String? _codeError;

  final _reason = TextEditingController();
  String? _problem;
  var _busy = false;
  CheckOutResult? _result;
  ExtendResult? _extended;
  VoidPlan? _voided;

  static const _noShift = 'This records money. Open a shift first.';

  @override
  void dispose() {
    _code.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).pop();

  void _go(_Mode mode) => setState(() {
    _mode = mode;
    _problem = null;
    _codeError = null;
  });

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _problem = null;
      _codeError = null;
    });
    try {
      await action();
    } on InvalidLatePayment catch (e) {
      if (mounted) setState(() => _codeError = e.message);
    } on CheckOutRefused catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } on ExtendRefused catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } on VoidRuleViolation catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } on NoOpenShift {
      if (mounted) setState(() => _problem = _noShift);
    } on NotPermitted {
      if (mounted) setState(() => _problem = 'You can’t do that here.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkOut(
    UserAccount user,
    StayDetail detail,
    CheckoutTerms terms,
  ) async {
    if (terms is LateCheckout && _method == null) {
      setState(() => _codeError = 'Choose Cash or M-Pesa.');
      return;
    }
    await _run(() async {
      final result = await ref
          .read(checkOutRepositoryProvider)
          .checkOut(
            user,
            CheckOutRequest(
              stayId: detail.id,
              shown: terms,
              method: terms is LateCheckout ? _method : null,
              mpesaCode:
                  terms is LateCheckout && _method == PaymentMethod.paybill
                  ? _code.text
                  : null,
            ),
          );
      if (mounted) setState(() => _result = result);
    });
  }

  Future<void> _extend(UserAccount user, StayDetail detail, int nights) =>
      _run(() async {
        final result = await ref
            .read(extendRepositoryProvider)
            .extend(
              user,
              ExtendRequest(
                stayId: detail.id,
                nights: nights,
                shownPaidUntil: detail.stay.paidUntil,
                method: _method,
                mpesaCode: _method == PaymentMethod.paybill ? _code.text : null,
              ),
            );
        if (mounted) setState(() => _extended = result);
      });

  Future<void> _void(UserAccount user, StayDetail detail, VoidPlan plan) =>
      _run(() async {
        await ref
            .read(voidsRepositoryProvider)
            .voidStay(user, detail.id, _reason.text);
        if (mounted) setState(() => _voided = plan);
      });

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider);
    final detail = ref.watch(stayDetailProvider(widget.stayId)).value;
    final grace = ref.watch(boardGraceMinutesProvider).value;
    final now = ref.watch(boardNowProvider).value;
    final shift = ref.watch(currentShiftProvider).value;

    if (user == null || detail == null || grace == null || now == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final past = minutesPastGrace(detail.stay.paidUntil, now, grace);
    final overstay = detail.isActive && past > 0;
    final mode = _mode ?? (overstay ? _Mode.extend : _Mode.overview);
    final ownShift = shift != null && shift.userId == user.id;
    final first = detail.stay.charges.first;
    final head = BedPanelHead(
      roomNumber: detail.roomNumber,
      bedLabel: detail.bedLabel,
      subtitle:
          '${first.categoryName} · ${formatKes(first.pricePerNight)} a night',
      colourKey: _categoryColour(detail),
      status: !detail.isActive
          ? BedPanelStatus.checkedOut
          : overstay
          ? BedPanelStatus.overstay
          : BedPanelStatus.occupied,
      onClose: _close,
    );

    final (List<Widget> body, List<Widget> actions) = switch (null) {
      _ when _result != null => (
        [_Result(result: _result!, onDone: _close)],
        const <Widget>[],
      ),
      _ when _extended != null => (
        [ExtendedView(result: _extended!, onDone: _close)],
        const <Widget>[],
      ),
      _ when _voided != null => (
        [_Voided(plan: _voided!, onDone: _close)],
        const <Widget>[],
      ),
      _ when !detail.isActive => (
        [
          Note.info(
            'This guest checked out '
            '${formatDayDateComma(detail.checkedOutAt!)}.',
          ),
        ],
        const <Widget>[],
      ),
      _ => switch (mode) {
        _Mode.overview => _overview(user, detail),
        _Mode.extend => _extendState(
          user,
          detail,
          now: now,
          grace: grace,
          overstay: overstay,
          ownShift: ownShift,
        ),
        _Mode.checkOut => _checkOutState(
          user,
          detail,
          checkoutTerms(detail.stay, now, grace),
          ownShift: ownShift,
        ),
        _Mode.voidStay => _voidState(user, detail),
      },
    };

    return BedPanelFrame(head: head, body: body, actions: actions);
  }

  String _categoryColour(StayDetail detail) {
    final rooms = ref.watch(boardRoomsProvider).value ?? const <BoardRoom>[];
    for (final r in rooms) {
      for (final b in r.beds) {
        if (b.id == detail.bedId) return b.categoryColour;
      }
    }
    return defaultCategoryColour;
  }

  /// No shift: the note and Open shift, coming back to this panel.
  List<Widget> _shiftNote(StayDetail detail) => [
    const Note.warning(_noShift, key: ValueKey('panel.noShift')),
    const SizedBox(height: Space.x8),
    AppButton.secondary(
      key: const ValueKey('panel.openShift'),
      label: 'Open shift',
      onPressed: () {
        final back = Uri(
          path: Routes.home,
          queryParameters: {'stay': detail.id},
        ).toString();
        _close();
        context.go(Routes.shiftThen(back));
      },
    ),
  ];

  List<Widget> _problemNote() => [
    if (_problem != null) ...[
      const SizedBox(height: Space.x16),
      Note.error(_problem!, key: const ValueKey('panel.problem')),
    ],
  ];

  // ── Occupied ─────────────────────────────────────────────────────────

  (List<Widget>, List<Widget>) _overview(UserAccount user, StayDetail detail) {
    final first = detail.stay.charges.first;
    final nights = detail.stay.charges.fold(0, (n, c) => n + c.nights);
    return (
      [
        _GuestRow(
          name: detail.guest.fullName,
          line: maskPhone(detail.guest.phone),
        ),
        const SizedBox(height: Space.x16),
        _InfoRow('Checked in', formatDayDateComma(first.periodStart)),
        _InfoRow(
          'Paid until',
          formatDayDateComma(detail.stay.paidUntil),
          key: const ValueKey('panel.paidUntil'),
        ),
        _InfoRow('Nights', '$nights × ${formatKes(first.pricePerNight)}'),
        const SizedBox(height: Space.x12),
        _Receipts(detail.charges),
      ],
      [
        Row(
          children: [
            if (can(user, Permission.extendStay)) ...[
              Expanded(
                child: AppButton.primary(
                  key: const ValueKey('panel.extend'),
                  label: 'Extend stay',
                  onPressed: () => _go(_Mode.extend),
                ),
              ),
              const SizedBox(width: Space.x10),
            ],
            Expanded(
              child: AppButton.secondary(
                key: const ValueKey('panel.toCheckOut'),
                label: 'Check out',
                onPressed: () => _go(_Mode.checkOut),
              ),
            ),
          ],
        ),
        if (can(user, Permission.voidRecords)) ...[
          const SizedBox(height: Space.x8),
          Center(
            child: TextButton(
              key: const ValueKey('panel.void'),
              onPressed: () => _go(_Mode.voidStay),
              style: TextButton.styleFrom(
                foregroundColor: LodgingColors.of(context).redText,
                minimumSize: const Size(0, Sizes.target),
              ),
              child: const Text('Void this stay'),
            ),
          ),
        ],
      ],
    );
  }

  // ── Extend, and the late checkout during an overstay ──────────────────

  (List<Widget>, List<Widget>) _extendState(
    UserAccount user,
    StayDetail detail, {
    required DateTime now,
    required int grace,
    required bool overstay,
    required bool ownShift,
  }) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final stay = detail.stay;
    final min = extendMinNights(stay, now, grace);
    final reason = minNightsReason(stay, now, grace);
    final stepped = _nights == null || _nights! < min ? min : _nights!;
    final chosen = _typed == null ? stepped : parseNights(_typed!);
    final nightsProblem = extendNightsError(chosen, minNights: min);
    final quote = nightsProblem == null ? quoteExtend(stay, chosen!) : null;
    final terms = checkoutTerms(stay, now, grace);
    final canExtend = can(user, Permission.extendStay);
    return (
      [
        if (overstay) ...[
          PanelBanner(
            key: const ValueKey('panel.overstay'),
            icon: LucideIcons.triangleAlert,
            text:
                '${compactOverdue(now.difference(stay.paidUntil))} past '
                '${formatTime(stay.paidUntil)} · paid to '
                '${formatDayDate(stay.paidUntil)}',
            tone: BannerTone.red,
          ),
          const SizedBox(height: Space.x16),
        ],
        _GuestRow(
          name: detail.guest.fullName,
          line: maskPhone(detail.guest.phone),
        ),
        if (canExtend) ...[
          const SizedBox(height: Space.x16),
          Text('Extend', style: t.sectionTitle),
          const SizedBox(height: Space.x12),
          Row(
            children: [
              NightStepper(
                value: stepped,
                min: min,
                max: extendMaxNights(min),
                onChanged: (n) => setState(() {
                  _nights = n;
                  _typed = null;
                }),
                onTyped: (text) => setState(() {
                  _typed = text;
                  final n = parseNights(text);
                  if (n != null) _nights = n;
                }),
              ),
              const SizedBox(width: Space.x12),
              if (quote != null)
                Expanded(
                  child: Text(
                    'Out ${quote.newCheckoutText}',
                    key: const ValueKey('extend.newCheckout'),
                    style: t.body.copyWith(color: c.ink),
                  ),
                ),
            ],
          ),
          if (reason != null) ...[
            const SizedBox(height: Space.x6),
            Text(
              reason,
              key: const ValueKey('extend.minReason'),
              style: t.secondary.copyWith(color: c.inkSoft),
            ),
          ],
          if (nightsProblem != null) ...[
            const SizedBox(height: Space.x6),
            Text(
              nightsProblem,
              key: const ValueKey('extend.nightsError'),
              style: t.secondary.copyWith(color: c.redText),
            ),
          ],
          const SizedBox(height: Space.x12),
          _InfoRow(
            'Price',
            '${formatKes(stay.charges.first.pricePerNight)} (check-in price)',
            mono: true,
          ),
        ],
        const SizedBox(height: Space.x12),
        SegmentedChoice<PaymentMethod>(
          key: const ValueKey('extend.method'),
          options: [
            for (final m in PaymentMethod.values) ChoiceOption(m, m.label),
          ],
          selected: _method,
          onChanged: (m) => setState(() {
            _method = m;
            _codeError = null;
          }),
        ),
        if (_method == PaymentMethod.paybill) ...[
          const SizedBox(height: Space.x12),
          LabeledField(
            label: 'M-Pesa transaction code',
            controller: _code,
            fieldKey: const ValueKey('extend.mpesaCode'),
            textStyle: t.moneySmall,
            helperText: 'Each code can be used once. A used code is refused.',
            errorText: _codeError,
          ),
        ] else if (_codeError != null) ...[
          const SizedBox(height: Space.x8),
          Text(
            _codeError!,
            key: const ValueKey('panel.paymentError'),
            style: t.secondary.copyWith(color: c.redText),
          ),
        ],
        const SizedBox(height: Space.x12),
        _ConfirmLine(
          method: _method,
          quote: canExtend ? quote : null,
          late: terms is LateCheckout ? terms : null,
        ),
        if (!ownShift) ...[
          const SizedBox(height: Space.x16),
          ..._shiftNote(detail),
        ],
        ..._problemNote(),
      ],
      [
        if (canExtend)
          AppButton.primary(
            key: const ValueKey('extend.save'),
            label: quote?.button ?? 'Extend and print receipt',
            busy: _busy,
            onPressed: quote == null || _method == null || !ownShift
                ? null
                : () => _extend(user, detail, quote.nights),
          ),
        const SizedBox(height: Space.x10),
        if (terms is LateCheckout && can(user, Permission.checkOut))
          AppButton.secondary(
            key: const ValueKey('panel.checkOut'),
            label: terms.button,
            busy: _busy,
            onPressed: ownShift ? () => _checkOut(user, detail, terms) : null,
          )
        else
          AppButton.secondary(
            key: const ValueKey('panel.back'),
            label: 'Back',
            onPressed: () => _go(_Mode.overview),
          ),
      ],
    );
  }

  // ── Check out ────────────────────────────────────────────────────────

  (List<Widget>, List<Widget>) _checkOutState(
    UserAccount user,
    StayDetail detail,
    CheckoutTerms terms, {
    required bool ownShift,
  }) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    return (
      [
        _GuestRow(
          name: detail.guest.fullName,
          line: maskPhone(detail.guest.phone),
        ),
        const SizedBox(height: Space.x16),
        ...switch (terms) {
          EarlyCheckout(:final nightsPaid, :final nightsUsed, :final refund) =>
            [
              _InfoRow('Nights paid', '$nightsPaid'),
              _InfoRow('Nights used', '$nightsUsed (tonight counts)'),
              const SizedBox(height: Space.x12),
              Container(
                padding: const EdgeInsets.all(Space.x16),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(Radii.control),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Refund · ${refund.nights} × '
                      '${formatKes(refund.pricePerNight)}',
                      style: t.secondary.copyWith(color: c.inkSoft),
                    ),
                    Text(
                      formatKes(refund.amount),
                      key: const ValueKey('panel.refund'),
                      style: t.moneyHero.copyWith(color: c.ink),
                    ),
                    Text(
                      'Needs approval before it is paid',
                      style: t.secondary.copyWith(color: c.inkSoft),
                    ),
                  ],
                ),
              ),
            ],
          OnTimeCheckout() => [
            Text(
              'Within the paid time and grace, leaving is free. The bed then '
              'needs cleaning.',
              style: t.body.copyWith(color: c.inkSoft),
            ),
          ],
          // Past grace, the panel shows the extend state, whose second
          // button charges the nights started.
          LateCheckout() => const <Widget>[],
        },
        if (!ownShift) ...[
          const SizedBox(height: Space.x16),
          ..._shiftNote(detail),
        ],
        ..._problemNote(),
      ],
      [
        AppButton.primary(
          key: const ValueKey('panel.checkOut'),
          label: terms.button,
          busy: _busy,
          onPressed: ownShift && can(user, Permission.checkOut)
              ? () => _checkOut(user, detail, terms)
              : null,
        ),
        const SizedBox(height: Space.x10),
        AppButton.secondary(
          key: const ValueKey('panel.back'),
          label: 'Back',
          onPressed: () => _go(_Mode.overview),
        ),
      ],
    );
  }

  // ── Void stay (supervisor) ───────────────────────────────────────────

  (List<Widget>, List<Widget>) _voidState(UserAccount user, StayDetail detail) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final view = ref.watch(stayVoidProvider(detail.id)).value;
    if (view == null) {
      return (const [Center(child: CircularProgressIndicator())], const []);
    }
    final plan = view.plan;
    final blocker = voidBlocker(plan, user);
    final methods = {for (final p in detail.charges) p.receiptNumber: p.method};
    final others = [
      for (final s in plan.stays)
        if (s.id != detail.id) s,
    ];
    final cancel = AppButton.secondary(
      key: const ValueKey('panel.voidCancel'),
      label: 'Cancel',
      onPressed: () => _go(_Mode.overview),
    );
    return (
      [
        const PanelBanner(
          icon: LucideIcons.triangleAlert,
          text: 'Voids the stay and its payments',
          tone: BannerTone.red,
        ),
        const SizedBox(height: Space.x16),
        _GuestRow(
          name: detail.guest.fullName,
          line:
              'Checked in by ${view.checkedInBy} · '
              '${formatDayDate(detail.stay.charges.first.periodStart)}',
        ),
        const SizedBox(height: Space.x16),
        for (final p in plan.payments)
          _InfoRow(
            [p.receiptNumber, ?methods[p.receiptNumber]?.label].join(' · '),
            '− ${formatKes(p.amount)}',
            mono: true,
            valueColor: c.redText,
          ),
        for (final s in others)
          _InfoRow(
            'Also voids',
            s.place,
            key: ValueKey('panel.voidAlso.${s.id}'),
          ),
        _InfoRow('Bed after void', 'To clean'),
        const SizedBox(height: Space.x16),
        if (blocker != null)
          Note.warning(blocker, key: const ValueKey('panel.voidBlocked'))
        else
          LabeledField(
            label: 'Reason',
            controller: _reason,
            fieldKey: const ValueKey('panel.voidReason'),
            hintText: 'e.g. Checked into the wrong bed',
            onChanged: (_) => setState(() {}),
          ),
        ..._problemNote(),
        if (blocker == null) ...[
          const SizedBox(height: Space.x8),
          Text(
            'Nothing is deleted: the receipts show VOID and the money leaves '
            'the totals.',
            style: t.secondary.copyWith(color: c.muted),
          ),
        ],
      ],
      [
        if (blocker == null) ...[
          AppButton.urgent(
            key: const ValueKey('panel.voidConfirm'),
            label: 'Void stay',
            busy: _busy,
            onPressed: _reason.text.trim().isEmpty
                ? null
                : () => _void(user, detail, plan),
          ),
          const SizedBox(height: Space.x10),
        ],
        cancel,
      ],
    );
  }
}

/// The guest: a 40 px circle, the name and one line under it.
class _GuestRow extends StatelessWidget {
  const _GuestRow({required this.name, required this.line});

  final String name;
  final String line;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    return Row(
      key: const ValueKey('panel.guest'),
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle),
          child: Icon(LucideIcons.users, size: 18, color: c.inkSoft),
        ),
        const SizedBox(width: Space.x12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: t.bodyMedium.copyWith(color: c.ink)),
              Text(line, style: t.secondary.copyWith(color: c.muted)),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(
    this.label,
    this.value, {
    super.key,
    this.mono = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool mono;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: mono
                  ? t.moneySmall.copyWith(color: c.ink)
                  : t.secondary.copyWith(color: c.muted),
            ),
          ),
          const SizedBox(width: Space.x8),
          Text(
            value,
            style: (mono ? t.moneySmall : t.body).copyWith(
              color: valueColor ?? c.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Receipts", then each receipt once: number, method and this stay's
/// share of it.
class _Receipts extends StatelessWidget {
  const _Receipts(this.charges);

  final List<PaidCharge> charges;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final byReceipt = <String, (PaymentMethod, int)>{};
    for (final p in charges) {
      final (method, sum) = byReceipt[p.receiptNumber] ?? (p.method, 0);
      byReceipt[p.receiptNumber] = (method, sum + p.charge.amount);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Receipts', style: t.secondary.copyWith(color: c.muted)),
        const SizedBox(height: Space.x6),
        for (final MapEntry(key: number, value: (method, amount))
            in byReceipt.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.x4),
            child: Row(
              key: ValueKey('panel.receipt.$number'),
              children: [
                Expanded(
                  child: Text(
                    '$number · ${method.label}',
                    style: t.moneySmall.copyWith(color: c.ink),
                  ),
                ),
                Text(
                  formatKes(amount),
                  style: t.moneySmall.copyWith(color: c.ink),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The line above the buttons: what saving takes, or what's missing.
class _ConfirmLine extends StatelessWidget {
  const _ConfirmLine({
    required this.method,
    required this.quote,
    required this.late,
  });

  final PaymentMethod? method;
  final ExtendQuote? quote;
  final LateCheckout? late;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final quote = this.quote;
    return Container(
      constraints: const BoxConstraints(minHeight: Sizes.target),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x14,
        vertical: Space.x10,
      ),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: method == null
          ? Text(
              'Choose Cash or M-Pesa',
              key: const ValueKey('panel.confirmLine'),
              style: t.body.copyWith(color: c.muted),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (quote != null)
                  Row(
                    key: const ValueKey('panel.confirmLine'),
                    children: [
                      Expanded(
                        child: Text(
                          'Extend: ${quote.priceLine}, by ${method!.label}',
                          style: t.secondary.copyWith(color: c.ink),
                        ),
                      ),
                      Text(
                        formatKes(quote.total),
                        key: const ValueKey('extend.total'),
                        style: t.money,
                      ),
                    ],
                  ),
                if (late case final late?)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Or check out: ${late.charge.nights} × '
                          '${formatKes(late.charge.pricePerNight)}',
                          style: t.secondary.copyWith(color: c.inkSoft),
                        ),
                      ),
                      Text(
                        formatKes(late.charge.amount),
                        key: const ValueKey('panel.lateTotal'),
                        style: t.moneySmall,
                      ),
                    ],
                  ),
              ],
            ),
    );
  }
}

// ── Results ────────────────────────────────────────────────────────────

/// After the checkout: when, the bed needs cleaning, and the refund request
/// or the late charge's receipt.
class _Result extends StatelessWidget {
  const _Result({required this.result, required this.onDone});

  final CheckOutResult result;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final r = result;
    return Column(
      key: const ValueKey('panel.result'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle_rounded, color: c.marine, size: 24),
            const SizedBox(width: Space.x8),
            Expanded(
              child: Text(
                'Checked out at ${formatTime(r.checkedOutAt)}',
                key: const ValueKey('panel.result.title'),
                style: t.sectionTitle,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.x4),
        Text(
          '${r.guestName} · Room ${r.roomNumber}, Bed ${r.bedLabel} now needs '
          'cleaning.',
          style: t.body.copyWith(color: c.inkSoft),
        ),
        if (r.terms case EarlyCheckout(:final refund)) ...[
          const SizedBox(height: Space.x16),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: StatusBadge(
              'Waiting for owner approval',
              key: const ValueKey('panel.result.refundBadge'),
              tone: BadgeTone.warning,
            ),
          ),
          const SizedBox(height: Space.x8),
          Text(
            'Refund of ${formatKes(refund.amount)} requested '
            '(${refund.nights} × ${formatKes(refund.pricePerNight)}).',
            key: const ValueKey('panel.result.refund'),
            style: t.bodyMedium,
          ),
          Text(
            'The guest’s phone ${maskPhone(r.guestPhone)} is saved for the '
            'refund.',
            key: const ValueKey('panel.result.phone'),
            style: t.secondary.copyWith(color: c.inkSoft),
          ),
        ],
        if (r.paymentId case final paymentId?) ...[
          const SizedBox(height: Space.x16),
          ReceiptPanel(paymentId: paymentId),
        ],
        const SizedBox(height: Space.x20),
        AppButton.secondary(
          key: const ValueKey('panel.done'),
          label: 'Done',
          onPressed: onDone,
        ),
      ],
    );
  }
}

/// After a void: what it did.
class _Voided extends StatelessWidget {
  const _Voided({required this.plan, required this.onDone});

  final VoidPlan plan;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    return Column(
      key: const ValueKey('panel.voided'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle_rounded, color: c.marine, size: 24),
            const SizedBox(width: Space.x8),
            Expanded(child: Text('Stay voided', style: t.sectionTitle)),
          ],
        ),
        const SizedBox(height: Space.x4),
        Text(plan.summary, style: t.body.copyWith(color: c.inkSoft)),
        const SizedBox(height: Space.x20),
        AppButton.secondary(
          key: const ValueKey('panel.done'),
          label: 'Done',
          onPressed: onDone,
        ),
      ],
    );
  }
}
