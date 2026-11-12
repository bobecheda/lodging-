import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/gate.dart';
import '../../../app/theme/theme.dart';
import '../../../app/widgets/buttons.dart';
import '../../../app/widgets/labeled_dropdown.dart';
import '../../../app/widgets/labeled_field.dart';
import '../../../app/widgets/money_input.dart';
import '../../../app/widgets/notes.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/money/kes.dart';
import '../data/drawer_repository.dart';
import '../data/shift_repository.dart';
import '../domain/drawer.dart';
import '../domain/shift_close.dart';
import 'shift_providers.dart';

enum _Step { present, count, reason, removed, done }

/// Story B2: a drawer check or a weekly collection, by the supervisor or
/// the owner, with the receptionist present.
///
/// 1. The receptionist co-signs with their own password (the one on shift,
///    or, with none open, whoever is at the desk).
/// 2. The counter counts blind: one recount, then a reason.
/// 3. A collection then says how much cash is taken away.
///
/// The screen never shows a figure while the receptionist is there: it ends
/// on "Counted." A collection's week of figures stays behind "Show the
/// week's figures", for the collector.
class DrawerCountScreen extends ConsumerStatefulWidget {
  const DrawerCountScreen({super.key, required this.kind});

  final DrawerCountKind kind;

  @override
  ConsumerState<DrawerCountScreen> createState() => _DrawerCountScreenState();
}

class _DrawerCountScreenState extends ConsumerState<DrawerCountScreen> {
  final _password = TextEditingController();
  final _count = TextEditingController();
  final _reason = TextEditingController();
  final _removed = TextEditingController();
  var _step = _Step.present;
  UserAccount? _present;
  List<UserAccount>? _choices;
  String? _chosenId;
  CosignToken? _token;
  int? _firstCount;
  int? _recount;
  DrawerEventRow? _saved;
  var _showWeek = false;
  String? _error;
  var _busy = false;

  bool get _collect => widget.kind == DrawerCountKind.collect;

  @override
  void initState() {
    super.initState();
    Future(() async {
      final user = ref.read(sessionProvider);
      if (user == null) return;
      final repo = ref.read(drawerRepositoryProvider);
      final present = await repo.presentForCount();
      final choices = present == null
          ? await repo.peopleWhoMayBePresent(user)
          : null;
      if (mounted) {
        setState(() {
          _present = present;
          _choices = choices;
          _chosenId = present?.id;
        });
      }
    });
  }

