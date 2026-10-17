import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/theme.dart';
import '../../../../app/widgets/buttons.dart';
import '../../../../app/widgets/labeled_field.dart';
import '../../../../app/widgets/notes.dart';
import '../../../../core/auth/permissions.dart';
import '../../../../core/auth/session.dart';
import '../../../../core/clock/nairobi.dart';
import '../../../../core/contacts/phone.dart';
import '../../data/guests_repository.dart';
import '../../domain/guest.dart';
import '../guests_providers.dart';
import 'guest_form_fields.dart';

/// "Guest" (FD-3): find a guest by phone or ID number as you type, or
/// register a new one. Reused by check-in (FD-4).
///
/// With [showRecent] (the Guests screen) the card fills its height: an
/// empty search box shows the 30 most recent guests in a lazy list, and
/// typing replaces them with the matches. Lists mask the phone; only the
/// selected guest's card ([showSelected]) shows it in full.
class GuestFinderCard extends ConsumerStatefulWidget {
  const GuestFinderCard({
    super.key,
    required this.selected,
    required this.onSelected,
    this.showRecent = false,
    this.showSelected = true,
  });

  final Guest? selected;
  final ValueChanged<Guest> onSelected;
  final bool showRecent;
  final bool showSelected;

  @override
  ConsumerState<GuestFinderCard> createState() => _GuestFinderCardState();
}

class _GuestFinderCardState extends ConsumerState<GuestFinderCard> {
  final _search = TextEditingController();
  final _new = GuestFormControllers();
  var _registering = false;

  /// The guest registered from this card, shown as NEW rather than
  /// RETURNING.
  String? _registeredId;
  var _errors = <GuestField, String>{};
  String? _error;
  var _busy = false;

  @override
  void dispose() {
    _search.dispose();
    _new.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final input = _new.form;
    setState(() {
      _errors = validateGuest(input);
      _error = null;
    });
    if (_errors.isNotEmpty) return;
    setState(() => _busy = true);
    try {
      final guest = await ref
          .read(guestsRepositoryProvider)
          .register(ref.read(sessionProvider)!, input);
      _new.clear();
      if (!mounted) return;
      setState(() {
        _registering = false;
        _registeredId = guest.id;
      });
      widget.onSelected(guest);
    } on InvalidGuest catch (e) {
      if (mounted) setState(() => _errors = e.errors);
    } on NotPermitted {
      if (mounted) setState(() => _error = 'You can’t register guests.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final me = ref.watch(sessionProvider);
    final canRegister = me != null && can(me, Permission.registerGuests);
    final selected = widget.selected;
    final fill = widget.showRecent;

    final header = <Widget>[
      Text('GUEST', style: t.capsLabel.copyWith(color: c.muted)),
      const SizedBox(height: Space.x12),
      LabeledField(
        label: 'Find by phone or ID number',
        controller: _search,
        fieldKey: const ValueKey('guests.search'),
        hintText: '0722 418 905 or 12345678',
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: Space.x8),
    ];

    final registerForm = <Widget>[
      Text('Register a new guest', style: t.bodyStrong),
      const SizedBox(height: Space.x12),
      GuestFormFields(
        controllers: _new,
        errors: _errors,
        keyPrefix: 'newGuest',
      ),
      if (_error != null) ...[
        const SizedBox(height: Space.x12),
        Note.error(_error!),
      ],
      const SizedBox(height: Space.x16),
      Wrap(
        spacing: Space.x12,
        runSpacing: Space.x8,
        children: [
          AppButton.primary(
            key: const ValueKey('newGuest.save'),
            label: 'Register guest',
            busy: _busy,
            onPressed: _register,
          ),
          AppButton.secondary(
            key: const ValueKey('newGuest.cancel'),
            label: 'Cancel',
            onPressed: () => setState(() {
              _registering = false;
              _errors = {};
            }),
          ),
        ],
      ),
    ];

    final registerLink = <Widget>[
      if (canRegister) ...[
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const ValueKey('guests.register'),
            onPressed: () => setState(() => _registering = true),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(
              selected == null
                  ? 'Register a new guest'
                  : 'Register a new guest instead',
            ),
          ),
        ),
        const SizedBox(height: Space.x4),
        Text(
          'New guests: full name and phone required. ID is optional.',
          style: t.small,
        ),
      ],
    ];

    final Widget body;
    if (fill) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...header,
          Expanded(
            child: _registering
                ? SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Divider(color: c.lineSoft),
                        ...registerForm,
                      ],
                    ),
                  )
                : _GuestList(
                    query: _search.text,
                    selectedId: selected?.id,
                    onSelected: widget.onSelected,
                  ),
          ),
          if (!_registering) ...[
            const SizedBox(height: Space.x8),
            ...registerLink,
          ],
        ],
      );
    } else {
      final query = _search.text;
      final searching = !GuestQuery.parse(query).isEmpty;
      final matches = searching
          ? ref.watch(guestSearchProvider(query)).value ?? const <Guest>[]
          : const <Guest>[];
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...header,
          if (searching && matches.isEmpty) const _NoMatch(),
          for (final g in matches)
            GuestTile(
              guest: g,
              selected: g.id == selected?.id,
              onTap: () => widget.onSelected(g),
            ),
          if (selected != null && widget.showSelected) ...[
            const SizedBox(height: Space.x12),
            SelectedGuestCard(
              guest: selected,
              isNew: selected.id == _registeredId,
            ),
          ],
          const SizedBox(height: Space.x12),
          if (_registering) ...[
            Divider(color: c.lineSoft),
            const SizedBox(height: Space.x8),
            ...registerForm,
          ] else
            ...registerLink,
        ],
      );
    }

    return Card(
      child: Padding(padding: const EdgeInsets.all(Space.x24), child: body),
    );
  }
}

