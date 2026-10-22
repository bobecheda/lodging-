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
import '../../../core/clock/nairobi.dart';
import '../../../core/contacts/phone.dart';
import '../../../core/money/kes.dart';
import '../../payments/domain/payment_rules.dart';
import '../../receipts/domain/receipt.dart';
import '../../receipts/presentation/receipt_view.dart';
import '../../shifts/domain/shift_rules.dart';
import '../../shifts/presentation/shift_providers.dart';
import '../data/refunds_repository.dart';
import '../domain/refund.dart';
import 'refunds_providers.dart';

/// The desk's Refunds (AD-7, `payRefund`): approved refunds to pay from your
/// own shift, those waiting for the owner, and rejections with the owner's
/// reason (last 14 days). `/refunds?pay=<id>` reopens a pay panel, e.g.
/// after opening a shift from it.
class RefundsScreen extends ConsumerStatefulWidget {
  const RefundsScreen({super.key, this.openRefundId});

  final String? openRefundId;

  @override
  ConsumerState<RefundsScreen> createState() => _RefundsScreenState();
}

class _RefundsScreenState extends ConsumerState<RefundsScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.openRefundId case final id?) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showPayRefundPanel(context, id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final refunds = ref.watch(deskRefundsProvider);
    final Widget body = switch (refunds) {
      AsyncData(:final value) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Section(
              key: const ValueKey('refunds.toPay'),
              title: 'TO PAY',
              empty: 'Nothing to pay.',
              rows: [
                for (final v in value.toPay)
                  _RefundRow(
                    v,
                    detail:
                        'Approved by ${v.decidedByName} · '
                        '${formatDayDateComma(v.refund.decision!.decidedAt)}',
                    trailing: AppButton.primary(
                      key: ValueKey('refunds.pay.${v.id}'),
                      label: 'Pay',
                      compact: true,
                      onPressed: () => showPayRefundPanel(context, v.id),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Space.x20),
            _Section(
              key: const ValueKey('refunds.waiting'),
              title: 'WAITING FOR OWNER APPROVAL',
              empty: 'No refunds waiting for the owner.',
              rows: [
                for (final v in value.waiting)
                  _RefundRow(
                    v,
                    detail:
                        'Requested by ${v.requestedByName} · '
                        '${formatDayDateComma(v.refund.requestedAt)}',
                    trailing: const StatusBadge(
                      'WAITING FOR OWNER APPROVAL',
                      tone: BadgeTone.warning,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Space.x20),
            _Section(
              key: const ValueKey('refunds.rejected'),
              title: 'REJECTED · LAST 14 DAYS',
              empty: 'No refunds rejected lately.',
              rows: [
                for (final v in value.rejected)
                  _RefundRow(
                    v,
                    detail:
                        'Rejected by ${v.decidedByName} · '
                        '${formatDayDateComma(v.refund.decision!.decidedAt)}',
                    reason: v.refund.decision!.note,
                    trailing: const StatusBadge(
                      'REJECTED',
                      tone: BadgeTone.disabled,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      AsyncError(:final error) => Note.error(
        '$error',
        title: 'Refunds could not be loaded.',
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text('Refunds', style: t.pageTitle)),
        Text(
          'Refunds the owner approved are paid here, in full, from your own '
          'shift.',
          style: t.small.copyWith(color: c.muted),
        ),
        const SizedBox(height: Space.x20),
        Expanded(child: body),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    super.key,
    required this.title,
    required this.empty,
    required this.rows,
  });

  final String title;
  final String empty;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Space.x20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              rows.isEmpty ? title : '$title · ${rows.length}',
              style: t.cardHeading,
            ),
            const SizedBox(height: Space.x8),
            if (rows.isEmpty)
              Text(empty, style: t.body.copyWith(color: c.muted))
            else
              for (final (i, r) in rows.indexed) ...[
                if (i > 0) Divider(height: 1, color: c.lineSoft),
                r,
              ],
          ],
        ),
      ),
    );
  }
}

class _RefundRow extends StatelessWidget {
  const _RefundRow(
    this.refund, {
    required this.detail,
    required this.trailing,
    this.reason,
  });

  final RefundView refund;
  final String detail;
  final String? reason;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final v = refund;
    return Padding(
      key: ValueKey('refunds.row.${v.id}'),
      padding: const EdgeInsets.symmetric(vertical: Space.x12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v.guestName, style: t.bodyStrong),
                Text(
                  '${maskPhone(v.guestPhone)} · Room ${v.roomNumber} · '
                  'Bed ${v.bedLabel} · ${v.refund.nights} '
                  '${v.refund.nights == 1 ? 'night' : 'nights'}',
                  style: t.small.copyWith(color: c.muted),
                ),
                Text(detail, style: t.small.copyWith(color: c.muted)),
                if (reason != null)
                  Text(
                    '“$reason”',
                    key: ValueKey('refunds.reason.${v.id}'),
                    style: t.body.copyWith(color: c.inkSoft),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Space.x12),
          Text(formatKes(v.refund.amount), style: t.monoStrong),
          const SizedBox(width: Space.x16),
          trailing,
        ],
      ),
    );
  }
}

