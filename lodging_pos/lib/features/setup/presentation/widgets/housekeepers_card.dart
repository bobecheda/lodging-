import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/theme.dart';
import '../../../../app/widgets/buttons.dart';
import '../../../../app/widgets/labeled_field.dart';
import '../../../../app/widgets/notes.dart';
import '../../../../core/auth/permissions.dart';
import '../../../../core/auth/session.dart';
import '../../../../core/contacts/phone.dart';
import '../../data/staff_repository.dart';
import '../../domain/staff.dart';
import '../staff_providers.dart';

/// "Housekeepers" (AD-4): the list FD-9 picks from, with phones masked; add,
/// edit, deactivate and reactivate. Read-only without
/// [Permission.manageHousekeepers].
class HousekeepersCard extends ConsumerStatefulWidget {
  const HousekeepersCard({super.key});

  @override
  ConsumerState<HousekeepersCard> createState() => _HousekeepersCardState();
}

class _HousekeepersCardState extends ConsumerState<HousekeepersCard> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  var _errors = <HousekeeperField, String>{};

  /// The housekeeper being edited, with its own form.
  String? _editing;
  final _editName = TextEditingController();
  final _editPhone = TextEditingController();
  var _editErrors = <HousekeeperField, String>{};

  String? _error;
  var _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _editName, _editPhone]) {
      c.dispose();
    }
    super.dispose();
  }

  StaffRepository get _repo => ref.read(staffRepositoryProvider);

  Future<bool> _run(Future<void> Function() write) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await write();
      ref.invalidate(housekeepersListProvider);
      return true;
    } on StaffRuleViolation catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on NotPermitted {
      if (mounted) {
        setState(() => _error = 'Only the owner can manage housekeepers.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return false;
  }

  Future<void> _add() async {
    setState(
      () => _errors = housekeeperErrors(name: _name.text, phone: _phone.text),
    );
    if (_errors.isNotEmpty) return;
    final user = ref.read(sessionProvider)!;
    if (await _run(
      () => _repo.addHousekeeper(user, name: _name.text, phone: _phone.text),
    )) {
      _name.clear();
      _phone.clear();
    }
  }

  void _startEdit(Housekeeper h) => setState(() {
    _editing = h.id;
    _editName.text = h.fullName;
    _editPhone.text = h.phone ?? '';
    _editErrors = {};
    _error = null;
  });

  Future<void> _saveEdit(String id) async {
    setState(
      () => _editErrors = housekeeperErrors(
        name: _editName.text,
        phone: _editPhone.text,
      ),
    );
    if (_editErrors.isNotEmpty) return;
    final user = ref.read(sessionProvider)!;
    if (await _run(
      () => _repo.updateHousekeeper(
        user,
        id,
        name: _editName.text,
        phone: _editPhone.text,
      ),
    )) {
      setState(() => _editing = null);
    }
  }

  Future<void> _setActive(String id, {required bool active}) async {
    final user = ref.read(sessionProvider)!;
    if (await _run(
      () => active
          ? _repo.reactivateHousekeeper(user, id)
          : _repo.deactivateHousekeeper(user, id),
    )) {
      setState(() => _editing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final me = ref.watch(sessionProvider);
    final canManage = me != null && can(me, Permission.manageHousekeepers);
    final list = ref.watch(housekeepersListProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.x24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text('Housekeepers', style: t.sectionTitle),
            ),
            const SizedBox(height: Space.x4),
            Text(
              'Picked from this list when a bed is assigned. They don’t sign '
              'in.',
              style: t.small.copyWith(color: c.muted),
            ),
            const SizedBox(height: Space.x12),
            if (list case AsyncError(:final error))
              Note.error('$error', title: 'Housekeepers could not be loaded.')
            else if (list.value case final items? when items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.x8),
                child: Text('No housekeepers yet.', style: t.small),
              )
            else
              for (final h in list.value ?? const <Housekeeper>[]) ...[
                if (_editing == h.id)
                  _EditRow(
                    housekeeper: h,
                    name: _editName,
                    phone: _editPhone,
                    errors: _editErrors,
                    busy: _busy,
                    onSave: () => _saveEdit(h.id),
                    onCancel: () => setState(() => _editing = null),
                    onToggleActive: () => _setActive(h.id, active: !h.isActive),
                  )
                else
                  _HousekeeperRow(
                    housekeeper: h,
                    canManage: canManage,
                    onEdit: _busy ? null : () => _startEdit(h),
                  ),
                Divider(height: 1, color: c.lineSoft),
              ],
            if (_error != null) ...[
              const SizedBox(height: Space.x12),
              Note.error(_error!),
            ],
            if (canManage) ...[
              const SizedBox(height: Space.x20),
              LabeledField(
                label: 'Name',
                controller: _name,
                fieldKey: const ValueKey('hk.name'),
                errorText: _errors[HousekeeperField.name],
              ),
              const SizedBox(height: Space.x16),
              LabeledField(
                label: 'Phone (optional)',
                controller: _phone,
                fieldKey: const ValueKey('hk.phone'),
                keyboardType: TextInputType.phone,
                errorText: _errors[HousekeeperField.phone],
              ),
              const SizedBox(height: Space.x16),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: AppButton.secondary(
                  key: const ValueKey('hk.add'),
                  label: 'Add housekeeper',
                  busy: _busy,
                  onPressed: _add,
                ),
              ),
            ] else ...[
              const SizedBox(height: Space.x16),
              Text(
                'Only users who can manage housekeepers can change these.',
                style: t.small.copyWith(color: c.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HousekeeperRow extends StatelessWidget {
  const _HousekeeperRow({
    required this.housekeeper,
    required this.canManage,
    required this.onEdit,
  });

  final Housekeeper housekeeper;
  final bool canManage;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final h = housekeeper;
    final phone = h.phone;
    return Padding(
      key: ValueKey('hk.row.${h.id}'),
      padding: const EdgeInsets.symmetric(vertical: Space.x10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: Space.x8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      h.fullName,
                      style: t.bodyStrong.copyWith(
                        color: h.isActive ? null : c.muted,
                      ),
                    ),
                    if (!h.isActive)
                      const StatusBadge('INACTIVE', tone: BadgeTone.disabled),
                  ],
                ),
                const SizedBox(height: Space.x4),
                Text(
                  phone == null ? 'No phone recorded' : maskPhone(phone),
                  key: ValueKey('hk.phone.${h.id}'),
                  style: t.small.copyWith(color: c.muted),
                ),
              ],
            ),
          ),
          if (canManage)
            TextButton(
              key: ValueKey('hk.edit.${h.id}'),
              onPressed: onEdit,
              child: const Text('Edit'),
            ),
        ],
      ),
    );
  }
}

