import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/gate.dart';
import '../../../app/theme/theme.dart';
import '../../../app/widgets/buttons.dart';
import '../../../app/widgets/focus_ring.dart';
import '../../../app/widgets/labeled_field.dart';
import '../../../app/widgets/night_stepper.dart';
import '../../../app/widgets/notes.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/auth/user_account.dart';
import '../../../core/clock/nairobi.dart';
import '../../../core/contacts/phone.dart';
import '../../../core/money/kes.dart';
import '../../bed_board/presentation/bed_board_providers.dart';
import '../../guests/data/guests_repository.dart';
import '../../guests/domain/guest.dart';
import '../../guests/presentation/guests_providers.dart';
import '../../guests/presentation/widgets/guest_form_fields.dart';
import '../../payments/domain/payment_rules.dart';
import '../../receipts/presentation/receipt_view.dart';
import '../../setup/domain/rooms.dart';
import '../../shifts/domain/shift_rules.dart';
import '../../shifts/presentation/shift_providers.dart';
import '../data/check_in_repository.dart';
import '../domain/check_in.dart';
import '../domain/check_in_view.dart';
import '../domain/stay_rules.dart';
import 'check_in_bed.dart';
import 'check_in_guest.dart';
import 'check_in_providers.dart';

/// FD-4 "New check-in" with its payment (FD-5), v2 (PR 6, Figma "Desk ·
/// Check-in (full)" and "Check-in · variants"): a form card (Bed, Guest,
/// Nights, Payment) and a 360 px summary card (total, confirm line, Save
/// and print receipt, Cancel). Below about 860 px the summary sits under
/// the form. Nothing is saved until Save; then the receipt shows (FD-6),
/// with no print dialog of its own. Without an open shift of their own the
/// user sees "Open your shift first" instead of the form.
class CheckInScreen extends ConsumerStatefulWidget {
  const CheckInScreen({super.key, this.bedId});

  /// The bed to start with (a Ready tile on the board), if any.
  final String? bedId;

  @override
  ConsumerState<CheckInScreen> createState() => _CheckInScreenState();
}

/// Below this content width the summary moves under the form.
const _sideBySide = 860.0;
const _summaryWidth = 360.0;

class _CheckInScreenState extends ConsumerState<CheckInScreen> {
  String? _bedId;
  var _wholeRoom = false;

