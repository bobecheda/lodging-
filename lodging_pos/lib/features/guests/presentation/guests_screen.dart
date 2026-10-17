import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/theme.dart';
import '../../../app/widgets/buttons.dart';
import '../../../app/widgets/notes.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../data/guests_repository.dart';
import '../domain/guest.dart';
import 'guests_providers.dart';
import 'widgets/guest_finder_card.dart';
import 'widgets/guest_form_fields.dart';

/// FD-3 "Guests": find a guest, open them, correct their details. Kept
/// minimal: no stay history here.
class GuestsScreen extends ConsumerStatefulWidget {
  const GuestsScreen({super.key});

  @override
  ConsumerState<GuestsScreen> createState() => _GuestsScreenState();
}

class _GuestsScreenState extends ConsumerState<GuestsScreen> {
  String? _openId;

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    final id = _openId;
    final open = id == null ? null : ref.watch(guestByIdProvider(id)).value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text('Guests', style: t.pageTitle)),
        const SizedBox(height: Space.x20),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Fills the height: its recent list scrolls lazily.
              Expanded(
                child: GuestFinderCard(
                  selected: open,
                  showRecent: true,
                  showSelected: false,
                  onSelected: (g) => setState(() => _openId = g.id),
                ),
              ),
              const SizedBox(width: Space.x24),
              Expanded(
                child: SingleChildScrollView(
                  child: open == null
                      ? const Card(
                          child: Padding(
                            padding: EdgeInsets.all(Space.x24),
                            child: Note.info(
                              'Pick a guest from the list, or search by phone '
                              'or ID number, to see and correct their '
                              'details.',
                            ),
                          ),
                        )
                      : _CorrectDetails(
                          key: ValueKey('correct.${open.id}'),
                          guest: open,
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Corrects a guest's name, phone or ID (`guest.update`). The ID number is
/// shown in full only after choosing to correct details.
class _CorrectDetails extends ConsumerStatefulWidget {
  const _CorrectDetails({super.key, required this.guest});

  final Guest guest;

  @override
  ConsumerState<_CorrectDetails> createState() => _CorrectDetailsState();
}

class _CorrectDetailsState extends ConsumerState<_CorrectDetails> {
  GuestFormControllers? _form;
  var _errors = <GuestField, String>{};
  String? _error;
  String? _saved;
  var _busy = false;

  @override
  void dispose() {
    _form?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final form = _form!;
    final input = form.form;
    setState(() {
      _errors = validateGuest(input);
      _error = null;
    });
    if (_errors.isNotEmpty) return;
    setState(() => _busy = true);
    try {
      final changed = await ref
          .read(guestsRepositoryProvider)
          .update(ref.read(sessionProvider)!, widget.guest.id, input);
      // The opened guest, the list and any matches are watched queries:
      // they show the change by themselves.
      if (!mounted) return;
      setState(() {
        _saved = changed ? 'Details saved.' : 'Nothing to save.';
        _form?.dispose();
        _form = null;
      });
    } on InvalidGuest catch (e) {
      if (mounted) setState(() => _errors = e.errors);
    } on NotPermitted {
      if (mounted) setState(() => _error = 'You can’t change guest details.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final me = ref.watch(sessionProvider);
    final canEdit = me != null && can(me, Permission.registerGuests);
    final form = _form;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.x24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('DETAILS', style: t.capsLabel.copyWith(color: c.muted)),
            const SizedBox(height: Space.x12),
            if (form == null) ...[
              SelectedGuestCard(guest: widget.guest, showBadge: false),
              if (_saved != null) ...[
                const SizedBox(height: Space.x12),
                Text(
                  _saved!,
                  key: const ValueKey('correct.saved'),
                  style: t.small,
                ),
              ],
              if (canEdit) ...[
                const SizedBox(height: Space.x16),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AppButton.secondary(
                    key: const ValueKey('correct.open'),
                    label: 'Correct details',
                    onPressed: () => setState(() {
                      _form = GuestFormControllers(widget.guest);
                      _saved = null;
                      _errors = {};
                    }),
                  ),
                ),
              ],
            ] else ...[
              GuestFormFields(
                controllers: form,
                errors: _errors,
                keyPrefix: 'correct',
                exceptGuestId: widget.guest.id,
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
                    key: const ValueKey('correct.save'),
                    label: 'Save changes',
                    busy: _busy,
                    onPressed: _save,
                  ),
                  AppButton.secondary(
                    key: const ValueKey('correct.cancel'),
                    label: 'Cancel',
                    onPressed: () => setState(() {
                      _form?.dispose();
                      _form = null;
                    }),
                  ),
                ],
              ),
              const SizedBox(height: Space.x12),
              Text(
                'Every change is recorded in the audit trail.',
                style: t.small.copyWith(color: c.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