/// Opens the pay panel for [refundId] (440 px, from the right).
Future<void> showPayRefundPanel(BuildContext context, String refundId) =>
    showSidePanel(
      context,
      child: PayRefundPanel(refundId: refundId),
      barrierLabel: 'Close the refund',
    );

/// Pays one approved refund from your own open shift: Cash drawer or M-Pesa
/// (Paybill, with the phone it goes to and the transaction code), the
/// amount fixed; then the REFUND receipt with Print.
class PayRefundPanel extends ConsumerStatefulWidget {
  const PayRefundPanel({super.key, required this.refundId});

  final String refundId;

  @override
  ConsumerState<PayRefundPanel> createState() => _PayRefundPanelState();
}

class _PayRefundPanelState extends ConsumerState<PayRefundPanel> {
  PaymentMethod? _method;
  final _sendTo = TextEditingController();
  final _code = TextEditingController();
  String? _sendToError;
  String? _codeError;
  String? _methodError;
  String? _problem;
  String? _paidKey;
  var _busy = false;

  static const _noShift = 'Paying a refund records money. Open a shift first.';

  @override
  void dispose() {
    _sendTo.dispose();
    _code.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).maybePop();

  Future<void> _pay(RefundView v) async {
    final user = ref.read(sessionProvider);
    if (user == null) return;
    setState(() {
      _busy = true;
      _problem = null;
      _sendToError = null;
      _codeError = null;
      _methodError = null;
    });
    try {
      final paybill = _method == PaymentMethod.paybill;
      await ref
          .read(refundsRepositoryProvider)
          .pay(
            user,
            PayoutRequest(
              refundId: v.id,
              method: _method,
              mpesaCode: paybill ? _code.text : null,
              sendTo: paybill ? _sendTo.text : null,
            ),
          );
      if (mounted) setState(() => _paidKey = refundReceiptKey(v.id));
    } on PayoutRefused catch (e) {
      if (mounted) setState(() => _methodError = e.message);
    } on InvalidMpesaCode catch (e) {
      if (mounted) setState(() => _codeError = e.message);
    } on InvalidPayoutPhone catch (e) {
      if (mounted) setState(() => _sendToError = e.message);
    } on RefundRuleViolation catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } on NoOpenShift {
      if (mounted) setState(() => _problem = _noShift);
    } on NotPermitted {
      if (mounted) setState(() => _problem = 'You can’t pay refunds.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final view = ref.watch(refundViewProvider(widget.refundId));
    final user = ref.watch(sessionProvider);
    final shift = ref.watch(currentShiftProvider).value;
    final ownShift = user != null && shift != null && shift.userId == user.id;

    final List<Widget> body;
    if (_paidKey case final key?) {
      body = [
        Row(
          children: [
            Icon(Icons.check_circle_rounded, color: c.marine, size: 24),
            const SizedBox(width: Space.x8),
            Expanded(
              child: Text(
                'Refund paid',
                key: const ValueKey('pay.done.title'),
                style: t.sectionTitle,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.x16),
        ReceiptPanel(paymentId: key),
        const SizedBox(height: Space.x20),
        AppButton.secondary(
          key: const ValueKey('pay.done'),
          label: 'Done',
          onPressed: _close,
        ),
      ];
    } else if (view case AsyncData(value: final v)) {
      body = _form(context, v, ownShift: ownShift);
    } else if (view case AsyncError(:final error)) {
      body = [Note.error('$error', title: 'The refund could not be loaded.')];
    } else {
      body = const [Center(child: CircularProgressIndicator())];
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.x24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Pay refund', style: t.pageTitle)),
                IconButton(
                  key: const ValueKey('pay.close'),
                  tooltip: 'Close',
                  onPressed: _close,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: Space.x12),
            ...body,
          ],
        ),
      ),
    );
  }

  List<Widget> _form(
    BuildContext context,
    RefundView v, {
    required bool ownShift,
  }) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final r = v.refund;
    if (r.status != RefundStatus.approved) {
      return [
        Note.info(switch (r.status) {
          RefundStatus.paid => 'This refund has already been paid.',
          RefundStatus.rejected => 'The owner rejected this refund.',
          _ => 'This refund is waiting for the owner’s approval.',
        }, key: const ValueKey('pay.notApproved')),
      ];
    }
    return [
      Text(v.guestName, style: t.sectionTitle),
      Text(
        'Room ${v.roomNumber} · Bed ${v.bedLabel} · approved by '
        '${v.decidedByName}',
        style: t.small.copyWith(color: c.muted),
      ),
      const SizedBox(height: Space.x16),
      Container(
        padding: const EdgeInsets.all(Space.x16),
        decoration: BoxDecoration(
          color: c.marineTint,
          borderRadius: BorderRadius.circular(Radii.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formatKes(r.amount),
              key: const ValueKey('pay.amount'),
              style: t.moneyHero.copyWith(color: c.marine),
            ),
            const SizedBox(height: Space.x6),
            Text(
              '${r.nights} ${r.nights == 1 ? 'night' : 'nights'} × '
              '${formatKes(r.pricePerNight)} (check-in price). Paid in full; '
              'it can’t be changed.',
              style: t.small.copyWith(color: c.inkSoft),
            ),
          ],
        ),
      ),
      const SizedBox(height: Space.x16),
      Text('Paid back from', style: t.fieldLabel),
      const SizedBox(height: Space.x6),
      SegmentedChoice<PaymentMethod>(
        key: const ValueKey('pay.method'),
        options: const [
          ChoiceOption(PaymentMethod.cash, 'Cash drawer'),
          ChoiceOption(PaymentMethod.paybill, 'M-Pesa (Paybill)'),
        ],
        selected: _method,
        onChanged: (m) => setState(() {
          _method = m;
          _methodError = null;
          // The guest's own number to start with; editable.
          if (m == PaymentMethod.paybill && _sendTo.text.isEmpty) {
            _sendTo.text = v.guestPhone;
          }
        }),
      ),
      if (_methodError != null) ...[
        const SizedBox(height: Space.x6),
        Text(
          _methodError!,
          key: const ValueKey('pay.methodError'),
          style: t.small.copyWith(color: c.redText),
        ),
      ],
      if (_method == PaymentMethod.paybill) ...[
        const SizedBox(height: Space.x12),
        LabeledField(
          label: 'Send to',
          controller: _sendTo,
          fieldKey: const ValueKey('pay.sendTo'),
          textStyle: t.monoStrong,
          helperText:
              'The guest’s phone. Change it if they asked for another '
              'number.',
          errorText: _sendToError,
        ),
        const SizedBox(height: Space.x12),
        LabeledField(
          label: 'M-Pesa transaction code',
          controller: _code,
          fieldKey: const ValueKey('pay.mpesaCode'),
          textStyle: t.monoStrong,
          helperText:
              'The code of the money you sent. Each code can be used '
              'once.',
          errorText: _codeError,
        ),
      ],
      if (!ownShift) ...[
        const SizedBox(height: Space.x12),
        const Note.warning(_noShift, key: ValueKey('pay.noShift')),
        const SizedBox(height: Space.x8),
        AppButton.secondary(
          key: const ValueKey('pay.openShift'),
          label: 'Open shift',
          onPressed: () {
            final back = Uri(
              path: Routes.refunds,
              queryParameters: {'pay': v.id},
            ).toString();
            _close();
            context.go(Routes.shiftThen(back));
          },
        ),
      ],
      if (_problem != null) ...[
        const SizedBox(height: Space.x12),
        Note.error(_problem!, key: const ValueKey('pay.problem')),
      ],
      const SizedBox(height: Space.x16),
      AppButton.primary(
        key: const ValueKey('pay.save'),
        label: 'Pay ${formatKes(r.amount)} and issue receipt',
        busy: _busy,
        onPressed: ownShift ? () => _pay(v) : null,
      ),
    ];
  }
}
