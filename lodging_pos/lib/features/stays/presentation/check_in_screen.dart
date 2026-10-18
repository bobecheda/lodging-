import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/gate.dart';
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
import '../../bed_board/presentation/bed_board_providers.dart';
import '../../guests/data/guests_repository.dart';
import '../../guests/domain/guest.dart';
import '../../guests/presentation/widgets/guest_finder_card.dart';
import '../../payments/domain/payment_rules.dart';
import '../../receipts/presentation/receipt_view.dart';
import '../../setup/domain/rooms.dart';
import '../../shifts/domain/shift_rules.dart';
import '../../shifts/presentation/shift_providers.dart';
import '../data/check_in_repository.dart';
import '../domain/check_in.dart';
import '../domain/stay_rules.dart';
import 'check_in_providers.dart';

/// FD-4 "New check-in" with its payment (FD-5), from the artboard
/// "Check-in — bed, guest, blocks, payment": the bed (and Bed B for the
/// whole room), the guest, then nights and payment. Nothing is saved until
/// "Save and issue receipt"; then step 4 shows what was saved (the printed
/// receipt, FD-6).
class CheckInScreen extends ConsumerStatefulWidget {
  const CheckInScreen({super.key, this.bedId});

  /// The bed to start with (a Ready tile on the board), if any.
  final String? bedId;