  // The guest: one search box; a found guest, or the new guest form.
  final _search = TextEditingController();
  Guest? _guest;
  final _newGuest = GuestFormControllers();
  var _newGuestMode = false;
  var _prefilled = (phone: '', idNumber: '');
  var _guestErrors = <GuestField, String>{};
  Guest? _idTaken;
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
    _search.dispose();
    _newGuest.dispose();
    _code.dispose();
    super.dispose();
  }

  void _chooseBed(String bedId) => setState(() {
    if (bedId != _bedId) _wholeRoom = false;
    _bedId = bedId;
    _problem = null;
  });

  /// The search changed: the form keeps what was typed into it, and takes
  /// the new search where it still holds the last one filled in.
  void _onSearch(String text) => setState(() {
    final p = newGuestPrefill(text);
    if (_newGuest.phone.text == _prefilled.phone) {
      _newGuest.phone.text = p.phone;
    }
    if (_newGuest.idNumber.text == _prefilled.idNumber) {
      _newGuest.idNumber.text = p.idNumber;
    }
    _prefilled = p;
    _newGuestMode = false;
    _guestErrors = {};
    _idTaken = null;
    _problem = null;
  });

  void _selectGuest(Guest g) => setState(() {
    _guest = g;
    _newGuestMode = false;
    _guestErrors = {};
    _idTaken = null;
    _phoneSeen = {};
    _problem = null;
  });

  void _clearGuest() => setState(() {
    _guest = null;
    _problem = null;
  });

  void _newGuestWithPhone() => setState(() {
    final p = newGuestPrefill(_search.text);
    if (_newGuest.phone.text.trim().isEmpty) _newGuest.phone.text = p.phone;
    _prefilled = (phone: _newGuest.phone.text, idNumber: _prefilled.idNumber);
    _newGuestMode = true;
  });

  void _restart() {
    setState(() {
      _bedId = null;
      _wholeRoom = false;
      _search.clear();
      _guest = null;
      _newGuest.clear();
      _newGuestMode = false;
      _prefilled = (phone: '', idNumber: '');
      _guestErrors = {};
      _idTaken = null;
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
    final guest = _guest;
    final GuestChoice choice;
    final String guestName;
    if (guest != null) {
      choice = ReturningGuest(guest.id);
      guestName = guest.fullName;
    } else {
      final form = _newGuest.form;
      final errors = validateGuest(form);
      if (errors.isNotEmpty) {
        setState(() {
          _guestErrors = errors;
          _idTaken = null;
        });
        return;
      }
      final phone = normalizeGuestPhone(form.phone);
      final shown = phone == null
          ? const <Guest>[]
          : ref.read(guestsWithPhoneProvider(phone, null)).value ??
                const <Guest>[];
      choice = NewGuest(
        form,
        phoneSharedWith: {..._phoneSeen, for (final g in shown) g.id},
      );
      guestName = form.normalized().fullName;
    }
    final method = _method!;
    setState(() {
      _busy = true;
      _errors = {};
      _guestErrors = {};
      _idTaken = null;
      _problem = null;
    });
    try {
      final result = await ref
          .read(checkInRepositoryProvider)
          .checkIn(
            user,
            CheckInRequest(
              guest: choice,
              method: method,
              mpesaCode: method == PaymentMethod.paybill ? _code.text : null,
              shown: quote,
            ),
          );
      if (!mounted) return;
      setState(() => _saved = _Saved(result, guestName));
    } on InvalidCheckIn catch (e) {
      if (!mounted) return;
      setState(() {
        _errors = e.errors;
        final other = {...e.errors}
          ..remove(CheckInField.mpesaCode)
          ..remove(CheckInField.nights);
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
    } on IdTaken catch (e) {
      if (mounted) setState(() => _idTaken = e.owner);
    } on InvalidGuest catch (e) {
      if (mounted) setState(() => _guestErrors = e.errors);
    } on NoOpenShift {
      if (mounted) {
        setState(() => _problem = 'Check-ins and payments need an open shift.');
      }
    } on NotPermitted {
      if (mounted) setState(() => _problem = 'You can’t check guests in.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    final user = ref.watch(sessionProvider);
    final rooms = ref.watch(checkInRoomsProvider);
    final checkout = ref.watch(checkInCheckoutTimeProvider).value;
    final now = ref.watch(boardNowProvider).value;
    final shiftState = ref.watch(currentShiftProvider);
    final saved = _saved;
    if (user == null) return const SizedBox.shrink();

    Widget page(Widget body) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('New check-in', style: t.pageTitle),
        ),
        const SizedBox(height: Space.x16),
        Expanded(child: body),
      ],
    );
    const loading = Center(child: CircularProgressIndicator());

    if (saved != null) {
      return page(
        SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: _Done(
              saved: saved,
              onBoard: () => context.go(Routes.home),
              onAnother: _restart,
            ),
          ),
        ),
      );
    }
    // Wait for the shift before saying there's none.
    if (!shiftState.hasValue) return page(loading);
    if (shiftState.value?.userId != user.id) {
      return page(
        SingleChildScrollView(
          child: _NoShift(
            canOpen: can(user, Permission.openShift),
            onOpen: () =>
                context.go(Routes.shiftThen(Routes.checkInFor(_bedId))),
            onBack: () => context.go(Routes.home),
          ),
        ),
      );
    }
    if (rooms case AsyncError(:final error)) {
      return page(
        Align(
          alignment: Alignment.topLeft,
          child: Note.error('$error', title: 'The beds could not be loaded.'),
        ),
      );
    }
    final list = rooms.value;
    if (list == null || checkout == null || now == null) return page(loading);

    // The chosen bed, its room and the room's other bed.
    RoomSummary? room;
    BedSummary? bed;
    for (final r in list) {
      for (final b in r.beds) {
        if (b.id == _bedId) (room, bed) = (r, b);
      }
    }
    final other = room?.beds.where((b) => b.id != bed!.id).firstOrNull;
    final bedProblem = bed == null
        ? null
        : letReason(bed, checkInOccupancy(bed));
    final otherFree =
        other != null && letBlocker(other, checkInOccupancy(other)) == null;
    final letting = [?bed, if (_wholeRoom && otherFree) other];

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
    final out = nightsProblem == null
        ? paidUntil(firstCheckout(now, checkout), _nights)
        : null;

    // The guest.
    final canRegister = can(user, Permission.registerGuests);
    final query = _search.text;
    final searchable = !GuestQuery.parse(query).isEmpty;
    final guest = _guest;
    final matches = searchable && guest == null
        ? ref.watch(guestSearchProvider(query)).value
        : null;
    final formShown =
        guest == null &&
        canRegister &&
        (_newGuestMode || (matches != null && matches.isEmpty));
    final readiness = guest != null
        ? GuestReadiness.ready
        : !formShown
        ? GuestReadiness.none
        : _newGuest.fullName.text.trim().isNotEmpty &&
              _newGuest.phone.text.trim().isNotEmpty
        ? GuestReadiness.ready
        : GuestReadiness.incomplete;
    final history = guest == null
        ? null
        : ref.watch(guestHistoryProvider(guest.id)).value;
    final selectedLine = guest == null
        ? ''
        : [
            spacePhone(guest.phone),
            ?guest.maskedId,
            if (history != null) stayCountLabel(history.stays),
          ].join(' · ');

    final confirm = checkInConfirm(
      quote: quote,
      bedChosen: bed != null,
      nightsProblem: nightsProblem,
      guest: readiness,
      method: _method,
    );

    final formCard = Card(
      key: const ValueKey('checkIn.form'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Space.x24,
          Space.x18,
          Space.x24,
          Space.x18,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CheckInBedSection(
              rooms: list,
              room: room,
              letting: letting,
              bedProblem: bedProblem,
              other: other,
              wholeRoom: _wholeRoom,
              onChoose: _chooseBed,
              onWholeRoom: (v) => setState(() => _wholeRoom = v),
            ),
            const SizedBox(height: Space.x14),
            CheckInGuestSection(
              search: _search,
              onSearch: _onSearch,
              matches: matches,
              selected: guest,
              selectedLine: selectedLine,
              onSelect: _selectGuest,
              onClear: _clearGuest,
              canRegister: canRegister,
              formShown: formShown,
              newGuestMode: _newGuestMode,
              onNewGuestWithPhone: _newGuestWithPhone,
              form: _newGuest,
              formErrors: _guestErrors,
              onFormChanged: () => setState(() {
                _guestErrors = {};
                _idTaken = null;
              }),
              idTaken: _idTaken,
              onUseTaken: _selectGuest,
            ),
            const SizedBox(height: Space.x14),
            _Nights(
              nights: _nights,
              out: out,
              error: nightsProblem ?? _errors[CheckInField.nights],
              onNights: (n) => setState(() {
                _nights = n;
                _nightsText = '$n';
              }),
              onTyped: (text) => setState(() {
                _nightsText = text;
                final n = parseNights(text);
                if (n != null && nightsError(n) == null) _nights = n;
              }),
            ),
            const SizedBox(height: Space.x14),
            _Payment(
              method: _method,
              onMethod: (m) => setState(() {
                _method = m;
                _errors = {..._errors}..remove(CheckInField.mpesaCode);
              }),
              code: _code,
              codeError: _errors[CheckInField.mpesaCode],
            ),
          ],
        ),
      ),
    );

    final summary = _Summary(
      quote: quote,
      lines: quote == null
          ? const []
          : checkInPriceLines(
              nights: quote.nights,
              beds: [
                for (final b in letting)
                  (bedName(room!.number, b.label), b.pricePerNight),
              ],
            ),
      confirm: confirm,
      problem: _problem,
      busy: _busy,
      onSave: confirm.ready && quote != null ? () => _save(user, quote) : null,
      onCancel: () => context.go(Routes.home),
    );

    return page(
      LayoutBuilder(
        builder: (context, box) => box.maxWidth >= _sideBySide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: formCard,
                    ),
                  ),
                  const SizedBox(width: Space.x20),
                  SizedBox(
                    width: _summaryWidth,
                    child: SingleChildScrollView(child: summary),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: formCard,
                    ),
                  ),
                  const SizedBox(height: Space.x16),
                  summary,
                ],
              ),
      ),
    );
  }
}

