import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/theme.dart';
import '../../../app/widgets/buttons.dart';
import '../../../app/widgets/focus_ring.dart';
import '../../../app/widgets/labeled_field.dart';
import '../../../app/widgets/notes.dart';
import '../../../core/contacts/phone.dart';
import '../../guests/domain/guest.dart';
import '../../guests/presentation/guests_providers.dart';
import '../../guests/presentation/widgets/guest_form_fields.dart';

/// "Guest" on the v2 check-in (PR 6, Figma "Desk · Check-in (full)" and
/// "New guest (no match)"): one search box for a phone or ID number. Matches
/// list with masked phones and IDs; the chosen guest shows the full phone
/// (to confirm it with them) and "Not this guest". No match opens the new
/// guest form, which check-in saves with the stay; "New guest with this
/// phone" opens it beside matches (families share phones). The screen holds
/// the state; this only shows it.
class CheckInGuestSection extends ConsumerWidget {
  const CheckInGuestSection({
    super.key,
    required this.search,
    required this.onSearch,
    required this.matches,
    required this.selected,
    required this.selectedLine,
    required this.onSelect,
    required this.onClear,
    required this.canRegister,
    required this.formShown,
    required this.newGuestMode,
    required this.onNewGuestWithPhone,
    required this.form,
    required this.formErrors,
    required this.onFormChanged,
    required this.idTaken,
    required this.onUseTaken,
  });

  final TextEditingController search;
  final ValueChanged<String> onSearch;

  /// The matches for a searchable entry once loaded; null otherwise.
  final List<Guest>? matches;
  final Guest? selected;

  /// Under the chosen guest's name: full phone, masked ID, stay count.
  final String selectedLine;
  final ValueChanged<Guest> onSelect;
  final VoidCallback onClear;
  final bool canRegister;
  final bool formShown;
  final bool newGuestMode;
  final VoidCallback onNewGuestWithPhone;
  final GuestFormControllers form;
  final Map<GuestField, String> formErrors;
  final VoidCallback onFormChanged;

  /// The guest who already has the typed ID, after a save was refused.
  final Guest? idTaken;
  final ValueChanged<Guest> onUseTaken;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final selected = this.selected;
    final matches = this.matches;
    final typed = search.text.trim().isNotEmpty;
    final searchable = !GuestQuery.parse(search.text).isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Guest', style: t.sectionTitle),
        const SizedBox(height: Space.x8),
        LabeledField(
          label: null,
          semanticLabel: 'Find the guest by phone or ID number',
          controller: search,
          fieldKey: const ValueKey('checkIn.guestSearch'),
          hintText: '0722 418 905 or 12345678',
          prefix: Padding(
            padding: const EdgeInsetsDirectional.only(
              start: Space.x14,
              end: Space.x10,
            ),
            child: Icon(LucideIcons.search, size: 18, color: c.muted),
          ),
          onChanged: onSearch,
        ),
        if (selected != null) ...[
          const SizedBox(height: Space.x10),
          _SelectedGuest(guest: selected, line: selectedLine, onClear: onClear),
        ] else ...[
          if (typed && !searchable) ...[
            const SizedBox(height: Space.x8),
            Text(
              'Keep typing: at least 3 digits of a phone, or 3 characters of '
              'an ID number.',
              key: const ValueKey('checkIn.keepTyping'),
              style: t.secondary.copyWith(color: c.muted),
            ),
          ],
          if (matches != null && matches.isNotEmpty) ...[
            const SizedBox(height: Space.x8),
            for (final g in matches)
              _MatchRow(guest: g, onTap: () => onSelect(g)),
            if (canRegister && !newGuestMode)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const ValueKey('checkIn.newGuestWithPhone'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, Sizes.target),
                  ),
                  onPressed: onNewGuestWithPhone,
                  icon: const Icon(LucideIcons.userPlus, size: 18),
                  label: const Text('New guest with this phone'),
                ),
              ),
          ],
          if (matches != null && matches.isEmpty) ...[
            const SizedBox(height: Space.x10),
            Text(
              canRegister
                  ? 'No guest with this phone or ID — new guest'
                  : 'No guest with this phone or ID.',
              key: const ValueKey('checkIn.noMatch'),
              style: t.secondary.copyWith(color: c.muted),
            ),
          ],
          if (formShown) ...[
            const SizedBox(height: Space.x14),
            _NewGuestForm(
              form: form,
              errors: formErrors,
              onChanged: onFormChanged,
              idTaken: idTaken,
              onUseTaken: onUseTaken,
            ),
          ],
        ],
      ],
    );
  }
}

