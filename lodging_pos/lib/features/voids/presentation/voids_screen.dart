import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/theme.dart';
import '../../../app/widgets/buttons.dart';
import '../../../app/widgets/labeled_field.dart';
import '../../../app/widgets/notes.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/clock/nairobi.dart';
import '../../../core/contacts/phone.dart';
import '../../../core/money/kes.dart';
import '../../receipts/data/receipts_repository.dart';
import '../../receipts/presentation/receipt_view.dart';
import '../../receipts/presentation/receipts_providers.dart';
import '../data/voids_repository.dart';
import '../domain/void_rules.dart';
import 'voids_providers.dart';

/// AD-7 "Voids": find a payment's receipt (by number or the guest's phone,
/// as in Receipts) and void the payment or the stay it paid for. The
/// record stays, marked VOID, and leaves every total. Owner and supervisor
/// only (`voidRecords`); nobody voids their own record.
class VoidsScreen extends ConsumerStatefulWidget {
  const VoidsScreen({super.key});

  @override
  ConsumerState<VoidsScreen> createState() => _VoidsScreenState();
}

class _VoidsScreenState extends ConsumerState<VoidsScreen> {
  final _search = TextEditingController();
  String? _selected;

  static const _listWidth = 320.0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final list = ref.watch(receiptListProvider(_search.text));
    final selected = _selected;

    final Widget items = switch (list) {
      AsyncError(:final error) => Note.error(
        '$error',
        title: 'Receipts could not be loaded.',
      ),
      AsyncData(:final value) => () {
        // Payments only: refund payouts aren't voided here.
        final receipts = [
          for (final r in value)
            if (!r.isRefund) r,
        ];
        if (receipts.isEmpty) {
          return Text(
            'No receipt matches. Search by receipt number or phone.',
            key: const ValueKey('voids.none'),
            style: t.secondary,
          );
        }
        return ListView.builder(
          key: const ValueKey('voids.list'),
          itemCount: receipts.length,
          itemBuilder: (context, i) => _Tile(
            receipts[i],
            selected: receipts[i].paymentId == selected,
            onTap: () => setState(() => _selected = receipts[i].paymentId),
          ),
        );
      }(),
      _ => const SizedBox.shrink(),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text('Voids', style: t.pageTitle)),
        Text(
          'Correct a wrong payment or stay. The record stays, marked VOID, '
          'and leaves every total. A void moves no money.',
          style: t.secondary.copyWith(color: c.muted),
        ),
        const SizedBox(height: Space.x16),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _listWidth,
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(Space.x20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LabeledField(
                          label: 'Find by receipt number or phone',
                          controller: _search,
                          fieldKey: const ValueKey('voids.search'),
                          hintText: 'R-000041 or 0722 418 905',
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: Space.x12),
                        Expanded(child: items),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Space.x24),
              Expanded(
                child: selected == null
                    ? const Align(
                        alignment: Alignment.topLeft,
                        child: Note.info(
                          'Choose a receipt to void its payment or its stay.',
                        ),
                      )
                    : SingleChildScrollView(
                        child: _VoidPanel(
                          key: ValueKey('voids.panel.$selected'),
                          paymentId: selected,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.receipt, {required this.selected, required this.onTap});

  final ReceiptSummary receipt;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final r = receipt;
    return Material(
      color: selected ? c.marineTint : c.white,
      borderRadius: BorderRadius.circular(Radii.control),
      child: InkWell(
        key: ValueKey('voids.item.${r.receiptNumber}'),
        borderRadius: BorderRadius.circular(Radii.control),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.x12,
            vertical: Space.x10,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(r.receiptNumber, style: t.moneySmall)),
                  if (r.isVoid) ...[
                    const StatusBadge('VOID', tone: BadgeTone.danger),
                    const SizedBox(width: Space.x8),
                  ],
                  Text(formatKes(r.total), style: t.moneySmall),
                ],
              ),
              Text(
                '${r.guestName} · ${maskPhone(r.guestPhone)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.secondary.copyWith(color: c.inkSoft),
              ),
              Text(
                '${r.roomAndBed} · ${formatDayDateTime(r.receivedAt)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.secondary.copyWith(color: c.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The receipt beside its two voids: this payment, or the stay it paid
/// for (with every payment behind it).
class _VoidPanel extends ConsumerWidget {
  const _VoidPanel({super.key, required this.paymentId});

  final String paymentId;

  static const _actionsWidth = 300.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipt = ref.watch(receiptProvider(paymentId));
    final view = ref.watch(voidViewProvider(paymentId));
    final user = ref.watch(sessionProvider);
    final Widget shown = switch (receipt) {
      AsyncData(:final value) => ReceiptView(value),
      AsyncError(:final error) => Note.error(
        '$error',
        title: 'The receipt could not be loaded.',
      ),
      _ => const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      ),
    };
    final Widget actions = switch (view) {
      AsyncData(:final value) when user != null => _Actions(
        view: value,
        canVoid: can(user, Permission.voidRecords),
        blockerFor: (plan) => voidBlocker(plan, user),
      ),
      AsyncError(:final error) => Note.error('$error'),
      _ => const SizedBox.shrink(),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: ReceiptPanel.receiptWidth,
            ),
            child: shown,
          ),
        ),
        const SizedBox(width: Space.x24),
        SizedBox(width: _actionsWidth, child: actions),
      ],
    );
  }
}