/// The lazy list under the search box: recent guests when it's empty, the
/// matches once something searchable is typed.
class _GuestList extends ConsumerWidget {
  const _GuestList({
    required this.query,
    required this.selectedId,
    required this.onSelected,
  });

  final String query;
  final String? selectedId;
  final ValueChanged<Guest> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final typed = query.trim().isNotEmpty;
    final searching = !GuestQuery.parse(query).isEmpty;
    if (typed && !searching) {
      return Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.x8),
          child: Text(
            'Keep typing: at least 3 digits of a phone, or 3 characters of an '
            'ID number.',
            key: const ValueKey('guests.keepTyping'),
            style: t.small,
          ),
        ),
      );
    }
    final source = searching
        ? ref.watch(guestSearchProvider(query))
        : ref.watch(recentGuestsProvider);
    final guests = source.value;

    if (source case AsyncError(:final error)) {
      return Note.error('$error', title: 'Guests could not be loaded.');
    }
    if (guests == null) return const SizedBox.shrink();
    if (guests.isEmpty) {
      return searching
          ? const Align(alignment: Alignment.topLeft, child: _NoMatch())
          : Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.x8),
                child: Text(
                  'No guests yet. Register one with the form, or during '
                  'check-in.',
                  key: const ValueKey('guests.empty'),
                  style: t.small,
                ),
              ),
            );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!searching) ...[
          Text(
            'Recent guests',
            key: const ValueKey('guests.recentTitle'),
            style: t.smallStrong,
          ),
          const SizedBox(height: Space.x4),
        ],
        Expanded(
          child: ListView.builder(
            key: ValueKey(searching ? 'guests.matches' : 'guests.recent'),
            itemCount: guests.length,
            itemBuilder: (context, i) => GuestTile(
              guest: guests[i],
              selected: guests[i].id == selectedId,
              showRegistered: true,
              onTap: () => onSelected(guests[i]),
            ),
          ),
        ),
        if (!searching) ...[
          const SizedBox(height: Space.x8),
          Text(
            'Showing the ${GuestsRepository.recentLimit} most recent. Search '
            'by phone or ID to find others.',
            key: const ValueKey('guests.recentNote'),
            style: t.small.copyWith(color: c.muted),
          ),
        ],
      ],
    );
  }
}

class _NoMatch extends StatelessWidget {
  const _NoMatch();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.x8),
    child: Text(
      'No guest found.',
      key: const ValueKey('guests.none'),
      style: LodgingType.of(context).small,
    ),
  );
}

/// One guest in a list: name, masked phone, masked ID, and (in the Guests
/// screen's list) the registration date.
class GuestTile extends StatelessWidget {
  const GuestTile({
    super.key,
    required this.guest,
    required this.selected,
    required this.onTap,
    this.showRegistered = false,
  });

  final Guest guest;
  final bool selected;
  final VoidCallback onTap;
  final bool showRegistered;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final id = guest.maskedId;
    return Material(
      color: selected ? c.marineTint : c.white,
      borderRadius: BorderRadius.circular(Radii.control),
      child: InkWell(
        key: ValueKey('guests.match.${guest.id}'),
        borderRadius: BorderRadius.circular(Radii.control),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.x12,
            vertical: Space.x10,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(guest.fullName, style: t.bodyStrong),
                    Text(
                      [maskPhone(guest.phone), ?id].join(' · '),
                      style: t.small.copyWith(color: c.muted),
                    ),
                  ],
                ),
              ),
              if (showRegistered) ...[
                const SizedBox(width: Space.x8),
                Text(
                  'Registered ${formatDayDate(guest.registeredAt)}',
                  style: t.small.copyWith(color: c.muted),
                ),
              ],
              Icon(Icons.chevron_right_rounded, color: c.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// The chosen guest: full phone (to confirm with them), ID still masked.
class SelectedGuestCard extends StatelessWidget {
  const SelectedGuestCard({
    super.key,
    required this.guest,
    this.isNew = false,
    this.showBadge = true,
  });

  final Guest guest;

  /// Just registered: NEW instead of RETURNING.
  final bool isNew;

  /// RETURNING / NEW matter at check-in, not on the Guests screen.
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final id = guest.maskedId;
    return Container(
      key: const ValueKey('guests.selected'),
      padding: const EdgeInsets.all(Space.x16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.marine, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(guest.fullName, style: t.sectionTitle)),
              if (showBadge)
                StatusBadge(
                  isNew ? 'NEW' : 'RETURNING',
                  key: const ValueKey('guests.selected.badge'),
                  tone: isNew ? BadgeTone.neutral : BadgeTone.active,
                ),
            ],
          ),
          const SizedBox(height: Space.x6),
          Text(
            [_spaced(guest.phone), ?id].join(' · '),
            style: t.body.copyWith(color: c.inkSoft),
          ),
        ],
      ),
    );
  }

  /// `0722 418 905`; international numbers as stored.
  static String _spaced(String phone) => phone.length == 10
      ? '${phone.substring(0, 4)} ${phone.substring(4, 7)} '
            '${phone.substring(7)}'
      : phone;
}