final class _Saved {
  const _Saved(this.result, this.guestName);
  final CheckInResult result;
  final String guestName;
}

/// "Nights": the stepper (typing allowed) and "Out Fri 13 Nov, 10:00".
class _Nights extends StatelessWidget {
  const _Nights({
    required this.nights,
    required this.out,
    required this.error,
    required this.onNights,
    required this.onTyped,
  });

  final int nights;
  final DateTime? out;
  final String? error;
  final ValueChanged<int> onNights;
  final ValueChanged<String> onTyped;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final out = this.out;
    final error = this.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Nights', style: t.sectionTitle),
        const SizedBox(height: Space.x8),
        Row(
          children: [
            NightStepper(
              value: nights,
              min: nightsRange.min,
              max: nightsRange.max,
              onChanged: onNights,
              onTyped: onTyped,
            ),
            const SizedBox(width: Space.x12),
            if (out != null)
              Flexible(
                child: Text(
                  'Out ${formatDayDateComma(out)}',
                  key: const ValueKey('checkIn.out'),
                  style: t.body,
                ),
              ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: Space.x6),
          Text(
            error,
            key: const ValueKey('checkIn.nightsError'),
            style: t.secondary.copyWith(color: c.redText),
          ),
        ],
      ],
    );
  }
}

/// "Payment": Cash / M-Pesa with none chosen; the chosen one solid marine
/// with white text (the brief: stronger than other selections, as the wrong
/// method is the most common mistake). The M-Pesa code only for M-Pesa.
class _Payment extends StatelessWidget {
  const _Payment({
    required this.method,
    required this.onMethod,
    required this.code,
    required this.codeError,
  });

