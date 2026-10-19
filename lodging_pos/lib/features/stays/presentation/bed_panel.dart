import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/gate.dart';
import '../../../app/theme/theme.dart';
import '../../../app/widgets/buttons.dart';
import '../../../app/widgets/labeled_field.dart';
import '../../../app/widgets/notes.dart';
import '../../../app/widgets/segmented_choice.dart';
import '../../../app/widgets/side_panel.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/clock/nairobi.dart';
import '../../../core/contacts/phone.dart';
import '../../../core/money/kes.dart';
import '../../bed_board/presentation/bed_board_providers.dart';
import '../../payments/domain/payment_rules.dart';
import '../../receipts/presentation/receipt_view.dart';
import '../../shifts/domain/shift_rules.dart';
import '../../shifts/presentation/shift_providers.dart';
import '../data/check_out_repository.dart';
import '../data/extend_repository.dart';
import '../domain/check_out.dart';
import '../domain/stay_rules.dart';
import 'check_in_providers.dart';
import 'extend_card.dart';

/// Opens the bed panel for [stayId]: 440px from the right over the dimmed
/// board (docs/design.md, "Bed panel"). Escape or a tap on the scrim
/// closes it.
Future<void> showBedPanel(BuildContext context, String stayId) => showSidePanel(
  context,
  barrierLabel: 'Close the bed panel',
  child: BedPanel(key: ValueKey('panel.$stayId'), stayId: stayId),
);

/// FD-8 "Bed panel — check out": the guest, what they've paid, and the
/// checkout that applies right now: free, with a refund request, or with a
/// late charge (artboard "Bed panel — renew, check out"; Extend arrives
/// with FD-7).
class BedPanel extends ConsumerStatefulWidget {
  const BedPanel({super.key, required this.stayId});

  final String stayId;

  @override
  ConsumerState<BedPanel> createState() => _BedPanelState();
}

class _BedPanelState extends ConsumerState<BedPanel> {
  PaymentMethod? _method;
  final _code = TextEditingController();
  String? _codeError;
  String? _problem;
  var _busy = false;
  CheckOutResult? _result;
  ExtendResult? _extended;