  @override
  ConsumerState<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends ConsumerState<CheckInScreen> {
  String? _bedId;
  var _wholeRoom = false;
  Guest? _guest;
  GuestForm? _newGuest;
  var _phoneSeen = <String>{};
  var _nights = 1;
  var _nightsText = '1';
  PaymentMethod? _method;
  final _code = TextEditingController();

  var _errors = <CheckInField, String>{};
  String? _problem;
  var _busy = false;
  _Saved? _saved;

  @override
  void initState() {
    super.initState();
    _bedId = widget.bedId;
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _chooseBed(String? bedId) => setState(() {
    _bedId = bedId;
    _wholeRoom = false;
    _problem = null;
  });

  void _restart() {
    setState(() {
      _bedId = null;
      _wholeRoom = false;
      _guest = null;
      _newGuest = null;
      _phoneSeen = {};
      _nights = 1;
      _nightsText = '1';
      _method = null;
      _code.clear();
      _errors = {};
      _problem = null;
      _saved = null;
    });
    context.go(Routes.checkIn);
  }

  Future<void> _save(UserAccount user, CheckInQuote quote) async {
    final newGuest = _newGuest;
    final guest = _guest;
    final method = _method!;
    setState(() {
      _busy = true;
      _errors = {};
      _problem = null;
    });
    try {
      final result = await ref
          .read(checkInRepositoryProvider)
          .checkIn(
            user,
            CheckInRequest(
              guest: newGuest != null
                  ? NewGuest(newGuest, phoneSharedWith: _phoneSeen)
                  : ReturningGuest(guest!.id),
              method: method,
              mpesaCode: method == PaymentMethod.paybill ? _code.text : null,
              shown: quote,
            ),
          );
      if (!mounted) return;
      setState(
        () => _saved = _Saved(
          result,
          newGuest?.normalized().fullName ?? guest!.fullName,
        ),
      );
    } on InvalidCheckIn catch (e) {
      if (!mounted) return;
      setState(() {
        _errors = e.errors;
        final other = {...e.errors}..remove(CheckInField.mpesaCode);
        if (other.isNotEmpty) _problem = other.values.join(' ');
      });
    } on CheckInRefused catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } on PhoneNowShared catch (e) {
      if (!mounted) return;
      setState(() {
        _problem = e.toString();
        _phoneSeen = {..._phoneSeen, for (final g in e.guests) g.id};
      });
    } on InvalidGuest catch (e) {
      if (mounted) setState(() => _problem = e.errors.values.join(' '));
    } on NoOpenShift {
      if (mounted) setState(() => _problem = _noShift);
    } on NotPermitted {
      if (mounted) setState(() => _problem = 'You can’t check guests in.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _noShift = 'Check-in takes a payment. Open a shift first.';

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider);
    final rooms = ref.watch(checkInRoomsProvider);
    final checkout = ref.watch(checkInCheckoutTimeProvider).value;
    final now = ref.watch(boardNowProvider).value;
    final shift = ref.watch(currentShiftProvider).value;
    final saved = _saved;

    final header = _Header(
      bedDone: _bedId != null || saved != null,
      guestDone: _guest != null || _newGuest != null || saved != null,
      saved: saved != null,
    );
    if (user == null) return const SizedBox.shrink();
    if (saved != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: Space.x20),
          Expanded(
            child: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topLeft,
                child: _Done(
                  saved: saved,
                  onBoard: () => context.go(Routes.home),
                  onAnother: _restart,
                ),
              ),
            ),
          ),
        ],
      );
    }
    if (rooms case AsyncError(:final error)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: Space.x16),
          Note.error('$error', title: 'The beds could not be loaded.'),
        ],
      );
    }
    final list = rooms.value;
    if (list == null || checkout == null || now == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }

    // The chosen bed, its room and the room's other bed.
    RoomSummary? room;
    BedSummary? bed;
    for (final r in list) {
      for (final b in r.beds) {
        if (b.id == _bedId) (room, bed) = (r, b);
      }
    }
    final other = room?.beds.where((b) => b.id != bed!.id).firstOrNull;
    final bedProblem = bed == null ? null : _blocker(bed);
    final otherProblem = other == null ? null : _blocker(other);
    final letting = [
      ?bed,
      if (_wholeRoom && other != null && otherProblem == null) other,
    ];

    final nightsProblem = nightsError(parseNights(_nightsText));
    final quote = bed == null || bedProblem != null || nightsProblem != null
        ? null
        : quoteCheckIn(
            checkInAt: now,
            nights: _nights,
            checkout: checkout,
            beds: [
              for (final b in letting)
                LetBed(
                  bedId: b.id,
                  categoryId: b.categoryId,
                  categoryName: b.categoryName,
                  pricePerNight: b.pricePerNight,
                ),
            ],
          );
    final ownShift = shift != null && shift.userId == user.id;
    final hasGuest = _guest != null || _newGuest != null;
    final missing = [
      if (bed == null) 'the bed',
      if (!hasGuest) 'the guest',
      if (_method == null) 'how they paid',
    ];

    final guestId = _guest?.id;
    final bedCard = _BedCard(
      rooms: list,
      room: room,
      bed: bed,
      bedProblem: bedProblem,
      other: other,
      otherProblem: otherProblem,
      wholeRoom: _wholeRoom,
      onChoose: _chooseBed,
      onWholeRoom: (v) => setState(() => _wholeRoom = v),
    );
    final guestCard = GuestFinderCard(
      selected: _guest,
      newGuest: _newGuest,
      selectedDetail: guestId == null
          ? null
          : ref.watch(guestHistoryProvider(guestId)).value?.summary,
      onSelected: (g) => setState(() {
        _guest = g;
        _newGuest = null;
        _phoneSeen = {};
        _problem = null;
      }),
      onNewGuest: (form, seen) => setState(() {
        _newGuest = form;
        _phoneSeen = seen;
        _guest = null;
        _problem = null;
      }),
    );
    final stayCard = _StayCard(
      nights: _nights,
      nightsError: nightsProblem ?? _errors[CheckInField.nights],
      checkoutLabel: checkout.format(),
      onNights: (n) => setState(() => _nights = n),
      onNightsTyped: (text) => setState(() {
        _nightsText = text;
        final n = parseNights(text);
        if (n != null && nightsError(n) == null) _nights = n;
      }),
      checkInAt: now,
      quote: quote,
      letting: letting,
      method: _method,
      onMethod: (m) => setState(() => _method = m),
      code: _code,
      codeError: _errors[CheckInField.mpesaCode],
      ownShift: ownShift,
      onOpenShift: () =>
          context.go(Routes.shiftThen(Routes.checkInFor(_bedId))),
      problem: _problem,
      missing: missing,
      busy: _busy,
      onSave: quote == null || !hasGuest || _method == null || !ownShift
          ? null
          : () => _save(user, quote),
    );

    Widget column(Widget card) =>
        Expanded(child: SingleChildScrollView(child: card));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: Space.x20),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              column(bedCard),
              const SizedBox(width: Space.x16),
              column(guestCard),
              const SizedBox(width: Space.x16),
              column(stayCard),
            ],
          ),
        ),
      ],
    );
  }

  static String? _blocker(BedSummary b) =>
      letBlocker(b, b.hasActiveStay ? Occupancy.occupied : Occupancy.available);
}

