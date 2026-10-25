import 'package:flutter/material.dart';

import '../../../app/theme/theme.dart';
import '../../../app/widgets/buttons.dart';
import '../../../app/widgets/labeled_field.dart';
import '../../../app/widgets/notes.dart';
import '../../../core/clock/nairobi.dart';
import '../../../core/money/kes.dart';
import '../domain/price_request.dart';

/// A price request waiting for the owner (Figma "06 Prices"): who asked,
/// the change, their reason, the stale warning, then Approve (off when
/// stale) and Reject. Shared by the desk and the owner's phone.
class PriceRequestCard extends StatelessWidget {
  const PriceRequestCard({
    super.key,
    required this.request,
    required this.categoryName,
    required this.requestedByFirstName,
    required this.requestedByRole,
    required this.staleMessage,
    required this.now,
    required this.busy,
    required this.locked,
    required this.onApprove,
    required this.onReject,
  });

  final PriceRequest request;
  final String categoryName;
  final String requestedByFirstName;

  /// As stored (`supervisor`); null when unknown.
  final String? requestedByRole;

  /// Why it can only be rejected now ([staleError]); null when it can be
  /// approved.
  final String? staleMessage;
  final DateTime now;
  final bool busy;

  /// Another request is being decided.
  final bool locked;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final r = request;
    final id = r.id;
    final role = requestedByRole?.toUpperCase();
    final when = formatWhen(r.requestedAt, now: now);
    return Container(
      key: ValueKey('priceRequest.card.$id'),
      padding: const EdgeInsets.all(Space.x20),
      decoration: BoxDecoration(
        color: c.marineTint,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.marine, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'REQUEST FROM ${requestedByFirstName.toUpperCase()}'
            '${role == null ? '' : ' ($role)'}',
            style: t.cardHeading.copyWith(color: c.marine),
          ),
          const SizedBox(height: Space.x10),
          Wrap(
            spacing: Space.x10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(categoryName, style: t.sectionTitle),
              Text(
                'KES ${formatKesPlain(r.oldPrice)} → '
                '${formatKesPlain(r.newPrice)}',
                key: ValueKey('priceRequest.change.$id'),
                style: t.moneyLarge.copyWith(color: c.marine),
              ),
            ],
          ),
          const SizedBox(height: Space.x8),
          Text(
            r.reason == null ? 'Asked $when' : '“${r.reason}” · $when',
            key: ValueKey('priceRequest.reason.$id'),
            style: t.small.copyWith(color: c.inkSoft),
          ),
          if (staleMessage case final stale?) ...[
            const SizedBox(height: Space.x12),
            Note.warning(stale, key: ValueKey('priceRequest.stale.$id')),
          ],
          const SizedBox(height: Space.x16),
          Row(
            children: [
              Expanded(
                child: AppButton.primary(
                  key: ValueKey('priceRequest.approve.$id'),
                  label: 'Approve',
                  busy: busy,
                  onPressed: staleMessage != null || locked ? null : onApprove,
                ),
              ),
              const SizedBox(width: Space.x10),
              Expanded(
                child: AppButton.destructive(
                  key: ValueKey('priceRequest.reject.$id'),
                  label: 'Reject',
                  onPressed: locked ? null : onReject,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Reject this price change?" (like Figma "03b Reject reason"): a required
/// reason the supervisor sees. Pops the reason, or null on Cancel.
class RejectPriceDialog extends StatefulWidget {
  const RejectPriceDialog({
    super.key,
    required this.categoryName,
    required this.oldPrice,
    required this.newPrice,
    required this.requestedByFirstName,
  });

  final String categoryName;
  final int oldPrice;
  final int newPrice;
  final String requestedByFirstName;

  @override
  State<RejectPriceDialog> createState() => _RejectPriceDialogState();
}

class _RejectPriceDialogState extends State<RejectPriceDialog> {
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
      setState(() => _error = 'Give a reason for rejecting the price change.');
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    final v = widget;
    return AlertDialog(
      key: const ValueKey('priceReject.dialog'),
      title: Text('Reject this price change?', style: t.sectionTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${v.categoryName} · KES ${formatKesPlain(v.oldPrice)} '
              '→ ${formatKesPlain(v.newPrice)}. '
              '${v.requestedByFirstName} will see your reason.',
              style: t.small,
            ),
            const SizedBox(height: Space.x12),
            LabeledField(
              label: 'Reason',
              controller: _reason,
              fieldKey: const ValueKey('priceReject.reason'),
              errorText: _error,
              autofocus: true,
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        AppButton.secondary(
          key: const ValueKey('priceReject.cancel'),
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton.destructive(
          key: const ValueKey('priceReject.reject'),
          label: 'Reject request',
          onPressed: _submit,
        ),
      ],
    );
  }
}
