import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/theme.dart';
import '../../../app/widgets/buttons.dart';
import '../../../app/widgets/labeled_field.dart';
import '../../../app/widgets/notes.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/clock/nairobi.dart';
import '../../../core/money/kes.dart';
import '../../auth/domain/credentials.dart';
import '../data/owner_cloud.dart';
import '../data/owner_more_repository.dart';
import '../domain/owner_more.dart';
import 'owner_app.dart';
import 'owner_providers.dart';

/// A page under More: "‹ More", its title, then [children].
class _MorePage extends StatelessWidget {
  const _MorePage({
    required this.title,
    required this.listKey,
    required this.children,
    this.onRefresh,
  });

  final String title;
  final String listKey;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    final list = ListView(
      key: ValueKey(listKey),
      padding: const EdgeInsets.fromLTRB(
        Space.x16,
        Space.x8,
        Space.x16,
        Space.x16,
      ),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Semantics(header: true, child: Text(title, style: t.pageTitle)),
        const SizedBox(height: Space.x12),
        ...children,
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.x8, Space.x8, Space.x16, 0),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('more.back'),
              onPressed: () => context.go(OwnerRoutes.more),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: Text('More', style: t.bodyStrong),
            ),
          ),
        ),
        Expanded(
          child: onRefresh == null
              ? list
              : RefreshIndicator(onRefresh: onRefresh!, child: list),
        ),
      ],
    );
  }
}

Widget _loading<T>(
  AsyncValue<T> value, {
  required String what,
  required Widget Function(T data) data,
}) => switch (value) {
  AsyncData(:final value) => data(value),
  AsyncError(:final error) => Note.error(
    error is OwnerCloudOffline
        ? 'No internet connection. $what shows once the phone is online.'
        : '$error',
    title: '$what could not be loaded.',
  ),
  _ => const Padding(
    padding: EdgeInsets.all(Space.x24),
    child: Center(child: CircularProgressIndicator()),
  ),
};

