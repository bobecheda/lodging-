import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/theme.dart';
import '../../../app/widgets/buttons.dart';
import '../../../app/widgets/labeled_field.dart';
import '../../../app/widgets/night_stepper.dart';
import '../../../app/widgets/notes.dart';
import '../../../app/widgets/segmented_choice.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/clock/nairobi.dart';
import '../../../core/money/kes.dart';
import '../../payments/domain/payment_rules.dart';
import '../../receipts/presentation/receipt_view.dart';
import '../../shifts/domain/shift_rules.dart';
import '../data/check_out_repository.dart';
import '../data/extend_repository.dart';
import '../domain/check_in.dart';
import '../domain/extend.dart';
import 'check_in_providers.dart';

/// FD-7 "Extend stay", in the bed panel above Check out: n more nights from
/// paid_until at the check-in price, paid now (Cash or M-Pesa), with its
/// own receipt. During an overstay the stepper starts at the nights already
/// started, counted as a late checkout would ([extendMinNights]).
class ExtendCard extends ConsumerStatefulWidget {
  const ExtendCard({
    super.key,
    required this.detail,
    required this.now,
    required this.graceMinutes,
    required this.ownShift,
    required this.onExtended,
  });

  final StayDetail detail;
  final DateTime now;
  final int graceMinutes;
  final bool ownShift;
  final ValueChanged<ExtendResult> onExtended;

  @override
  ConsumerState<ExtendCard> createState() => _ExtendCardState();
}

class _ExtendCardState extends ConsumerState<ExtendCard> {
  int? _nights;
  String? _typed;
  PaymentMethod? _method;
  final _code = TextEditingController();
  String? _codeError;
  String? _problem;
  var _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _extend(UserAccount user, int nights) async {
    setState(() {
      _busy = true;
      _problem = null;
      _codeError = null;
    });
    try {
      final result = await ref
          .read(extendRepositoryProvider)
          .extend(
            user,
            ExtendRequest(
              stayId: widget.detail.id,
              nights: nights,
              shownPaidUntil: widget.detail.stay.paidUntil,
              method: _method,
              mpesaCode: _method == PaymentMethod.paybill ? _code.text : null,
            ),
          );
      if (mounted) widget.onExtended(result);
    } on InvalidLatePayment catch (e) {
      if (mounted) setState(() => _codeError = e.message);
    } on ExtendRefused catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } on NoOpenShift {
      if (mounted) {
        setState(
          () => _problem = 'Extending records money. Open a shift first.',
        );
      }
    } on NotPermitted {
      if (mounted) setState(() => _problem = 'You can’t extend stays.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final user = ref.watch(sessionProvider);
    final stay = widget.detail.stay;
    final min = extendMinNights(stay, widget.now, widget.graceMinutes);
    final reason = minNightsReason(stay, widget.now, widget.graceMinutes);
    final stepped = _nights == null || _nights! < min ? min : _nights!;
    final chosen = _typed == null ? stepped : parseNights(_typed!);
    final nightsProblem = extendNightsError(chosen, minNights: min);
    final quote = nightsProblem == null ? quoteExtend(stay, chosen!) : null;

    return Container(
      key: const ValueKey('extend.card'),
      padding: const EdgeInsets.all(Space.x16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.marine, width: Sizes.borderStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Nights', style: t.bodyStrong)),
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
            ],
          ),
          if (reason != null) ...[
            const SizedBox(height: Space.x6),
            Text(
              reason,
              key: const ValueKey('extend.minReason'),
              style: t.small.copyWith(color: c.inkSoft),
            ),
          ],
          if (nightsProblem != null) ...[
            const SizedBox(height: Space.x6),
            Text(
              nightsProblem,
              key: const ValueKey('extend.nightsError'),
              style: t.small.copyWith(color: c.redText),
            ),
          ],
          if (quote != null) ...[
            const SizedBox(height: Space.x10),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'New checkout ', style: t.body),
                  TextSpan(text: quote.newCheckoutText, style: t.bodyStrong),
                  TextSpan(text: '.', style: t.body),
                ],
              ),
              key: const ValueKey('extend.newCheckout'),
            ),
            const SizedBox(height: Space.x10),
            Divider(color: c.lineSoft),
            Row(
              children: [
                Expanded(
                  child: Text(
                    quote.priceLine,
                    style: t.small.copyWith(color: c.muted),
                  ),
                ),
                Text(
                  formatKes(quote.total),
                  key: const ValueKey('extend.total'),
                  style: t.moneyLarge,
                ),
              ],
            ),
          ],
          const SizedBox(height: Space.x12),
          Text('Paid by', style: t.fieldLabel),
          const SizedBox(height: Space.x6),
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
              textStyle: t.monoStrong,
              helperText: 'Each code can be used once. A used code is refused.',
              errorText: _codeError,
            ),
          ] else if (_codeError != null) ...[
            const SizedBox(height: Space.x8),
            Text(
              _codeError!,
              key: const ValueKey('extend.paymentError'),
              style: t.small.copyWith(color: c.redText),
            ),
          ],
          if (_problem != null) ...[
            const SizedBox(height: Space.x12),
            Note.error(_problem!, key: const ValueKey('extend.problem')),
          ],
          const SizedBox(height: Space.x12),
          AppButton.primary(
            key: const ValueKey('extend.save'),
            label: 'Extend and issue receipt',
            busy: _busy,
            onPressed: user == null || quote == null || !widget.ownShift
                ? null
                : () => _extend(user, quote.nights),
          ),
        ],
      ),
    );
  }
}

/// After an extension: the new checkout and its receipt, with Print.
class ExtendedView extends StatelessWidget {
  const ExtendedView({super.key, required this.result, required this.onDone});

  final ExtendResult result;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final nights =
        '${result.nights} ${result.nights == 1 ? 'night' : 'nights'}';
    return Column(
      key: const ValueKey('extend.result'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle_rounded, color: c.marine, size: 24),
            const SizedBox(width: Space.x8),
            Expanded(
              child: Text(
                'Extended by $nights',
                key: const ValueKey('extend.result.title'),
                style: t.sectionTitle,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.x4),
        Text(
          'New checkout ${formatDayDateComma(result.newPaidUntil)}.',
          key: const ValueKey('extend.result.checkout'),
          style: t.body.copyWith(color: c.inkSoft),
        ),
        const SizedBox(height: Space.x16),
        ReceiptPanel(paymentId: result.paymentId),
        const SizedBox(height: Space.x20),
        AppButton.secondary(
          key: const ValueKey('extend.done'),
          label: 'Done',
          onPressed: onDone,
        ),
      ],
    );
  }
}
