import 'package:flutter/material.dart';

import '../../../app/theme/theme.dart';
import '../../../app/widgets/buttons.dart';
import '../../../app/widgets/labeled_field.dart';
import '../../../app/widgets/notes.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/clock/nairobi.dart';
import '../../../core/money/kes.dart';
import '../domain/refund.dart';
import '../domain/refund_detail.dart';

/// The body of "Refund request" (Figma "03"): the guest, the stay and its
/// receipts, the calculated amount (unchangeable), who asked, then Approve
/// or Reject. Shared by the desk and the owner's phone; each brings its own
/// data and decision.
class RefundDetailBody extends StatelessWidget {
  const RefundDetailBody({
    super.key,
    required this.detail,
    required this.maskedPhone,
    required this.canDecide,
    required this.busy,
    required this.onApprove,
    required this.onReject,
    this.problem,
  });

  final RefundDetail detail;

  /// The guest's phone, already masked ("0711 ••• 482"): the phone app
  /// never has the full number.
  final String maskedPhone;

  /// The signed-in user may decide refunds.
  final bool canDecide;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final String? problem;

  @override
  Widget build(BuildContext context) {
    final d = detail;
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final v = d.view;
    final r = v.refund;
    Widget card(String title, List<Widget> children, {Key? key}) => Card(
      key: key,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Space.x20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: t.cardHeading),
            const SizedBox(height: Space.x10),
            ...children,
          ],
        ),
      ),
    );
    Widget row(String label, String value, {Key? key}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.body.copyWith(color: c.inkSoft)),
          const SizedBox(width: Space.x12),
          // Long values (several receipts) wrap rather than overflow.
          Expanded(
            child: Text(
              value,
              key: key,
              style: t.bodyStrong,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
    final role = switch (v.requestedByRole) {
      Role.receptionist => ' (receptionist)',
      Role.supervisor => ' (supervisor)',
      _ => '',
    };
    final decision = r.decision;
    final decides = canDecide && r.status == RefundStatus.requested;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Refund request', style: t.pageTitle),
        ),
        const SizedBox(height: Space.x16),
        card('GUEST', [
          Text(v.guestName, style: t.sectionTitle),
          const SizedBox(height: Space.x4),
          Text(
            '$maskedPhone · Room ${v.roomNumber} · '
            'Bed ${v.bedLabel} · ${d.categoryName}',
            key: const ValueKey('refund.guest'),
            style: t.small.copyWith(color: c.muted),
          ),
        ]),
        const SizedBox(height: Space.x12),
        card('THE STAY', [
          row('Checked in', formatDayDateComma(d.checkInAt)),
          for (final (i, ch) in d.charges.indexed)
            row(
              i == 0 ? 'Paid' : '',
              '${ch.nights} ${ch.nights == 1 ? 'night' : 'nights'} × '
              '${formatKes(ch.pricePerNight)} · ${ch.receiptNumber}',
              key: ValueKey('refund.paid.$i'),
            ),
          row('Left', formatDayDateComma(d.checkedOutAt)),
          row(
            'Nights used',
            '${d.nightsUsed} (the night they left counts as used)',
            key: const ValueKey('refund.used'),
          ),
          row(
            'Nights not used',
            '${d.nightsNotUsed}',
            key: const ValueKey('refund.notUsed'),
          ),
        ]),
        const SizedBox(height: Space.x12),
        Container(
          key: const ValueKey('refund.amountBox'),
          padding: const EdgeInsets.all(Space.x20),
          decoration: BoxDecoration(
            color: c.marineTint,
            borderRadius: BorderRadius.circular(Radii.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('REFUND', style: t.cardHeading.copyWith(color: c.marine)),
              const SizedBox(height: Space.x8),
              Text(
                formatKes(r.amount),
                key: const ValueKey('refund.amount'),
                style: t.moneyHero.copyWith(color: c.marine),
              ),
              const SizedBox(height: Space.x8),
              Text(
                '${r.nights} ${r.nights == 1 ? 'night' : 'nights'} × '
                '${formatKes(r.pricePerNight)} (check-in price). Worked out '
                'by the system; it can’t be changed.',
                style: t.small.copyWith(color: c.inkSoft),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.x12),
        Text(
          'Requested by ${v.requestedByName}$role · '
          '${formatDayDateComma(r.requestedAt)}. Once you approve, the desk '
          'pays it from the cash drawer or M-Pesa and prints a REFUND '
          'receipt.',
          key: const ValueKey('refund.requestedBy'),
          style: t.small.copyWith(color: c.muted),
        ),
        const SizedBox(height: Space.x20),
        if (decision != null)
          switch (r.status) {
            RefundStatus.approved => Note.info(
              'Approved by ${v.decidedByName} · '
              '${formatDayDateComma(decision.decidedAt)}. The desk pays it '
              'from the next shift.',
              key: const ValueKey('refund.decided'),
            ),
            RefundStatus.paid => Note.info(
              'Approved by ${v.decidedByName}; paid by ${v.paidByName} · '
              '${formatDayDateComma(r.payout!.paidAt)}, receipt '
              '${v.receiptNumber}.',
              key: const ValueKey('refund.decided'),
            ),
            _ => Note.warning(
              'Rejected by ${v.decidedByName} · '
              '${formatDayDateComma(decision.decidedAt)}: '
              '“${decision.note}”. The desk sees your reason.',
              key: const ValueKey('refund.decided'),
            ),
          },
        if (problem != null) ...[
          Note.error(problem!, key: const ValueKey('refund.problem')),
          const SizedBox(height: Space.x12),
        ],
        if (decides) ...[
          AppButton.primary(
            key: const ValueKey('refund.approve'),
            label: 'Approve refund of ${formatKes(r.amount)}',
            large: true,
            busy: busy,
            onPressed: onApprove,
          ),
          const SizedBox(height: Space.x10),
          AppButton.destructive(
            key: const ValueKey('refund.reject'),
            label: 'Reject',
            onPressed: busy ? null : onReject,
          ),
        ],
        const SizedBox(height: Space.x24),
      ],
    );
  }
}

/// "Reject this refund?" (Figma "03b Reject reason"): the reason is
/// required; the desk sees it. Pops the reason, or null on Cancel.
class RejectRefundDialog extends StatefulWidget {
  const RejectRefundDialog({
    super.key,
    required this.guestName,
    required this.amount,
  });

  final String guestName;
  final int amount;

  @override
  State<RejectRefundDialog> createState() => _RejectRefundDialogState();
}

class _RejectRefundDialogState extends State<RejectRefundDialog> {
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Give a reason for rejecting the refund.');
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    return AlertDialog(
      key: const ValueKey('refund.rejectDialog'),
      title: Text('Reject this refund?', style: t.sectionTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.guestName} · ${formatKes(widget.amount)}. The desk '
              'will see your reason.',
              style: t.small,
            ),
            const SizedBox(height: Space.x12),
            LabeledField(
              label: 'Reason',
              controller: _reason,
              fieldKey: const ValueKey('refund.reason'),
              errorText: _error,
              autofocus: true,
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        AppButton.secondary(
          key: const ValueKey('refund.reason.cancel'),
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton.destructive(
          key: const ValueKey('refund.reason.reject'),
          label: 'Reject refund',
          onPressed: _submit,
        ),
      ],
    );
  }
}