class _EditRow extends StatelessWidget {
  const _EditRow({
    required this.housekeeper,
    required this.name,
    required this.phone,
    required this.errors,
    required this.busy,
    required this.onSave,
    required this.onCancel,
    required this.onToggleActive,
  });

  final Housekeeper housekeeper;
  final TextEditingController name;
  final TextEditingController phone;
  final Map<HousekeeperField, String> errors;
  final bool busy;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: Space.x8),
      padding: const EdgeInsets.all(Space.x12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LabeledField(
            label: 'Name',
            controller: name,
            fieldKey: const ValueKey('hk.editName'),
            errorText: errors[HousekeeperField.name],
          ),
          const SizedBox(height: Space.x12),
          LabeledField(
            label: 'Phone (optional)',
            controller: phone,
            fieldKey: const ValueKey('hk.editPhone'),
            keyboardType: TextInputType.phone,
            errorText: errors[HousekeeperField.phone],
          ),
          const SizedBox(height: Space.x12),
          Wrap(
            spacing: Space.x8,
            runSpacing: Space.x8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppButton.primary(
                key: const ValueKey('hk.save'),
                label: 'Save',
                compact: true,
                busy: busy,
                onPressed: onSave,
              ),
              AppButton.secondary(
                key: const ValueKey('hk.cancel'),
                label: 'Cancel',
                compact: true,
                onPressed: onCancel,
              ),
              if (housekeeper.isActive)
                AppButton.destructive(
                  key: const ValueKey('hk.deactivate'),
                  label: 'Deactivate',
                  compact: true,
                  onPressed: busy ? null : onToggleActive,
                )
              else
                AppButton.secondary(
                  key: const ValueKey('hk.reactivate'),
                  label: 'Reactivate',
                  compact: true,
                  onPressed: busy ? null : onToggleActive,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