final class _Saved {
  const _Saved(this.result, this.guestName);
  final CheckInResult result;
  final String guestName;
}

/// Back link, title and the step pills.
class _Header extends StatelessWidget {
  const _Header({
    required this.bedDone,
    required this.guestDone,
    required this.saved,
  });

  final bool bedDone;
  final bool guestDone;
  final bool saved;

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    _Step state(bool done, {bool current = false}) => done
        ? _Step.done
        : current
        ? _Step.current
        : _Step.todo;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(
                key: const ValueKey('checkIn.back'),
                onPressed: () => context.go(Routes.home),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Bed board'),
              ),
              Semantics(
                header: true,
                child: Text('New check-in', style: t.pageTitle),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: Space.x8,
          runSpacing: Space.x8,
          children: [
            _StepPill(1, 'Bed', state(bedDone, current: true)),
            _StepPill(2, 'Guest', state(guestDone, current: bedDone)),
            _StepPill(
              3,
              'Stay & payment',
              state(saved, current: bedDone && guestDone),
            ),
            _StepPill(4, 'Receipt', saved ? _Step.current : _Step.todo),
          ],
        ),
      ],
    );
  }
}

enum _Step { done, current, todo }

class _StepPill extends StatelessWidget {
  const _StepPill(this.number, this.label, this.step);

  final int number;
  final String label;
  final _Step step;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final (Color bg, Color fg, Color? border) = switch (step) {
      _Step.done => (c.marineTint, c.marine, null),
      _Step.current => (c.marine, c.white, null),
      _Step.todo => (c.white, c.muted, c.line),
    };
    final spoken = switch (step) {
      _Step.done => 'done',
      _Step.current => 'current step',
      _Step.todo => 'to do',
    };
    return Semantics(
      label: 'Step $number, $label, $spoken',
      excludeSemantics: true,
      child: Container(
        key: ValueKey('checkIn.step.$number.${step.name}'),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.x14,
          vertical: Space.x8,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: border == null ? null : Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (step == _Step.done)
              Icon(Icons.check_rounded, size: 16, color: fg)
            else
              Text('$number', style: t.smallStrong.copyWith(color: fg)),
            const SizedBox(width: Space.x6),
            Text(label, style: t.smallStrong.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}

/// "BED": the chosen bed and Bed B for the whole room, or the Ready beds
/// to choose from.
class _BedCard extends StatelessWidget {
  const _BedCard({
    required this.rooms,
    required this.room,
    required this.bed,
    required this.bedProblem,
    required this.other,
    required this.otherProblem,
    required this.wholeRoom,
    required this.onChoose,
    required this.onWholeRoom,
  });

  final List<RoomSummary> rooms;
  final RoomSummary? room;
  final BedSummary? bed;
  final String? bedProblem;
  final BedSummary? other;
  final String? otherProblem;
  final bool wholeRoom;
  final ValueChanged<String?> onChoose;
  final ValueChanged<bool> onWholeRoom;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final room = this.room;
    final bed = this.bed;
    final other = this.other;

    final List<Widget> body;
    if (room == null || bed == null) {
      final ready = [
        for (final r in rooms)
          for (final b in r.beds)
            if (_CheckInScreenState._blocker(b) == null) (r, b),
      ];
      body = [
        Text('Choose a Ready bed.', style: t.body.copyWith(color: c.inkSoft)),
        const SizedBox(height: Space.x12),
        if (ready.isEmpty)
          const Note.info(
            'No bed is ready right now. Beds that need cleaning become '
            'Ready once they are cleaned.',
          ),
        for (final (r, b) in ready)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.x6),
            child: Material(
              color: c.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Radii.control),
                side: BorderSide(color: c.line),
              ),
              child: InkWell(
                key: ValueKey('checkIn.pick.${r.number}${b.label.code}'),
                borderRadius: BorderRadius.circular(Radii.control),
                onTap: () => onChoose(b.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.x12,
                    vertical: Space.x10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Room ${r.number} · Bed ${b.label.code}',
                          style: t.bodyStrong,
                        ),
                      ),
                      Text(
                        '${b.categoryName} · ${formatKes(b.pricePerNight)}',
                        style: t.small.copyWith(color: c.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ];
    } else {
      body = [
        Row(
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.marineTint,
                borderRadius: BorderRadius.circular(Radii.control),
              ),
              child: Text(
                '${room.number}${bed.label.code}',
                style: t.sectionTitle.copyWith(color: c.marine),
              ),
            ),
            const SizedBox(width: Space.x14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Room ${room.number} · Bed ${bed.label.code}',
                    key: const ValueKey('checkIn.bed'),
                    style: t.sectionTitle,
                  ),
                  Text(
                    '${bed.categoryName} · ${formatKes(bed.pricePerNight)} / '
                    'night',
                    style: t.small.copyWith(color: c.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (bedProblem != null) ...[
          const SizedBox(height: Space.x12),
          Note.error(
            'Room ${room.number} · $bedProblem now. Choose another bed.',
            key: const ValueKey('checkIn.bedProblem'),
          ),
        ],
        if (other != null) ...[
          const SizedBox(height: Space.x12),
          Divider(color: c.lineSoft),
          CheckboxListTile(
            key: const ValueKey('checkIn.wholeRoom'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: wholeRoom && otherProblem == null,
            onChanged: otherProblem != null || bedProblem != null
                ? null
                : (v) => onWholeRoom(v ?? false),
            title: Text(
              'Also let Bed ${other.label.code} to this guest (whole room)',
              style: t.body,
            ),
            subtitle: otherProblem == null
                ? Text(
                    '${other.categoryName} · ${formatKes(other.pricePerNight)}'
                    ' / night',
                    style: t.small.copyWith(color: c.muted),
                  )
                : null,
          ),
          if (otherProblem != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: StatusBadge(
                otherProblem!,
                key: const ValueKey('checkIn.otherProblem'),
                tone: BadgeTone.warning,
              ),
            ),
        ],
      ];
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.x24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'BED',
                    style: t.capsLabel.copyWith(color: c.muted),
                  ),
                ),
                if (bed != null)
                  TextButton(
                    key: const ValueKey('checkIn.changeBed'),
                    onPressed: () => onChoose(null),
                    child: const Text('Change'),
                  ),
              ],
            ),
            const SizedBox(height: Space.x12),
            ...body,
          ],
        ),
      ),
    );
  }
}