  static const _noShift = 'Checkout records money. Open a shift first.';

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).pop();

  Future<void> _checkOut(
    UserAccount user,
    StayDetail detail,
    CheckoutTerms shown,
  ) async {
    if (shown is! LateCheckout) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => _ConfirmDialog(
          text: checkoutConfirmText(
            guestName: detail.guest.fullName,
            roomNumber: detail.roomNumber,
            bedLabel: detail.bedLabel,
            terms: shown,
          ),
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _problem = null;
      _codeError = null;
    });
    try {
      final result = await ref
          .read(checkOutRepositoryProvider)
          .checkOut(
            user,
            CheckOutRequest(
              stayId: detail.id,
              shown: shown,
              method: _method,
              mpesaCode: _method == PaymentMethod.paybill ? _code.text : null,
            ),
          );
      if (mounted) setState(() => _result = result);
    } on InvalidLatePayment catch (e) {
      if (mounted) setState(() => _codeError = e.message);
    } on CheckOutRefused catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } on NoOpenShift {
      if (mounted) setState(() => _problem = _noShift);
    } on NotPermitted {
      if (mounted) setState(() => _problem = 'You can’t check guests out.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final user = ref.watch(sessionProvider);
    final detail = ref.watch(stayDetailProvider(widget.stayId)).value;
    final grace = ref.watch(boardGraceMinutesProvider).value;
    final now = ref.watch(boardNowProvider).value;
    final shift = ref.watch(currentShiftProvider).value;

    if (user == null || detail == null || grace == null || now == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final first = detail.stay.charges.first;
    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Room ${detail.roomNumber} · Bed ${detail.bedLabel}',
                  key: const ValueKey('panel.title'),
                  style: t.cardTitle,
                ),
              ),
              Text(
                '${first.categoryName} · ${formatKes(first.pricePerNight)} / '
                'night (check-in price)',
                style: t.small.copyWith(color: c.muted),
              ),
            ],
          ),
        ),
        IconButton(
          key: const ValueKey('panel.close'),
          tooltip: 'Close',
          onPressed: _close,
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );

    final result = _result;
    final extended = _extended;
    final List<Widget> body;
    if (result != null) {
      body = [_Result(result: result, onDone: _close)];
    } else if (extended != null) {
      body = [ExtendedView(result: extended, onDone: _close)];
    } else if (!detail.isActive) {
      body = [
        Note.info(
          'This guest checked out '
          '${formatDayDateComma(detail.checkedOutAt!)}.',
        ),
      ];
    } else {
      final terms = checkoutTerms(detail.stay, now, grace);
      final past = minutesPastGrace(detail.stay.paidUntil, now, grace);
      final ownShift = shift != null && shift.userId == user.id;
      body = [
        if (past > 0) ...[
          _OverstayBanner(
            minutes: past,
            paidUntil: detail.stay.paidUntil,
            graceEnded: detail.stay.paidUntil.add(Duration(minutes: grace)),
          ),
          const SizedBox(height: Space.x20),
        ],
        _caps(context, 'GUEST'),
        Text(detail.guest.fullName, style: t.sectionTitle),
        Text(
          [
            maskPhone(detail.guest.phone),
            detail.guest.maskedId ?? 'no ID recorded',
          ].join(' · '),
          style: t.small.copyWith(color: c.inkSoft),
        ),
        const SizedBox(height: Space.x20),
        _caps(context, 'PAID SO FAR'),
        for (final paid in detail.charges) _PaidRow(paid),
        const SizedBox(height: Space.x20),
        // FD-7: Extend first, then Check out (artboard order).
        if (can(user, Permission.extendStay)) ...[
          _caps(context, 'EXTEND STAY'),
          ExtendCard(
            key: ValueKey('extend.${detail.id}.${detail.stay.paidUntil}'),
            detail: detail,
            now: now,
            graceMinutes: grace,
            ownShift: ownShift,
            onExtended: (r) => setState(() => _extended = r),
          ),
          const SizedBox(height: Space.x20),
        ],
        _caps(context, 'CHECK OUT'),
        ..._checkoutSection(context, terms),
        if (!ownShift) ...[
          const SizedBox(height: Space.x12),
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
        ],
        if (_problem != null) ...[
          const SizedBox(height: Space.x12),
          Note.error(_problem!, key: const ValueKey('panel.problem')),
        ],
        const SizedBox(height: Space.x16),
        if (terms is LateCheckout)
          AppButton.destructive(
            key: const ValueKey('panel.checkOut'),
            label: terms.button,
            busy: _busy,
            onPressed: ownShift ? () => _checkOut(user, detail, terms) : null,
          )
        else
          AppButton.primary(
            key: const ValueKey('panel.checkOut'),
            label: terms.button,
            busy: _busy,
            onPressed: ownShift ? () => _checkOut(user, detail, terms) : null,
          ),
        const SizedBox(height: Space.x8),
        Text(
          terms is LateCheckout
              ? 'Past the grace time, leaving costs '
                    '${terms.charge.nights == 1 ? 'one more night' : '${terms.charge.nights} more nights'}. '
                    'The bed then needs cleaning.'
              : 'The bed then needs cleaning.',
          textAlign: TextAlign.center,
          style: t.small.copyWith(color: c.muted),
        ),
      ];
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.x28,
        Space.x24,
        Space.x20,
        Space.x24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: Space.x20),
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.only(right: Space.x8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: body,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The part that differs: refund figures, the free window, or the late
  /// charge with its payment.
  List<Widget> _checkoutSection(BuildContext context, CheckoutTerms terms) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    Widget row(String label, String value, {Key? key}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: t.body.copyWith(color: c.muted)),
          ),
          Text(value, key: key, style: t.monoStrong),
        ],
      ),
    );
    return switch (terms) {
      EarlyCheckout(:final nightsPaid, :final nightsUsed, :final refund) => [
        row('Nights paid', '$nightsPaid'),
        row('Nights used', '$nightsUsed'),
        row('Nights to refund', '${refund.nights}'),
        row(
          'Refund (${refund.nights} × ${formatKes(refund.pricePerNight)})',
          formatKes(refund.amount),
          key: const ValueKey('panel.refund'),
        ),
        const SizedBox(height: Space.x8),
        const Note.info(
          'The night in progress is not refunded. The owner must approve '
          'the refund before it is paid.',
        ),
      ],
      OnTimeCheckout() => [
        Text(
          'Within the paid time and grace, leaving is free.',
          style: t.body.copyWith(color: c.inkSoft),
        ),
      ],
      LateCheckout(:final charge) => [
        row(
          '${charge.nights} × ${formatKes(charge.pricePerNight)} '
          '(check-in price)',
          formatKes(charge.amount),
          key: const ValueKey('panel.lateTotal'),
        ),
        const SizedBox(height: Space.x12),
        Text('Paid by', style: t.fieldLabel),
        const SizedBox(height: Space.x6),
        SegmentedChoice<PaymentMethod>(
          key: const ValueKey('panel.method'),
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
            fieldKey: const ValueKey('panel.mpesaCode'),
            textStyle: t.monoStrong,
            helperText: 'Each code can be used once. A used code is refused.',
            errorText: _codeError,
          ),
        ] else if (_codeError != null) ...[
          const SizedBox(height: Space.x8),
          Text(
            _codeError!,
            key: const ValueKey('panel.paymentError'),
            style: t.small.copyWith(color: c.redText),
          ),
        ],
      ],
    };
  }

  static Widget _caps(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: Space.x6),
    child: Text(
      text,
      style: LodgingType.of(context).capsLabel
          .copyWith(color: LodgingColors.of(context).muted),
    ),
  );
}

