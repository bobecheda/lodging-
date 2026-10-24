import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/gate.dart';
import '../../../app/theme/theme.dart';
import '../../../app/widgets/notes.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/contacts/phone.dart';
import '../../sync/presentation/owner_cloud_prompt.dart';
import '../data/refunds_repository.dart';
import '../domain/refund.dart';
import 'refund_detail_body.dart';
import 'refunds_providers.dart';

/// The owner's decision on one refund (AD-7), as the Figma "03 Refund
/// request": the guest, the stay and its receipts, the calculated amount
/// (unchangeable), who asked, then Approve or Reject (with a reason the desk
/// sees). On the desk for now; the phone uses the same layout.
class RefundDetailScreen extends ConsumerStatefulWidget {
  const RefundDetailScreen({super.key, required this.refundId});

  final String refundId;

  static const width = 560.0;

  @override
  ConsumerState<RefundDetailScreen> createState() => _RefundDetailState();
}

class _RefundDetailState extends ConsumerState<RefundDetailScreen> {
  String? _problem;
  var _busy = false;

  Future<void> _decide(RefundDetail d, {required bool approve}) async {
    final user = ref.read(sessionProvider);
    if (user == null) return;
    if (!await ensureOwnerCloud(context, ref) || !mounted) return;
    String? note;
    if (!approve) {
      note = await showDialog<String>(
        context: context,
        builder: (_) => RejectRefundDialog(
          guestName: d.view.guestName,
          amount: d.view.refund.amount,
        ),
      );
      if (note == null || !mounted) return;
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await withOwnerCloud(
        context,
        ref,
        () => ref
            .read(refundsRepositoryProvider)
            .decide(user, widget.refundId, approve: approve, note: note),
      );
    } on RefundRuleViolation catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } on NotPermitted {
      if (mounted) setState(() => _problem = 'Only the owner decides refunds.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    final user = ref.watch(sessionProvider);
    final detail = ref.watch(refundDetailProvider(widget.refundId));
    final Widget body = switch (detail) {
      AsyncData(:final value) => RefundDetailBody(
        detail: value,
        maskedPhone: maskPhone(value.view.guestPhone),
        canDecide: user != null && can(user, Permission.approveRefund),
        busy: _busy,
        problem: _problem,
        onApprove: () => _decide(value, approve: true),
        onReject: () => _decide(value, approve: false),
      ),
      AsyncError(:final error) => Note.error(
        '$error',
        title: 'The refund could not be loaded.',
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const ValueKey('refund.back'),
            onPressed: () => context.go(Routes.today),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: Text('Today', style: t.bodyStrong),
          ),
        ),
        const SizedBox(height: Space.x8),
        Expanded(
          child: SingleChildScrollView(
            child: Center(
              child: SizedBox(width: RefundDetailScreen.width, child: body),
            ),
          ),
        ),
      ],
    );
  }
}
