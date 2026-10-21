import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/gate.dart';
import '../../../app/theme/theme.dart';
import '../../../app/widgets/buttons.dart';
import '../../../app/widgets/gate_top_bar.dart';
import '../../../app/widgets/money_input.dart';
import '../../../app/widgets/notes.dart';
import '../../../core/auth/session.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/clock/clock.dart';
import '../../../core/clock/nairobi.dart';
import '../../../core/money/kes.dart';
import '../../payments/domain/payment_rules.dart';
import '../data/shift_repository.dart';
import '../domain/shift.dart';
import '../domain/shift_close.dart';
import '../domain/shift_rules.dart';
import 'shift_providers.dart';

/// Before working, a receptionist opens a shift (counting the float),
/// continues their own open shift, or is told whose shift is blocking the
/// device (artboard "Open or resume shift").
class OpenShiftScreen extends ConsumerWidget {
  const OpenShiftScreen({super.key, this.returnTo});

  /// Where a user who works without a shift (a supervisor) came from, e.g.
  /// check-in. They come back there once the shift is open, or on "Back".
  final String? returnTo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    final open = ref.watch(currentShiftProvider).value;
    final start = user == null
        ? null
        : shiftStartFor(
            openShift: open,
            user: user,
            resumeConfirmed: ref.watch(shiftContinuedProvider),
          );

    void back() => context.go(returnTo ?? Routes.home);

    return Scaffold(
      appBar: const GateTopBar(),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.x32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.x32),
                child: switch (start) {
                  ShiftBlocked(:final openShift) => _Blocked(openShift),
                  ResumeShift(:final shift) => _Resume(user!, shift),
                  // A supervisor came here by choice: they can go back, and
                  // someone else's open shift blocks them too.
                  ShiftReady() when open != null && open.userId != user!.id =>
                    _Blocked(open, onBack: back),
                  ShiftReady() => _OpenNew(user!, onBack: back),
                  _ when user != null => _OpenNew(user),
                  _ => const SizedBox.shrink(),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Date line + greeting at the top of the card.
class _Heading extends ConsumerWidget {
  const _Heading(this.title);

  /// Null for the default greeting.
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LodgingType.of(context);
    final now = ref.watch(clockProvider).now();
    final user = ref.watch(sessionProvider);
    final firstName = user?.fullName.split(' ').first ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(formatDayDateTime(now), style: t.smallStrong),
        const SizedBox(height: Space.x8),
        Semantics(
          header: true,
          child: Text(
            title ?? '${greetingFor(now)}, $firstName',
            style: t.cardTitle,
          ),
        ),
        const SizedBox(height: Space.x8),
      ],
    );
  }
}

class _OpenNew extends ConsumerStatefulWidget {
  const _OpenNew(this.user, {this.onBack});

  final UserAccount user;

  /// "Back", for a user who may work without a shift.
  final VoidCallback? onBack;

  @override
  ConsumerState<_OpenNew> createState() => _OpenNewState();
}

class _OpenNewState extends ConsumerState<_OpenNew> {
  final _float = TextEditingController();
  String? _error;
  var _busy = false;

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = parseKes(_float.text);
    final problem = openingFloatError(amount);
    setState(() => _error = problem);
    if (problem != null) return;

    setState(() => _busy = true);
    try {
      await ref.read(currentShiftProvider.notifier).open(widget.user, amount!);
    } on ShiftAlreadyOpen {
      // Someone opened one meanwhile; reload so the router re-decides.
      ref.invalidate(currentShiftProvider);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open the shift: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Heading(null),
        Text(
          'Count the cash in the drawer, then open your shift. Check-ins and '
          'payments start once it is open.',
          style: t.body.copyWith(color: c.muted),
        ),
        const SizedBox(height: Space.x24),
        MoneyInput(
          label: 'Opening cash float',
          controller: _float,
          fieldKey: const ValueKey('shift.float'),
          large: true,
          autofocus: true,
          errorText: _error,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: Space.x20),
        AppButton.primary(
          key: const ValueKey('shift.submit'),
          label: 'Open shift',
          large: true,
          busy: _busy,
          onPressed: _submit,
        ),
        if (widget.onBack != null) ...[
          const SizedBox(height: Space.x12),
          AppButton.secondary(
            key: const ValueKey('shift.back'),
            label: 'Back',
            onPressed: widget.onBack,
          ),
        ],
      ],
    );
  }
}

class _Resume extends ConsumerWidget {
  const _Resume(this.user, this.shift);

  final UserAccount user;
  final OpenShift shift;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final takings = ref.watch(shiftTakingsProvider(shift.id)).value;