  @override
  void dispose() {
    for (final c in [_password, _count, _reason, _removed]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function(UserAccount user) action) async {
    final user = ref.read(sessionProvider);
    if (user == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(user);
    } on CosignRefused catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          // A refused or stale co-sign starts again from the co-sign.
          if (_step != _Step.present) {
            _step = _Step.present;
            _token = null;
          }
        });
      }
    } on DrawerCountProblem catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on DrawerRefused catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on NotPermitted {
      if (mounted) setState(() => _error = 'You can’t count the drawer.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cosign() => _run((user) async {
    final id = _chosenId;
    if (id == null) {
      setState(() => _error = 'Choose who is at the desk.');
      return;
    }
    final token = await ref
        .read(drawerRepositoryProvider)
        .cosign(user, presentUserId: id, password: _password.text);
    _password.clear();
    if (mounted) {
      setState(() {
        _token = token;
        _step = _Step.count;
      });
    }
  });

  Future<void> _submitCount() => _run((user) async {
    final amount = parseKes(_count.text);
    if (countError(amount) case final p?) {
      setState(() => _error = p);
      return;
    }
    final repo = ref.read(drawerRepositoryProvider);
    final matches = await repo.firstCountMatches(user, _token!, amount!);
    _count.clear();
    if (_firstCount == null) {
      _firstCount = amount;
      if (matches) return _afterCount();
      setState(() => _step = _Step.count);
      return;
    }
    _recount = amount;
    if (matches) return _afterCount();
    setState(() => _step = _Step.reason);
  });

  /// The count is settled: a check is saved now, a collection asks what is
  /// taken away first.
  Future<void> _afterCount() async {
    if (_collect) {
      setState(() => _step = _Step.removed);
      return;
    }
    await _save();
  }

  Future<void> _submitReason() => _run((user) async {
    if (closeReasonError(_reason.text) case final p?) {
      setState(() => _error = p);
      return;
    }
    await _afterCount();
  });

  Future<void> _submitRemoved() => _run((user) async {
    final amount = parseKes(_removed.text);
    final counted = _recount ?? _firstCount!;
    if (removedError(amount, counted: counted) case final p?) {
      setState(() => _error = p);
      return;
    }
    await _save(removed: amount!);
  });

  Future<void> _save({int removed = 0}) async {
    final user = ref.read(sessionProvider)!;
    final row = await ref
        .read(drawerRepositoryProvider)
        .recordCount(
          user,
          _token!,
          kind: widget.kind,
          firstCount: _firstCount!,
          recount: _recount,
          note: _step == _Step.reason || _reason.text.trim().isNotEmpty
              ? _reason.text
              : null,
          removed: removed,
        );
    if (mounted) {
      setState(() {
        _saved = row;
        _step = _Step.done;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final title = _collect ? 'Collect cash' : 'Check the drawer';
    final Widget body = switch (_step) {
      _Step.present => _presentStep(),
      _Step.count => _countStep(),
      _Step.reason => _reasonStep(),
      _Step.removed => _removedStep(),
      _Step.done => _doneStep(),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text(title, style: t.pageTitle)),
        Text(
          _collect
              ? 'Count the drawer, then say how much you take away. The '
                    'receptionist co-signs first.'
              : 'Count the drawer with the receptionist present. They '
                    'co-sign first.',
          style: t.secondary.copyWith(color: c.muted),
        ),
        const SizedBox(height: Space.x20),
        Expanded(
          child: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(Space.x24),
                    child: body,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _errorNote() => [
    if (_error != null) ...[
      const SizedBox(height: Space.x12),
      Note.error(_error!, key: const ValueKey('drawer.error')),
    ],
  ];

  Widget _presentStep() {
    final t = LodgingType.of(context);
    final present = _present;
    final choices = _choices;
    final name =
        present?.fullName ??
        choices
            ?.where((u) => u.id == _chosenId)
            .map((u) => u.fullName)
            .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (present != null)
          Text(
            '${present.fullName} is on shift and must be present.',
            key: const ValueKey('drawer.present'),
            style: t.body,
          )
        else if (choices != null)
          LabeledDropdown<String>(
            label: 'Who is at the desk',
            fieldKey: const ValueKey('drawer.presentPick'),
            value: _chosenId,
            options: [
              for (final u in choices) DropdownOption(u.id, u.fullName),
            ],
            onChanged: (id) => setState(() => _chosenId = id),
          ),
        const SizedBox(height: Space.x16),
        LabeledField(
          label: name == null ? 'Their password' : '$name’s password',
          controller: _password,
          fieldKey: const ValueKey('drawer.password'),
          obscureText: true,
          helperText: 'They type it themselves.',
          onSubmitted: (_) => _cosign(),
        ),
        ..._errorNote(),
        const SizedBox(height: Space.x20),
        AppButton.primary(
          key: const ValueKey('drawer.cosign'),
          label: 'Confirm they are present',
          busy: _busy,
          onPressed: _cosign,
        ),
        const SizedBox(height: Space.x8),
        AppButton.secondary(
          key: const ValueKey('drawer.cancel'),
          label: 'Back to Cash',
          onPressed: () => context.go(Routes.cash),
        ),
      ],
    );
  }

  Widget _countStep() {
    final t = LodgingType.of(context);
    final recount = _firstCount != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (recount) ...[
          const Note.warning(
            countAgainMessage,
            key: ValueKey('drawer.countAgain'),
          ),
          const SizedBox(height: Space.x16),
        ],
        Text(
          recount
              ? 'Count all the cash in the drawer once more.'
              : 'Count all the cash in the drawer.',
          style: t.body,
        ),
        const SizedBox(height: Space.x16),
        MoneyInput(
          label: 'Cash counted',
          controller: _count,
          fieldKey: const ValueKey('drawer.count'),
          large: true,
          autofocus: true,
          onSubmitted: (_) => _submitCount(),
        ),
        ..._errorNote(),
        const SizedBox(height: Space.x20),
        AppButton.primary(
          key: const ValueKey('drawer.submit'),
          label: recount ? 'Submit the recount' : 'Submit the count',
          busy: _busy,
          onPressed: _submitCount,
        ),
      ],
    );
  }

  Widget _reasonStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Note.warning(
        'The count still doesn’t match. Say why; it will be reviewed.',
        key: ValueKey('drawer.reasonNeeded'),
      ),
      const SizedBox(height: Space.x16),
      LabeledField(
        label: 'Reason',
        controller: _reason,
        fieldKey: const ValueKey('drawer.reason'),
        autofocus: true,
        helperText: 'At most $closeNoteMax characters.',
      ),
      ..._errorNote(),
      const SizedBox(height: Space.x20),
      AppButton.primary(
        key: const ValueKey('drawer.reasonSave'),
        label: 'Continue',
        busy: _busy,
        onPressed: _submitReason,
      ),
    ],
  );

  Widget _removedStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      MoneyInput(
        label: 'Cash taken away',
        controller: _removed,
        fieldKey: const ValueKey('drawer.removed'),
        large: true,
        autofocus: true,
        helperText: 'No more than you counted.',
        onSubmitted: (_) => _submitRemoved(),
      ),
      ..._errorNote(),
      const SizedBox(height: Space.x20),
      AppButton.primary(
        key: const ValueKey('drawer.removedSave'),
        label: 'Save the collection',
        busy: _busy,
        onPressed: _submitRemoved,
      ),
    ],
  );

  Widget _doneStep() {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final saved = _saved!;
    return Column(
      key: const ValueKey('drawer.done'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle_rounded, color: c.marine, size: 24),
            const SizedBox(width: Space.x8),
            Text('Counted.', style: t.sectionTitle),
          ],
        ),
        if (_collect) ...[
          const SizedBox(height: Space.x16),
          if (!_showWeek)
            AppButton.secondary(
              key: const ValueKey('drawer.showWeek'),
              label: 'Show the week’s figures',
              onPressed: () => setState(() => _showWeek = true),
            )
          else
            _WeekFigures(saved),
        ],
        const SizedBox(height: Space.x20),
        AppButton.primary(
          key: const ValueKey('drawer.back'),
          label: 'Back to Cash',
          onPressed: () => context.go(Routes.cash),
        ),
      ],
    );
  }
}