  final PaymentMethod? method;
  final ValueChanged<PaymentMethod> onMethod;
  final TextEditingController code;
  final String? codeError;

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Payment', style: t.sectionTitle),
        const SizedBox(height: Space.x8),
        Row(
          children: [
            for (final (i, m) in PaymentMethod.values.indexed) ...[
              if (i > 0) const SizedBox(width: Space.x12),
              Expanded(
                child: _MethodButton(
                  method: m,
                  chosen: m == method,
                  onTap: () => onMethod(m),
                ),
              ),
            ],
          ],
        ),
        if (method == PaymentMethod.paybill) ...[
          const SizedBox(height: Space.x12),
          LabeledField(
            label: 'M-Pesa code',
            controller: code,
            fieldKey: const ValueKey('checkIn.mpesaCode'),
            textStyle: t.moneySmall,
            errorText: codeError,
          ),
        ],
      ],
    );
  }
}

class _MethodButton extends StatelessWidget {
  const _MethodButton({
    required this.method,
    required this.chosen,
    required this.onTap,
  });

  final PaymentMethod method;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: chosen,
      button: true,
      label: method.label,
      excludeSemantics: true,
      child: FocusRing(
        radius: Radii.control,
        child: Material(
          color: chosen ? c.marine : c.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.control),
            side: BorderSide(color: chosen ? c.marine : c.fieldBorder),
          ),
          child: InkWell(
            key: ValueKey('choice.$method'),
            borderRadius: BorderRadius.circular(Radii.control),
            onTap: onTap,
            child: SizedBox(
              height: 48,
              child: Center(
                child: Text(
                  method.label,
                  style: t.body.copyWith(
                    color: chosen ? c.white : c.ink,
                    fontWeight: chosen ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The summary card: Total, the price lines, the confirm line, a refusal if
/// any, Save and print receipt, Cancel.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.quote,
    required this.lines,
    required this.confirm,
    required this.problem,
    required this.busy,
    required this.onSave,
    required this.onCancel,
  });

  final CheckInQuote? quote;
  final List<String> lines;
  final CheckInConfirm confirm;
  final String? problem;
  final bool busy;
  final VoidCallback? onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final quote = this.quote;
    final problem = this.problem;
    return Card(
      key: const ValueKey('checkIn.summary'),
      child: Padding(
        padding: const EdgeInsets.all(Space.x24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Total', style: t.secondary.copyWith(color: c.muted)),
            const SizedBox(height: Space.x10),
            Text(
              quote == null ? '—' : formatKes(quote.total),
              key: const ValueKey('checkIn.total'),
              style: t.moneyHero,
            ),
            for (final (i, line) in lines.indexed) ...[
              SizedBox(height: i == 0 ? Space.x10 : Space.x4),
              Text(
                line,
                key: ValueKey('checkIn.priceLine.$i'),
                style: t.secondary.copyWith(color: c.inkSoft),
              ),
            ],
            const SizedBox(height: Space.x14),
            Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(
                horizontal: Space.x14,
                vertical: Space.x10,
              ),
              alignment: AlignmentDirectional.centerStart,
              decoration: BoxDecoration(
                color: confirm.ready ? c.marineTint : c.surface,
                borderRadius: BorderRadius.circular(Radii.control),
              ),
              child: Text(
                confirm.text,
                key: const ValueKey('checkIn.confirmLine'),
                style: t.body.copyWith(color: confirm.ready ? c.ink : c.muted),
              ),
            ),
            if (problem != null) ...[
              const SizedBox(height: Space.x14),
              Note.error(problem, key: const ValueKey('checkIn.problem')),
            ],
            const SizedBox(height: Space.x14),
            AppButton.primary(
              key: const ValueKey('checkIn.save'),
              label: 'Save and print receipt',
              busy: busy,
              onPressed: onSave,
            ),
            const SizedBox(height: Space.x14),
            AppButton.secondary(
              key: const ValueKey('checkIn.cancel'),
              label: 'Cancel',
              onPressed: onCancel,
            ),
          ],
        ),
      ),
    );
  }
}

