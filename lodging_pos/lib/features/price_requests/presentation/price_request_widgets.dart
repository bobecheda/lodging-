import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/theme.dart';
import '../../../app/widgets/buttons.dart';
import '../../../app/widgets/labeled_field.dart';
import '../../../app/widgets/money_input.dart';
import '../../../app/widgets/notes.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/clock/clock.dart';
import '../../../core/clock/nairobi.dart';
import '../../../core/money/kes.dart';
import '../../setup/data/prices_repository.dart';
import '../../setup/domain/prices_settings.dart';
import '../../setup/presentation/prices_providers.dart';
import '../data/price_requests_repository.dart';
import '../domain/price_request.dart';
import 'price_requests_providers.dart';

// ── The supervisor ───────────────────────────────────────────────────────

/// "Deluxe · ask for a new price" (Figma "06b Edit price", as a request):
/// the new price, a live "700 → 750 (+50 a night)" line and an optional
/// reason. Sends the request itself; pops true once sent.
class RequestPriceDialog extends ConsumerStatefulWidget {
  const RequestPriceDialog({super.key, required this.usage});

  final CategoryUsage usage;

  @override
  ConsumerState<RequestPriceDialog> createState() => _RequestPriceDialogState();
}

class _RequestPriceDialogState extends ConsumerState<RequestPriceDialog> {
  final _price = TextEditingController();
  final _reason = TextEditingController();
  String? _priceError;
  String? _reasonError;
  String? _problem;
  var _busy = false;

