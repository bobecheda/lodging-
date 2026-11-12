import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/gate.dart';
import '../../../app/theme/theme.dart';
import '../../../app/widgets/buttons.dart';
import '../../../app/widgets/gate_top_bar.dart';
import '../../../app/widgets/notes.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/clock/clock.dart';
import '../../../core/clock/nairobi.dart';
import '../data/shift_repository.dart';
import '../domain/shift.dart';
import '../domain/shift_close.dart';
import '../domain/shift_rules.dart';
import 'shift_providers.dart';

/// Before working, a receptionist opens a shift (its float comes from the
/// drawer, Story B),
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
        Text(formatDayDateTime(now), style: t.meta),
        const SizedBox(height: Space.x8),
        Semantics(
          header: true,
          child: Text(
            title ?? '${greetingFor(now)}, $firstName',
            style: t.pageTitle,
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

/// Opening a shift (Story B): no float to type. The float is what the
/// drawer held at its last count, and the receptionist never sees it.
/// Before the starting cash is counted, the shift can't open.
class _OpenNewState extends ConsumerState<_OpenNew> {
  String? _error;
  var _busy = false;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(currentShiftProvider.notifier).open(widget.user);
    } on ShiftAlreadyOpen {
      // Someone opened one meanwhile; reload so the router re-decides.
      ref.invalidate(currentShiftProvider);
    } on NoStartingCash catch (e) {
      ref.invalidate(drawerStartedProvider);
      if (mounted) setState(() => _error = '$e');
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
    final started = ref.watch(drawerStartedProvider).value;
    final mayCount = can(widget.user, Permission.checkDrawer);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Heading(null),
        Text(
          'Open your shift. Check-ins and payments start once it is open.',
          style: t.body.copyWith(color: c.muted),
        ),
        const SizedBox(height: Space.x24),
        if (started == false) ...[
          Note.warning(
            mayCount
                ? 'Count the starting cash in the drawer first (Cash).'
                : 'The starting cash hasn’t been counted yet. Ask the '
                      'supervisor or the owner to count it.',
            key: const ValueKey('shift.noStartingCash'),
          ),
          const SizedBox(height: Space.x16),
          if (mayCount) ...[
            AppButton.secondary(
              key: const ValueKey('shift.countStart'),
              label: 'Count the starting cash',
              onPressed: () => context.go(Routes.cash),
            ),
            const SizedBox(height: Space.x12),
          ],
        ],
        if (_error != null) ...[
          Note.error(_error!, key: const ValueKey('shift.error')),
          const SizedBox(height: Space.x16),
        ],
        AppButton.primary(
          key: const ValueKey('shift.submit'),
          label: 'Open shift',
          large: true,
          busy: _busy,
          onPressed: started == true ? _submit : null,
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

/// A receptionist back at their open shift: when it opened, and Continue.
/// No figures: the close is blind (Story B), so nothing here says what has
/// been taken.
class _Resume extends ConsumerWidget {
  const _Resume(this.user, this.shift);

  final UserAccount user;
  final OpenShift shift;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Heading('Welcome back, ${user.fullName.split(' ').first}'),
        Text(
          'Your shift has been open since ${formatDayDateTime(shift.openedAt)}.',
          key: const ValueKey('shift.since'),
          style: t.body.copyWith(color: c.muted),
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