/// A label on the left, a value on the right.
class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.valueKey});

  final String label;
  final String value;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x4 / 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: t.small.copyWith(color: c.inkSoft)),
          ),
          const SizedBox(width: Space.x8),
          Flexible(
            child: Text(
              value,
              key: valueKey,
              textAlign: TextAlign.end,
              style: t.mono,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shifts ───────────────────────────────────────────────────────────────

/// More → Shifts (read-only): the open shift with what it has taken so far,
/// then the last 30 days' closed shifts, newest first.
class OwnerShiftsScreen extends ConsumerWidget {
  const OwnerShiftsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shifts = ref.watch(ownerShiftsProvider);
    final now = ref.watch(ownerClockProvider).now();
    return _MorePage(
      title: 'Shifts',
      listKey: 'owner.shifts',
      onRefresh: () => ref.refresh(ownerShiftsProvider.future),
      children: [
        _loading(
          shifts,
          what: 'Shifts',
          data: (list) => list.isEmpty
              ? const Note.info('No shifts in the last 30 days.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final s in list) ...[
                      _ShiftCard(s, now: now),
                      const SizedBox(height: Space.x12),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _ShiftCard extends StatelessWidget {
  const _ShiftCard(this.shift, {required this.now});

  final OwnerShift shift;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final s = shift;
    final takings = s.takings;
    final variance = s.variance;
    return Card(
      key: ValueKey('owner.shift.${s.id}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Space.x16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(s.userName, style: t.bodyStrong)),
                if (s.open)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.x8,
                      vertical: Space.x4 / 2,
                    ),
                    decoration: BoxDecoration(
                      color: c.marineTint,
                      borderRadius: BorderRadius.circular(Radii.badge),
                    ),
                    child: Text(
                      'OPEN',
                      style: t.smallStrong.copyWith(color: c.marine),
                    ),
                  ),
              ],
            ),
            Text(
              s.open
                  ? 'Since ${formatWhen(s.openedAt, now: now)}'
                  : '${formatWhen(s.openedAt, now: now)} – '
                        '${formatWhen(s.closedAt!, now: now)}',
              style: t.small.copyWith(color: c.muted),
            ),
            const SizedBox(height: Space.x8),
            if (takings != null) ...[
              _Line(
                'Cash so far',
                formatKes(takings.cash.net),
                valueKey: ValueKey('owner.shift.${s.id}.cash'),
              ),
              _Line('M-Pesa so far', formatKes(takings.paybill.net)),
              _Line(
                'Expected in the drawer',
                formatKes(takings.expectedCash(openingFloat: s.openingFloat)),
              ),
            ] else ...[
              _Line('Expected cash', formatKes(s.expectedCash ?? 0)),
              _Line('Counted', formatKes(s.countedCash ?? 0)),
              if (variance != null)
                _Line(
                  'Difference',
                  varianceLine(variance),
                  valueKey: ValueKey('owner.shift.${s.id}.variance'),
                ),
              _Line('M-Pesa', formatKes(s.expectedPaybill ?? 0)),
              if (s.closeNote case final note?)
                Padding(
                  padding: const EdgeInsets.only(top: Space.x4),
                  child: Text(
                    '“$note”',
                    style: t.small.copyWith(color: c.inkSoft),
                  ),
                ),
              if (s.closedBy case final by? when by != s.userName)
                Text('Closed by $by', style: t.small.copyWith(color: c.muted)),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Audit trail ──────────────────────────────────────────────────────────

/// More → Audit trail (read-only): the latest entries, newest first, with
/// who, what, where and when; details only where they hold no guest data.
class OwnerAuditScreen extends ConsumerStatefulWidget {
  const OwnerAuditScreen({super.key});

  @override
  ConsumerState<OwnerAuditScreen> createState() => _OwnerAuditState();
}

class _OwnerAuditState extends ConsumerState<OwnerAuditScreen> {
  String? _userId;
  AuditKind? _kind;
  int? _days;

  static const _periods = {null: 'All', 1: 'Today', 7: '7 days', 30: '30 days'};

  AuditFilter _filter(DateTime now) => AuditFilter(
    userId: _userId,
    kind: _kind,
    since: switch (_days) {
      null => null,
      1 => dayStartOf(now),
      final d => now.subtract(Duration(days: d)),
    },
  );

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final now = ref.watch(ownerClockProvider).now();
    final filter = _filter(now);
    final entries = ref.watch(ownerAuditProvider(filter));
    final staff = ref.watch(ownerStaffProvider).value ?? const [];
    Widget chip<T>(
      String key,
      String label,
      T value,
      T selected,
      void Function(T) on,
    ) => ChoiceChip(
      key: ValueKey(key),
      label: Text(label),
      selected: value == selected,
      onSelected: (_) => setState(() => on(value)),
    );
    return _MorePage(
      title: 'Audit trail',
      listKey: 'owner.audit',
      onRefresh: () => ref.refresh(ownerAuditProvider(filter).future),
      children: [
        Wrap(
          spacing: Space.x8,
          runSpacing: Space.x8,
          children: [
            chip<AuditKind?>(
              'audit.kind.all',
              'Everything',
              null,
              _kind,
              (v) => _kind = v,
            ),
            for (final k in AuditKind.values)
              chip<AuditKind?>(
                'audit.kind.${k.name}',
                k.label,
                k,
                _kind,
                (v) => _kind = v,
              ),
          ],
        ),
        const SizedBox(height: Space.x8),
        Wrap(
          spacing: Space.x8,
          runSpacing: Space.x8,
          children: [
            for (final MapEntry(:key, :value) in _periods.entries)
              chip<int?>(
                'audit.days.${key ?? 'all'}',
                value,
                key,
                _days,
                (v) => _days = v,
              ),
          ],
        ),
        const SizedBox(height: Space.x8),
        DropdownButton<String?>(
          key: const ValueKey('audit.person'),
          isExpanded: true,
          value: _userId,
          items: [
            const DropdownMenuItem(value: null, child: Text('Everyone')),
            for (final s in staff)
              DropdownMenuItem(value: s.id, child: Text(s.name)),
          ],
          onChanged: (v) => setState(() => _userId = v),
        ),
        const SizedBox(height: Space.x12),
        _loading(
          entries,
          what: 'The audit trail',
          data: (list) => list.isEmpty
              ? const Note.info('Nothing matches.')
              : Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, e) in list.indexed) ...[
                        if (i > 0) Divider(height: 1, color: c.lineSoft),
                        Padding(
                          key: ValueKey('audit.entry.$i'),
                          padding: const EdgeInsets.all(Space.x12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.action, style: t.bodyStrong),
                              if (e.detail case final d?)
                                Text(
                                  d,
                                  key: ValueKey('audit.entry.$i.detail'),
                                  style: t.small.copyWith(color: c.inkSoft),
                                ),
                              Text(
                                '${e.who} · ${e.where} · '
                                '${formatWhen(e.at, now: now)}',
                                key: ValueKey('audit.entry.$i.who'),
                                style: t.small.copyWith(color: c.muted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
        const SizedBox(height: Space.x8),
        Text(
          'The latest ${OwnerMoreRepository.auditShown} entries. Guests’ '
          'details are never shown here.',
          style: t.small.copyWith(color: c.muted),
        ),
      ],
    );
  }
}

/// Nairobi midnight starting [now]'s day.
DateTime dayStartOf(DateTime now) {
  final t = toNairobi(now);
  return nairobiInstant(t.year, t.month, t.day);
}

// ── Staff ────────────────────────────────────────────────────────────────

/// More → Staff (read-only): everyone on the desk, and who is disabled.
class OwnerStaffScreen extends ConsumerWidget {
  const OwnerStaffScreen({super.key});

  static String _role(Role r) => switch (r) {
    Role.owner => 'Owner',
    Role.supervisor => 'Supervisor',
    Role.receptionist => 'Receptionist',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final staff = ref.watch(ownerStaffProvider);
    return _MorePage(
      title: 'Staff',
      listKey: 'owner.staff',
      onRefresh: () => ref.refresh(ownerStaffProvider.future),
      children: [
        _loading(
          staff,
          what: 'Staff',
          data: (list) => Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, s) in list.indexed) ...[
                  if (i > 0) Divider(height: 1, color: c.lineSoft),
                  Padding(
                    key: ValueKey('owner.staff.${s.username}'),
                    padding: const EdgeInsets.all(Space.x12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.name,
                                style: t.bodyStrong.copyWith(
                                  color: s.active ? c.ink : c.muted,
                                ),
                              ),
                              Text(
                                '${_role(s.role)} · ${s.username}'
                                '${s.active ? '' : ' · Disabled'}',
                                style: t.small.copyWith(color: c.muted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.x8),
        Text(
          'Adding staff, resetting passwords and disabling are done at the '
          'desk.',
          style: t.small.copyWith(color: c.muted),
        ),
      ],
    );
  }
}

// ── Change password ──────────────────────────────────────────────────────

/// More → Change password: current, new, new again. It is also the
/// owner's password at the desk, which asks for the new one (online) the
/// next time.
class OwnerPasswordScreen extends ConsumerStatefulWidget {
  const OwnerPasswordScreen({super.key});

  @override
  ConsumerState<OwnerPasswordScreen> createState() => _OwnerPasswordState();
}

class _OwnerPasswordState extends ConsumerState<OwnerPasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _repeat = TextEditingController();
  String? _problem;
  var _done = false;
  var _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final signedIn = ref.read(ownerSessionProvider).value;
    if (signedIn == null) return;
    if (_next.text != _repeat.text) {
      setState(() => _problem = 'The new passwords don’t match.');
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
      _done = false;
    });
    try {
      await ref
          .read(ownerMoreRepositoryProvider)
          .changePassword(
            ownerAccount(signedIn),
            current: _current.text,
            next: _next.text,
          );
      if (mounted) {
        setState(() => _done = true);
        _current.clear();
        _next.clear();
        _repeat.clear();
      }
    } on OwnerPasswordRefused catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } on OwnerCloudOffline {
      if (mounted) {
        setState(
          () =>
              _problem = 'Changing your password needs an internet connection.',
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
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    return _MorePage(
      title: 'Change password',
      listKey: 'owner.password',
      children: [
        Text(
          'It is also your password at the desk: the desk asks for the new '
          'one, once, the next time you sign in there (it needs the '
          'internet then).',
          style: t.small.copyWith(color: c.inkSoft),
        ),
        const SizedBox(height: Space.x12),
        if (_done) ...[
          const Note.info(
            'Password changed.',
            key: ValueKey('ownerPassword.done'),
          ),
          const SizedBox(height: Space.x12),
        ],
        LabeledField(
          label: 'Current password',
          controller: _current,
          fieldKey: const ValueKey('ownerPassword.current'),
          obscureText: true,
          autofillHints: const [AutofillHints.password],
        ),
        const SizedBox(height: Space.x12),
        LabeledField(
          label: 'New password',
          controller: _next,
          fieldKey: const ValueKey('ownerPassword.new'),
          obscureText: true,
          helperText: 'At least $minPasswordLength characters',
          autofillHints: const [AutofillHints.newPassword],
        ),
        const SizedBox(height: Space.x12),
        LabeledField(
          label: 'New password again',
          controller: _repeat,
          fieldKey: const ValueKey('ownerPassword.repeat'),
          obscureText: true,
          onSubmitted: (_) => _save(),
        ),
        if (_problem != null) ...[
          const SizedBox(height: Space.x12),
          Note.error(_problem!, key: const ValueKey('ownerPassword.problem')),
        ],
        const SizedBox(height: Space.x16),
        AppButton.primary(
          key: const ValueKey('ownerPassword.save'),
          label: 'Change password',
          large: true,
          busy: _busy,
          onPressed: _save,
        ),
      ],
    );
  }
}