  @override
  void dispose() {
    _price.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final category = widget.usage.category;
    final price = parseKes(_price.text);
    setState(() {
      _priceError = requestedPriceError(
        price,
        currentPrice: category.pricePerNight,
      );
      _reasonError = requestReasonError(_reason.text);
      _problem = null;
    });
    if (_priceError != null || _reasonError != null) return;
    final user = ref.read(sessionProvider);
    if (user == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(priceRequestsRepositoryProvider)
          .request(
            user,
            categoryId: category.id,
            newPrice: price,
            reason: _reason.text,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on InvalidRequestedPrice catch (e) {
      if (mounted) setState(() => _priceError = e.message);
    } on PriceRequestRuleViolation catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } on NotPermitted {
      if (mounted) {
        setState(() => _problem = 'Only the supervisor asks for prices.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final category = widget.usage.category;
    final beds = widget.usage.activeBeds;
    final price = parseKes(_price.text);
    final preview = price != null && priceError(price) == null
        ? '${category.name}: ${formatKesPlain(category.pricePerNight)} → '
              '${formatKesPlain(price)} '
              '(${formatPriceChange(price - category.pricePerNight)} a night). '
              'Applies to new check-ins only, once the owner approves.'
        : 'Applies to new check-ins only, once the owner approves.';
    return AlertDialog(
      key: const ValueKey('priceRequest.dialog'),
      title: Text(
        '${category.name} · ask for a new price',
        style: t.sectionTitle,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Now ${formatKes(category.pricePerNight)} · $beds '
                '${beds == 1 ? 'bed' : 'beds'}',
                style: t.small.copyWith(color: c.muted),
              ),
              const SizedBox(height: Space.x16),
              MoneyInput(
                label: 'New price',
                controller: _price,
                fieldKey: const ValueKey('priceRequest.price'),
                errorText: _priceError,
                autofocus: true,
                onChanged: (_) => setState(() => _priceError = null),
                onSubmitted: (_) => _send(),
              ),
              const SizedBox(height: Space.x8),
              Text(
                preview,
                key: const ValueKey('priceRequest.preview'),
                style: t.small.copyWith(color: c.inkSoft),
              ),
              const SizedBox(height: Space.x16),
              LabeledField(
                label: 'Reason (optional)',
                controller: _reason,
                fieldKey: const ValueKey('priceRequest.reason'),
                errorText: _reasonError,
                helperText:
                    'The owner sees it. Up to $reasonMaxLength '
                    'characters.',
                onSubmitted: (_) => _send(),
              ),
              if (_problem != null) ...[
                const SizedBox(height: Space.x12),
                Note.error(
                  _problem!,
                  key: const ValueKey('priceRequest.problem'),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        AppButton.secondary(
          key: const ValueKey('priceRequest.cancel'),
          label: 'Cancel',
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        ),
        AppButton.primary(
          key: const ValueKey('priceRequest.send'),
          label: 'Send request',
          busy: _busy,
          onPressed: _send,
        ),
      ],
    );
  }
}

/// Opens [RequestPriceDialog] for [usage]'s category.
Future<void> showRequestPriceDialog(
  BuildContext context,
  CategoryUsage usage,
) => showDialog<bool>(
  context: context,
  builder: (_) => RequestPriceDialog(usage: usage),
);

/// The supervisor's "Price requests" card: what's waiting for the owner
/// (their own can be withdrawn), and the owner's answers and requests
/// ended by closing a category, for 14 days.
class SupervisorPriceRequestsCard extends ConsumerStatefulWidget {
  const SupervisorPriceRequestsCard({super.key});

  @override
  ConsumerState<SupervisorPriceRequestsCard> createState() =>
      _SupervisorPriceRequestsCardState();
}

class _SupervisorPriceRequestsCardState
    extends ConsumerState<SupervisorPriceRequestsCard> {
  String? _busyId;
  String? _problem;

  Future<void> _withdraw(String id) async {
    final user = ref.read(sessionProvider);
    if (user == null) return;
    setState(() {
      _busyId = id;
      _problem = null;
    });
    try {
      await ref.read(priceRequestsRepositoryProvider).withdraw(user, id);
    } on PriceRequestRuleViolation catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } on NotPermitted {
      if (mounted) {
        setState(
          () => _problem = 'Only the supervisor who asked can withdraw it.',
        );
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final user = ref.watch(sessionProvider);
    final now = ref.watch(clockProvider).now();
    final requests = ref.watch(supervisorPriceRequestsProvider);
    final Widget body = switch (requests) {
      AsyncData(:final value)
          when value.waiting.isEmpty && value.recent.isEmpty =>
        Text(
          'No price requests in the last 14 days. Use “Request a change” '
          'beside a category to ask the owner.',
          key: const ValueKey('priceRequests.empty'),
          style: t.small.copyWith(color: c.muted),
        ),
      AsyncData(:final value) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final v in [...value.waiting, ...value.recent])
            _SupervisorRow(
              v,
              now: now,
              busy: _busyId == v.id,
              onWithdraw:
                  v.request.requestedBy == user?.id &&
                      v.status == PriceRequestStatus.waiting
                  ? () => _withdraw(v.id)
                  : null,
            ),
        ],
      ),
      AsyncError(:final error) => Note.error(
        '$error',
        title: 'Price requests could not be loaded.',
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
    return Card(
      key: const ValueKey('priceRequests'),
      child: Padding(
        padding: const EdgeInsets.all(Space.x24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text('Price requests', style: t.sectionTitle),
            ),
            const SizedBox(height: Space.x4),
            Text(
              'The owner approves or rejects each one. Answers stay here for '
              '14 days.',
              style: t.small.copyWith(color: c.muted),
            ),
            const SizedBox(height: Space.x12),
            body,
            if (_problem != null) ...[
              const SizedBox(height: Space.x12),
              Note.error(
                _problem!,
                key: const ValueKey('priceRequests.problem'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SupervisorRow extends StatelessWidget {
  const _SupervisorRow(
    this.view, {
    required this.now,
    required this.busy,
    required this.onWithdraw,
  });

  final PriceRequestView view;
  final DateTime now;
  final bool busy;
  final VoidCallback? onWithdraw;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final r = view.request;
    final id = view.id;
    final (badge, tone, detail) = switch (view.status) {
      PriceRequestStatus.waiting => (
        'WAITING FOR OWNER APPROVAL',
        BadgeTone.warning,
        'Asked by ${view.requestedByFirstName} · '
            '${formatWhen(r.requestedAt, now: now)}',
      ),
      PriceRequestStatus.approved => (
        'APPROVED',
        BadgeTone.active,
        'Approved by ${view.decidedByName} · '
            '${formatWhen(r.decision!.decidedAt, now: now)}',
      ),
      PriceRequestStatus.rejected => (
        'REJECTED',
        BadgeTone.disabled,
        'Rejected by ${view.decidedByName} · '
            '${formatWhen(r.decision!.decidedAt, now: now)}',
      ),
      PriceRequestStatus.withdrawn => (
        'WITHDRAWN',
        BadgeTone.disabled,
        'Withdrawn · category closed · '
            '${formatWhen(r.withdrawal!.at, now: now)}',
      ),
    };
    return Container(
      key: ValueKey('priceRequests.row.$id'),
      padding: const EdgeInsets.symmetric(vertical: Space.x12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.lineSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${view.categoryName}  ',
                        style: t.bodyStrong,
                      ),
                      TextSpan(
                        text:
                            'KES ${formatKesPlain(r.oldPrice)} → '
                            '${formatKesPlain(r.newPrice)}',
                        style: t.monoStrong,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: Space.x8),
              StatusBadge(
                badge,
                key: ValueKey('priceRequests.status.$id'),
                tone: tone,
              ),
            ],
          ),
          const SizedBox(height: Space.x4),
          Text(
            detail,
            key: ValueKey('priceRequests.detail.$id'),
            style: t.small.copyWith(color: c.muted),
          ),
          if (view.status == PriceRequestStatus.rejected)
            Padding(
              padding: const EdgeInsets.only(top: Space.x4),
              child: Text(
                '“${r.decision!.note}”',
                key: ValueKey('priceRequests.reason.$id'),
                style: t.small.copyWith(color: c.inkSoft),
              ),
            ),
          if (view.stale) ...[
            const SizedBox(height: Space.x8),
            Note.warning(
              'The owner has since changed ${view.categoryName} to '
              '${formatKes(view.currentPrice)}. Withdraw this and ask again '
              'if it’s still needed.',
              key: ValueKey('priceRequests.stale.$id'),
            ),
          ],
          if (onWithdraw != null) ...[
            const SizedBox(height: Space.x4),
            TextButton(
              key: ValueKey('priceRequests.withdraw.$id'),
              onPressed: busy ? null : onWithdraw,
              style: TextButton.styleFrom(
                foregroundColor: c.redText,
                padding: EdgeInsets.zero,
              ),
              child: const Text('Withdraw request'),
            ),
          ],
        ],
      ),
    );
  }
}

// ── The owner ────────────────────────────────────────────────────────────

/// The owner's price requests on Prices (Figma "06 Prices"): a marine-tint
/// card for each waiting request with Approve / Reject. Approving changes
/// the price at once; a request the price has moved on from can only be
/// rejected.
class OwnerPriceRequests extends ConsumerStatefulWidget {
  const OwnerPriceRequests({super.key});

  @override
  ConsumerState<OwnerPriceRequests> createState() => _OwnerPriceRequestsState();
}

class _OwnerPriceRequestsState extends ConsumerState<OwnerPriceRequests> {
  String? _busyId;
  String? _problem;
  String? _done;

  Future<void> _decide(PriceRequestView v, {required bool approve}) async {
    final user = ref.read(sessionProvider);
    if (user == null) return;
    String? note;
    if (!approve) {
      note = await showDialog<String>(
        context: context,
        builder: (_) => RejectPriceDialog(view: v),
      );
      if (note == null || !mounted) return;
    }
    setState(() {
      _busyId = v.id;
      _problem = null;
      _done = null;
    });
    try {
      await ref
          .read(priceRequestsRepositoryProvider)
          .decide(user, v.id, approve: approve, note: note);
      ref.invalidate(categoryUsageProvider);
      if (mounted) {
        setState(
          () => _done = approve
              ? '${v.categoryName} is now ${formatKes(v.request.newPrice)} '
                    'for new check-ins.'
              : 'Request rejected. ${v.requestedByFirstName} will see your '
                    'reason.',
        );
      }
    } on StalePriceRequest catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } on PriceRequestRuleViolation catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } on NotPermitted {
      if (mounted) {
        setState(() => _problem = 'Only the owner decides price changes.');
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider).now();
    final waiting = ref.watch(waitingPriceRequestsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_done != null) ...[
          Note.info(_done!, key: const ValueKey('priceRequest.done')),
          const SizedBox(height: Space.x16),
        ],
        if (_problem != null) ...[
          Note.error(_problem!, key: const ValueKey('priceRequest.problem')),
          const SizedBox(height: Space.x16),
        ],
        switch (waiting) {
          AsyncData(:final value) when value.isEmpty => const Note.info(
            'No price requests waiting. When the supervisor asks for a '
            'change, it shows here and on Today.',
            key: ValueKey('priceRequest.none'),
          ),
          AsyncData(:final value) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, v) in value.indexed) ...[
                if (i > 0) const SizedBox(height: Space.x16),
                _RequestCard(
                  v,
                  now: now,
                  busy: _busyId == v.id,
                  locked: _busyId != null,
                  onApprove: () => _decide(v, approve: true),
                  onReject: () => _decide(v, approve: false),
                ),
              ],
            ],
          ),
          AsyncError(:final error) => Note.error(
            '$error',
            title: 'Price requests could not be loaded.',
          ),
          _ => const SizedBox.shrink(),
        },
      ],
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard(
    this.view, {
    required this.now,
    required this.busy,
    required this.locked,
    required this.onApprove,
    required this.onReject,
  });

  final PriceRequestView view;
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
    final r = view.request;
    final id = view.id;
    final role = view.requestedByRole?.name.toUpperCase();
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
            'REQUEST FROM ${view.requestedByFirstName.toUpperCase()}'
            '${role == null ? '' : ' ($role)'}',
            style: t.cardHeading.copyWith(color: c.marine),
          ),
          const SizedBox(height: Space.x10),
          Wrap(
            spacing: Space.x10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(view.categoryName, style: t.sectionTitle),
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
          if (view.stale) ...[
            const SizedBox(height: Space.x12),
            Note.warning(
              '${view.categoryName} is now ${formatKes(view.currentPrice)}, '
              'not ${formatKesPlain(r.oldPrice)}. Reject this request or ask '
              'for a new one.',
              key: ValueKey('priceRequest.stale.$id'),
            ),
          ],
          const SizedBox(height: Space.x16),
          Row(
            children: [
              Expanded(
                child: AppButton.primary(
                  key: ValueKey('priceRequest.approve.$id'),
                  label: 'Approve',
                  busy: busy,
                  onPressed: view.stale || locked ? null : onApprove,
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
  const RejectPriceDialog({super.key, required this.view});

  final PriceRequestView view;

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
    final v = widget.view;
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
              '${v.categoryName} · KES ${formatKesPlain(v.request.oldPrice)} '
              '→ ${formatKesPlain(v.request.newPrice)}. '
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