/// No open shift of their own (Figma "No open shift"): a centred card
/// instead of the form.
class _NoShift extends StatelessWidget {
  const _NoShift({
    required this.canOpen,
    required this.onOpen,
    required this.onBack,
  });

  final bool canOpen;
  final VoidCallback onOpen;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Card(
          key: const ValueKey('checkIn.noShift'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.x24,
              Space.x28,
              Space.x24,
              Space.x24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.butter,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      LucideIcons.clock,
                      size: 22,
                      color: c.butterText,
                    ),
                  ),
                ),
                const SizedBox(height: Space.x14),
                Text(
                  'Open your shift first',
                  textAlign: TextAlign.center,
                  style: t.sectionTitle,
                ),
                const SizedBox(height: Space.x12),
                Text(
                  'Check-ins and payments need an open shift.',
                  textAlign: TextAlign.center,
                  style: t.secondary.copyWith(color: c.inkSoft),
                ),
                const SizedBox(height: Space.x14),
                if (canOpen) ...[
                  AppButton.primary(
                    key: const ValueKey('checkIn.openShift'),
                    label: 'Open shift',
                    onPressed: onOpen,
                  ),
                  const SizedBox(height: Space.x14),
                ],
                AppButton.secondary(
                  key: const ValueKey('checkIn.backToBeds'),
                  label: 'Back to beds',
                  onPressed: onBack,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// After saving (not redesigned): the receipt (FD-6), with Print as the
/// main button. No print dialog opens by itself.
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
              Icon(LucideIcons.circleCheck, color: c.marine, size: 24),
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
            style: t.secondary.copyWith(color: c.inkSoft),
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