/// The collector's reconciliation since the last collection: this
/// collection's expected, count, gap and what was taken, then the shift
/// closes, checks, reviews and recount matches since the one before.
class _WeekFigures extends ConsumerWidget {
  const _WeekFigures(this.saved);

  final DrawerEventRow saved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final chain = ref.watch(drawerChainProvider).value ?? const [];
    final week = sinceLastCollection(chain);
    Widget row(String label, String value, {String? key}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: t.body.copyWith(color: c.inkSoft)),
          ),
          Text(
            value,
            key: key == null ? null : ValueKey(key),
            style: t.moneySmall,
          ),
        ],
      ),
    );
    final expected = saved.expected!;
    return Column(
      key: const ValueKey('drawer.week'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row('Expected', formatKes(expected)),
        row('Counted', formatKes(saved.counted)),
        row(
          'Gap',
          varianceLabel(saved.counted - expected),
          key: 'drawer.week.gap',
        ),
        row('Taken away', formatKes(saved.removed)),
        row('Left in the drawer', formatKes(saved.counted - saved.removed)),
        Divider(color: c.lineSoft),
        Text('Since the last collection', style: t.meta),
        row('Shift closes', '${week.closes}'),
        row('Drawer checks', '${week.checks}'),
        row('Needing review', '${week.reviews}', key: 'drawer.week.reviews'),
        row('Matched only on recount', '${week.recountMatches}'),
      ],
    );
  }
}
