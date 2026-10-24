import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/theme.dart';
import '../../../app/widgets/notes.dart';
import '../../../core/auth/permissions.dart';
import '../../refunds/domain/refund.dart';
import '../../refunds/presentation/refund_detail_body.dart';
import '../data/owner_cloud.dart';
import '../data/owner_refunds_repository.dart';
import 'owner_app.dart';
import 'owner_providers.dart';

/// "Refund request" on the phone (AD-7): the desk's layout, deciding in the
/// cloud at once. Offline it is refused.
class OwnerRefundScreen extends ConsumerStatefulWidget {
  const OwnerRefundScreen({super.key, required this.refundId});

  final String refundId;

  @override
  ConsumerState<OwnerRefundScreen> createState() => _OwnerRefundState();
}

class _OwnerRefundState extends ConsumerState<OwnerRefundScreen> {
  String? _problem;
  var _busy = false;

  Future<void> _decide(OwnerRefund r, {required bool approve}) async {
    final signedIn = ref.read(ownerSessionProvider).value;
    if (signedIn == null) return;
    String? note;
    if (!approve) {
      note = await showDialog<String>(
        context: context,
        builder: (_) => RejectRefundDialog(
          guestName: r.detail.view.guestName,
          amount: r.detail.view.refund.amount,
        ),
      );
      if (note == null || !mounted) return;
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await ref
          .read(ownerRefundsRepositoryProvider)
          .decide(
            ownerAccount(signedIn),
            widget.refundId,
            approve: approve,
            note: note,
          );
      ref.invalidate(ownerRefundProvider(widget.refundId));
      await ref.read(ownerTodayDataProvider.notifier).refresh();
    } on RefundRuleViolation catch (e) {
      if (mounted) setState(() => _problem = e.message);
      ref.invalidate(ownerRefundProvider(widget.refundId));
    } on OwnerCloudOffline {
      if (mounted) {
        setState(
          () => _problem = approve
              ? 'Approving needs an internet connection.'
              : 'Rejecting needs an internet connection.',
        );
      }
    } on OwnerCloudRefused catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } on OwnerSignInRefused {
      ref.read(ownerSessionProvider.notifier).ended();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    final signedIn = ref.watch(ownerSessionProvider).value;
    final refund = ref.watch(ownerRefundProvider(widget.refundId));
    final Widget body = switch (refund) {
      AsyncData(:final value) => RefundDetailBody(
        detail: value.detail,
        maskedPhone: value.maskedPhone,
        canDecide:
            signedIn != null &&
            can(ownerAccount(signedIn), Permission.approveRefund),
        busy: _busy,
        problem: _problem,
        onApprove: () => _decide(value, approve: true),
        onReject: () => _decide(value, approve: false),
      ),
      AsyncError(:final error) => Note.error(
        error is OwnerCloudOffline
            ? 'No internet connection. Try again once the phone is online.'
            : '$error',
        title: 'The refund could not be loaded.',
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.x8, Space.x8, Space.x16, 0),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('refund.back'),
              onPressed: () => context.go(OwnerRoutes.today),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: Text('Today', style: t.bodyStrong),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              Space.x16,
              Space.x8,
              Space.x16,
              Space.x16,
            ),
            child: body,
          ),
        ),
      ],
    );
  }
}