/// Red: how far past grace, paid until and when grace ended.
class _OverstayBanner extends StatelessWidget {
  const _OverstayBanner({
    required this.minutes,
    required this.paidUntil,
    required this.graceEnded,
  });

  final int minutes;
  final DateTime paidUntil;
  final DateTime graceEnded;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final past = minutes < 60
        ? '$minutes min'
        : '${minutes ~/ 60} h ${minutes % 60} min';
    return Container(
      key: const ValueKey('panel.overstay'),
      padding: const EdgeInsets.all(Space.x14),
      decoration: BoxDecoration(
        color: c.red,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OVERSTAY · $past past grace',
            style: t.bodyStrong.copyWith(color: c.white),
          ),
          Text(
            'Paid until ${formatWeekdayTime(paidUntil)}. Grace ended '
            '${formatTime(graceEnded)}.',
            style: t.small.copyWith(color: c.white),
          ),
        ],
      ),
    );
  }
}

/// `Wed 22:00 → Thu 10:00 · 1 night` and its receipt number.
class _PaidRow extends StatelessWidget {
  const _PaidRow(this.paid);

  final PaidCharge paid;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final ch = paid.charge;
    final nights = '${ch.nights} ${ch.nights == 1 ? 'night' : 'nights'}';
    return Container(
      margin: const EdgeInsets.only(bottom: Space.x6),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.x12,
        vertical: Space.x10,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${formatWeekdayTime(ch.periodStart)} → '
              '${formatWeekdayTime(ch.periodEnd)} · $nights'
              '${ch.kind == ChargeKind.lateCheckout ? ' · late' : ''}',
              style: t.small.copyWith(color: c.ink),
            ),
          ),
          Text(paid.receiptNumber, style: t.monoStrong),
        ],
      ),
    );
  }
}

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
              'WAITING FOR OWNER APPROVAL',
              key: const ValueKey('panel.result.refundBadge'),
              tone: BadgeTone.warning,
            ),
          ),
          const SizedBox(height: Space.x8),
          Text(
            'Refund of ${formatKes(refund.amount)} requested '
            '(${refund.nights} × ${formatKes(refund.pricePerNight)}).',
            key: const ValueKey('panel.result.refund'),
            style: t.bodyStrong,
          ),
          Text(
            'The guest’s phone ${maskPhone(r.guestPhone)} is saved for the '
            'refund.',
            key: const ValueKey('panel.result.phone'),
            style: t.small.copyWith(color: c.inkSoft),
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

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    return AlertDialog(
      key: const ValueKey('panel.confirm'),
      title: Text('Check out?', style: t.sectionTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Text(text, style: t.body),
      ),
      actions: [
        AppButton.secondary(
          key: const ValueKey('panel.confirm.cancel'),
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton.primary(
          key: const ValueKey('panel.confirm.ok'),
          label: 'Check out',
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}