/// A match while typing: name, then the masked phone and ID.
class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.guest, required this.onTap});

  final Guest guest;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.x6),
      child: FocusRing(
        radius: Radii.control,
        child: Material(
          color: c.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.control),
            side: BorderSide(color: c.line),
          ),
          child: InkWell(
            key: ValueKey('checkIn.match.${guest.id}'),
            borderRadius: BorderRadius.circular(Radii.control),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.x12,
                vertical: Space.x8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(guest.fullName, style: t.bodyMedium),
                        Text(
                          [maskPhone(guest.phone), ?guest.maskedId].join(' · '),
                          style: t.secondary.copyWith(color: c.muted),
                        ),
                      ],
                    ),
                  ),
                  Icon(LucideIcons.chevronRight, size: 18, color: c.muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The chosen guest: a marine-tint row with a check, the name, the full
/// phone, the masked ID and the stay count, and "Not this guest".
class _SelectedGuest extends StatelessWidget {
  const _SelectedGuest({
    required this.guest,
    required this.line,
    required this.onClear,
  });

  final Guest guest;
  final String line;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    return Container(
      key: const ValueKey('checkIn.guest'),
      padding: const EdgeInsetsDirectional.only(
        start: Space.x12,
        top: Space.x6,
        bottom: Space.x6,
        end: Space.x4,
      ),
      decoration: BoxDecoration(
        color: c.marineTint,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Row(
        children: [
          Container(
            width: Sizes.avatar,
            height: Sizes.avatar,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.white, shape: BoxShape.circle),
            child: Icon(LucideIcons.check, size: 18, color: c.marine),
          ),
          const SizedBox(width: Space.x12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(guest.fullName, style: t.bodyMedium),
                Text(
                  line,
                  key: const ValueKey('checkIn.guest.line'),
                  style: t.secondary.copyWith(color: c.inkSoft),
                ),
              ],
            ),
          ),
          TextButton(
            key: const ValueKey('checkIn.notThisGuest'),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, Sizes.target),
            ),
            onPressed: onClear,
            child: const Text('Not this guest'),
          ),
        ],
      ),
    );
  }
}

/// Phone and Full name side by side, then "ID (optional)": National ID /
/// Passport / Alien ID (none chosen until tapped) and the number.
class _NewGuestForm extends ConsumerWidget {
  const _NewGuestForm({
    required this.form,
    required this.errors,
    required this.onChanged,
    required this.idTaken,
    required this.onUseTaken,
  });

  final GuestFormControllers form;
  final Map<GuestField, String> errors;
  final VoidCallback onChanged;
  final Guest? idTaken;
  final ValueChanged<Guest> onUseTaken;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final phone = normalizeGuestPhone(form.phone.text);
    final shared = phone == null
        ? const <Guest>[]
        : ref.watch(guestsWithPhoneProvider(phone, null)).value ??
              const <Guest>[];
    final taken = idTaken;

    return Column(
      key: const ValueKey('checkIn.newGuest'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LabeledField(
                label: 'Phone',
                controller: form.phone,
                fieldKey: const ValueKey('checkIn.newGuest.phone'),
                keyboardType: TextInputType.phone,
                errorText: errors[GuestField.phone],
                onChanged: (_) => onChanged(),
              ),
            ),
            const SizedBox(width: Space.x12),
            Expanded(
              child: LabeledField(
                label: 'Full name',
                controller: form.fullName,
                fieldKey: const ValueKey('checkIn.newGuest.fullName'),
                errorText: errors[GuestField.fullName],
                onChanged: (_) => onChanged(),
              ),
            ),
          ],
        ),
        if (shared.isNotEmpty) ...[
          const SizedBox(height: Space.x8),
          Note.info(
            'Already registered with this phone: '
            '${shared.map((g) => g.fullName).join(', ')}. Check it isn’t the '
            'same person.',
            key: const ValueKey('checkIn.sharedPhone'),
          ),
        ],
        const SizedBox(height: Space.x14),
        Text('ID (optional)', style: t.secondaryMedium),
        const SizedBox(height: Space.x6),
        Row(
          children: [
            for (final (i, type) in IdType.values.indexed) ...[
              if (i > 0) const SizedBox(width: Space.x8),
              Expanded(
                child: _IdTypeChip(
                  type: type,
                  chosen: form.idType == type,
                  onTap: () {
                    form.idType = form.idType == type ? null : type;
                    onChanged();
                  },
                ),
              ),
            ],
          ],
        ),
        if (errors[GuestField.idType] case final error?) ...[
          const SizedBox(height: Space.x6),
          Text(
            error,
            key: const ValueKey('checkIn.newGuest.idTypeError'),
            style: t.secondary.copyWith(color: c.redText),
          ),
        ],
        const SizedBox(height: Space.x12),
        LabeledField(
          label: 'ID number',
          controller: form.idNumber,
          fieldKey: const ValueKey('checkIn.newGuest.idNumber'),
          errorText: taken == null ? errors[GuestField.idNumber] : null,
          onChanged: (_) => onChanged(),
        ),
        if (taken != null) ...[
          const SizedBox(height: Space.x8),
          Row(
            children: [
              Expanded(
                child: Text(
                  idTakenMessage(taken),
                  key: const ValueKey('checkIn.idTaken'),
                  style: t.secondary.copyWith(color: c.redText),
                ),
              ),
              const SizedBox(width: Space.x12),
              AppButton.secondary(
                key: const ValueKey('checkIn.useTakenGuest'),
                label: 'Use this guest',
                compact: true,
                onPressed: () => onUseTaken(taken),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _IdTypeChip extends StatelessWidget {
  const _IdTypeChip({
    required this.type,
    required this.chosen,
    required this.onTap,
  });

  final IdType type;
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
      label: type.label,
      excludeSemantics: true,
      child: FocusRing(
        radius: Radii.control,
        child: InkWell(
          key: ValueKey('checkIn.idType.${type.code}'),
          borderRadius: BorderRadius.circular(Radii.control),
          onTap: onTap,
          child: Container(
            key: chosen ? ValueKey('checkIn.idType.${type.code}.on') : null,
            height: Sizes.target,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: chosen ? c.marineTint : c.white,
              borderRadius: BorderRadius.circular(Radii.control),
              border: Border.all(
                color: chosen ? c.marine : c.fieldBorder,
                width: chosen ? Sizes.borderStrong : Sizes.borderThin,
              ),
            ),
            child: Text(
              type.label,
              style: t.secondaryMedium.copyWith(
                color: chosen ? c.marine : c.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