class _Actions extends ConsumerWidget {
  const _Actions({
    required this.view,
    required this.canVoid,
    required this.blockerFor,
  });

  final VoidView view;
  final bool canVoid;
  final String? Function(VoidPlan) blockerFor;

  Future<void> _void(BuildContext context, WidgetRef ref, VoidPlan plan) async {
    final user = ref.read(sessionProvider);
    if (user == null) return;
    final repo = ref.read(voidsRepositoryProvider);
    await showDialog<void>(
      context: context,
      builder: (_) => _ConfirmVoid(
        plan: plan,
        save: (reason) => plan.target == VoidTarget.payment
            ? repo.voidPayment(user, plan.targetId, reason)
            : repo.voidStay(user, plan.targetId, reason),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);

    Widget record(String what, VoidRecord r, String key) => Note.warning(
      'By ${r.voidedBy}, ${formatDayDateComma(r.voidedAt)}: ${r.reason}',
      key: ValueKey(key),
      title: '$what voided',
    );

    Widget section(
      String title,
      String help,
      VoidPlan plan,
      String button,
      String key,
    ) {
      final blocker = blockerFor(plan);
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(Space.x16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: t.sectionTitle),
              const SizedBox(height: Space.x4),
              Text(help, style: t.secondary.copyWith(color: c.inkSoft)),
              const SizedBox(height: Space.x12),
              if (blocker != null)
                Note.info(blocker, key: ValueKey('$key.blocked'))
              else
                AppButton.destructive(
                  key: ValueKey(key),
                  label: button,
                  onPressed: () => _void(context, ref, plan),
                ),
            ],
          ),
        ),
      );
    }

    if (!canVoid) return const Note.info('You can’t void records.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (view.stayVoid case final r?) ...[
          record('Stay', r, 'voids.stayVoided'),
          const SizedBox(height: Space.x12),
        ] else if (view.paymentVoid case final r?) ...[
          record('Payment', r, 'voids.paymentVoided'),
          const SizedBox(height: Space.x12),
        ],
        section(
          'This payment',
          'Money that was never taken: it leaves the shift and the owner’s '
              'figures. The guest stays in the bed.',
          view.paymentPlan,
          'Void payment…',
          'voids.payment',
        ),
        const SizedBox(height: Space.x12),
        section(
          'The whole stay',
          'A wrong guest, bed or method: the stay and every payment behind '
              'it. The bed becomes available and needs cleaning.',
          view.stayPlan,
          'Void stay…',
          'voids.stay',
        ),
      ],
    );
  }
}

/// What the void writes, in words, and the reason (required).
class _ConfirmVoid extends StatefulWidget {
  const _ConfirmVoid({required this.plan, required this.save});

  final VoidPlan plan;
  final Future<void> Function(String reason) save;

  @override
  State<_ConfirmVoid> createState() => _ConfirmVoidState();
}

class _ConfirmVoidState extends State<_ConfirmVoid> {
  final _reason = TextEditingController();
  String? _error;
  String? _problem;
  var _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final error = voidReasonError(_reason.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _problem = null;
    });
    try {
      await widget.save(_reason.text);
      if (mounted) Navigator.of(context).pop();
    } on VoidRuleViolation catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } on NotPermitted {
      if (mounted) setState(() => _problem = 'You can’t void records.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    final payment = widget.plan.target == VoidTarget.payment;
    return AlertDialog(
      key: const ValueKey('voids.confirm'),
      title: Text(
        payment ? 'Void this payment?' : 'Void this stay?',
        style: t.sectionTitle,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.plan.summary,
              key: const ValueKey('voids.summary'),
              style: t.body,
            ),
            const SizedBox(height: Space.x8),
            Text(
              'It can’t be undone. The owner sees it with your reason.',
              style: t.secondary,
            ),
            const SizedBox(height: Space.x12),
            LabeledField(
              label: 'Reason',
              controller: _reason,
              fieldKey: const ValueKey('voids.reason'),
              errorText: _error,
              autofocus: true,
              onSubmitted: (_) => _submit(),
            ),
            if (_problem != null) ...[
              const SizedBox(height: Space.x12),
              Note.error(_problem!, key: const ValueKey('voids.problem')),
            ],
          ],
        ),
      ),
      actions: [
        AppButton.secondary(
          key: const ValueKey('voids.cancel'),
          label: 'Cancel',
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
        AppButton.destructive(
          key: const ValueKey('voids.confirm.ok'),
          label: payment ? 'Void payment' : 'Void stay',
          busy: _busy,
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }
}