    Widget row(String label, int amount, {bool strong = false, Key? key}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.x6),
          child: Row(
            children: [
              Expanded(
                child: Text(label, style: strong ? t.bodyStrong : t.body),
              ),
              Text(
                formatKes(amount),
                key: key,
                style: strong ? t.moneyLarge : t.monoStrong,
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Heading('Welcome back, ${user.fullName.split(' ').first}'),
        Text(
          'Your shift has been open since ${formatDayDateTime(shift.openedAt)}.',
          style: t.body.copyWith(color: c.muted),
        ),
        const SizedBox(height: Space.x20),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.x16,
            vertical: Space.x10,
          ),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(Radii.control),
            border: Border.all(color: c.line),
          ),
          child: takings == null
              ? const Padding(
                  padding: EdgeInsets.all(Space.x12),
                  child: Center(child: CircularProgressIndicator()),
                )
              : Column(
                  children: [
                    row(
                      'Taken so far (net)',
                      takings.net,
                      strong: true,
                      key: const ValueKey('shift.takenTotal'),
                    ),
                    Divider(color: c.lineSoft),
                    _TakingsTable(takings),
                    Divider(color: c.lineSoft),
                    row('Opening float', shift.openingFloat),
                  ],
                ),
        ),
        const SizedBox(height: Space.x8),
        Text(
          'Refunds count once paid out. Voided payments and refunds are not '
          'counted.',
          style: t.small,
        ),
        const SizedBox(height: Space.x20),
        AppButton.primary(
          key: const ValueKey('shift.continue'),
          label: 'Continue my shift',
          large: true,
          onPressed: () => ref.read(shiftContinuedProvider.notifier).confirm(),
        ),
      ],
    );
  }
}

/// Received, refunded and net for each method, so refunds stay visible
/// rather than just making the total smaller.
class _TakingsTable extends StatelessWidget {
  const _TakingsTable(this.takings);

  final ShiftTakings takings;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);

    Widget cell(String text, {TextStyle? style, Key? key}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x6),
      child: Text(text, key: key, textAlign: TextAlign.end, style: style),
    );
    Widget head(String text) =>
        cell(text, style: t.small.copyWith(color: c.muted));
    TableRow line(PaymentMethod method, MethodTakings m) => TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.x6),
          child: Text(method.label, style: t.body),
        ),
        cell(formatKes(m.received), style: t.mono),
        cell(
          m.refunded == 0 ? formatKes(0) : formatKes(-m.refunded),
          style: t.mono.copyWith(color: m.refunded == 0 ? c.muted : null),
        ),
        cell(
          formatKes(m.net),
          style: t.monoStrong,
          key: ValueKey('shift.net.${method.code}'),
        ),
      ],
    );

    return Table(
      columnWidths: const {0: FlexColumnWidth(1.1)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            const SizedBox.shrink(),
            head('Received'),
            head('Refunded'),
            head('Net'),
          ],
        ),
        line(PaymentMethod.cash, takings.cash),
        line(PaymentMethod.paybill, takings.paybill),
      ],
    );
  }
}

class _Blocked extends ConsumerWidget {
  const _Blocked(this.openShift, {this.onBack});

  final OpenShift openShift;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final first = openShift.userName.split(' ').first;
    final user = ref.watch(sessionProvider);
    // FD-11: a supervisor can close it here; anyone else is told who can.
    final canClose =
        user != null && mayCloseShift(user, shiftUserId: openShift.userId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Heading("$first's shift must be closed first"),
        Note.warning(
          '${openShift.userName} has had a shift open on this computer since '
          '${formatDayDateTime(openShift.openedAt)}. A new shift can start '
          'once it is closed.',
        ),
        const SizedBox(height: Space.x12),
        if (canClose)
          AppButton.primary(
            key: const ValueKey('shift.closeOther'),
            label: "Close $first's shift",
            onPressed: () => context.go(Routes.closeShiftFor(openShift.id)),
          )
        else
          Text(
            'Ask $first to sign in and close it, or ask the supervisor to close '
            "$first's shift.",
            key: const ValueKey('shift.askToClose'),
            style: LodgingType.of(context).body,
          ),
        const SizedBox(height: Space.x20),
        if (onBack != null) ...[
          AppButton.secondary(
            key: const ValueKey('shift.back'),
            label: 'Back',
            onPressed: onBack,
          ),
          const SizedBox(height: Space.x12),
        ],
        AppButton.secondary(
          key: const ValueKey('shift.signOut'),
          label: 'Sign out',
          onPressed: () => ref.read(sessionProvider.notifier).signOut(),
        ),
      ],
    );
  }
}