/// "STAY & PAYMENT": nights, dates, total, method, M-Pesa code, save.
class _StayCard extends StatelessWidget {
  const _StayCard({
    required this.nights,
    required this.nightsError,
    required this.checkoutLabel,
    required this.onNights,
    required this.onNightsTyped,
    required this.checkInAt,
    required this.quote,
    required this.letting,
    required this.method,
    required this.onMethod,
    required this.code,
    required this.codeError,
    required this.ownShift,
    required this.onOpenShift,
    required this.problem,
    required this.missing,
    required this.busy,
    required this.onSave,
  });

  final int nights;
  final String? nightsError;
  final String checkoutLabel;
  final ValueChanged<int> onNights;
  final ValueChanged<String> onNightsTyped;
  final DateTime checkInAt;
  final CheckInQuote? quote;
  final List<BedSummary> letting;
  final PaymentMethod? method;
  final ValueChanged<PaymentMethod> onMethod;
  final TextEditingController code;
  final String? codeError;
  final bool ownShift;
  final VoidCallback onOpenShift;
  final String? problem;
  final List<String> missing;
  final bool busy;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final quote = this.quote;

    Widget dateBox(String label, String value, Key key) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.small.copyWith(color: c.muted)),
          Text(value, key: key, style: t.bodyStrong),
        ],
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.x24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('STAY & PAYMENT', style: t.capsLabel.copyWith(color: c.muted)),
            const SizedBox(height: Space.x12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Nights', style: t.bodyStrong),
                      Text(
                        'Checkout is $checkoutLabel',
                        style: t.small.copyWith(color: c.muted),
                      ),
                    ],
                  ),
                ),
                NightStepper(
                  value: nights,
                  min: nightsRange.min,
                  max: nightsRange.max,
                  onChanged: onNights,
                  onTyped: onNightsTyped,
                ),
              ],
            ),
            if (nightsError != null) ...[
              const SizedBox(height: Space.x6),
              Text(
                nightsError!,
                key: const ValueKey('checkIn.nightsError'),
                style: t.small.copyWith(color: c.redText),
              ),
            ],
            const SizedBox(height: Space.x12),
            Container(
              padding: const EdgeInsets.all(Space.x12),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(Radii.control),
              ),
              child: Row(
                children: [
                  dateBox(
                    'Check-in',
                    formatDayDateComma(checkInAt),
                    const ValueKey('checkIn.from'),
                  ),
                  const SizedBox(width: Space.x12),
                  dateBox(
                    'Check-out by',
                    quote == null ? '—' : formatDayDateComma(quote.paidUntil),
                    const ValueKey('checkIn.until'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.x12),
            Divider(color: c.lineSoft),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (quote != null)
                        for (final s in quote.plan.stays)
                          Text(
                            [
                              if (letting.length > 1)
                                'Bed ${letting.firstWhere((b) => b.id == s.bedId).label.code}',
                              '${s.charge.nights} × '
                                  '${formatKes(s.charge.pricePerNight)}',
                            ].join(' · '),
                            style: t.small.copyWith(color: c.muted),
                          ),
                    ],
                  ),
                ),
                Text(
                  quote == null ? '—' : formatKes(quote.total),
                  key: const ValueKey('checkIn.total'),
                  style: t.moneyLarge,
                ),
              ],
            ),
            const SizedBox(height: Space.x16),
            Text('Paid by', style: t.fieldLabel),
            const SizedBox(height: Space.x6),
            SegmentedChoice<PaymentMethod>(
              options: [
                for (final m in PaymentMethod.values) ChoiceOption(m, m.label),
              ],
              selected: method,
              onChanged: onMethod,
            ),
            if (method == PaymentMethod.paybill) ...[
              const SizedBox(height: Space.x12),
              LabeledField(
                label: 'M-Pesa transaction code',
                controller: code,
                fieldKey: const ValueKey('checkIn.mpesaCode'),
                textStyle: t.monoStrong,
                helperText:
                    'Each code can be used once. A used code is '
                    'refused.',
                errorText: codeError,
              ),
            ],
            if (!ownShift) ...[
              const SizedBox(height: Space.x16),
              const Note.warning(
                _CheckInScreenState._noShift,
                key: ValueKey('checkIn.noShift'),
              ),
              const SizedBox(height: Space.x8),
              AppButton.secondary(
                key: const ValueKey('checkIn.openShift'),
                label: 'Open shift',
                onPressed: onOpenShift,
              ),
            ],
            if (problem != null) ...[
              const SizedBox(height: Space.x16),
              Note.error(problem!, key: const ValueKey('checkIn.problem')),
            ],
            const SizedBox(height: Space.x16),
            if (missing.isNotEmpty && ownShift) ...[
              Text(
                'Still to choose: ${missing.join(', ')}.',
                key: const ValueKey('checkIn.missing'),
                style: t.small.copyWith(color: c.muted),
              ),
              const SizedBox(height: Space.x8),
            ],
            AppButton.primary(
              key: const ValueKey('checkIn.save'),
              label: 'Save and issue receipt',
              busy: busy,
              onPressed: onSave,
            ),
            const SizedBox(height: Space.x8),
            Text(
              'The bed becomes Occupied only after this is saved.',
              textAlign: TextAlign.center,
              style: t.small.copyWith(color: c.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Step 4: the receipt (FD-6), with Print as the main button. No print
/// dialog opens by itself.
class _Done extends StatelessWidget {
  const _Done({
    required this.saved,
    required this.onBoard,
    required this.onAnother,
  });

  final _Saved saved;
  final VoidCallback onBoard;
  final VoidCallback onAnother;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final r = saved.result;
    return ReceiptPanel(
      key: const ValueKey('checkIn.done'),
      paymentId: r.paymentId,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_rounded, color: c.marine, size: 24),
              const SizedBox(width: Space.x8),
              Semantics(
                header: true,
                child: Text('Checked in', style: t.sectionTitle),
              ),
            ],
          ),
          const SizedBox(height: Space.x4),
          Text(
            '${saved.guestName} · '
            '${checkedInSummary(roomNumber: r.roomNumber, labels: r.labels)}',
            key: const ValueKey('checkIn.done.summary'),
            style: t.small.copyWith(color: c.inkSoft),
          ),
        ],
      ),
      actions: [
        Divider(color: c.lineSoft),
        AppButton.secondary(
          key: const ValueKey('checkIn.done.board'),
          label: 'Back to bed board',
          onPressed: onBoard,
        ),
        AppButton.secondary(
          key: const ValueKey('checkIn.done.another'),
          label: 'Check in another guest',
          onPressed: onAnother,
        ),
      ],
    );
  }
}
