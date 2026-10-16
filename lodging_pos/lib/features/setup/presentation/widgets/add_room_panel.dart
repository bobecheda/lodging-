import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/theme.dart';
import '../../../../app/widgets/buttons.dart';
import '../../../../app/widgets/labeled_dropdown.dart';
import '../../../../app/widgets/labeled_field.dart';
import '../../../../app/widgets/notes.dart';
import '../../../../app/widgets/segmented_choice.dart';
import '../../../../core/auth/session.dart';
import '../../domain/rooms.dart';
import '../rooms_providers.dart';
import 'panel_parts.dart';

/// Adds a room with 1 or 2 beds (`room.create` + `bed.create`).
class AddRoomPanel extends ConsumerStatefulWidget {
  const AddRoomPanel({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  ConsumerState<AddRoomPanel> createState() => _AddRoomPanelState();
}

class _AddRoomPanelState extends ConsumerState<AddRoomPanel> {
  final _number = TextEditingController();
  final _floor = TextEditingController();
  var _bedCount = 1;
  String? _bedA;
  String? _bedB;
  var _errors = <RoomField, String>{};
  String? _error;
  var _busy = false;

  @override
  void dispose() {
    _number.dispose();
    _floor.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final errors = <RoomField, String>{
      RoomField.number: ?roomNumberError(_number.text),
      if (_bedA == null) RoomField.bedA: 'Choose a category',
      if (_bedCount == 2 && _bedB == null) RoomField.bedB: 'Choose a category',
    };
    setState(() {
      _errors = errors;
      _error = null;
    });
    if (errors.isNotEmpty) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(roomsRepositoryProvider)
          .createRoom(
            ref.read(sessionProvider)!,
            NewRoom(
              number: _number.text,
              floor: _floor.text,
              notes: null,
              bedACategoryId: _bedA!,
              bedBCategoryId: _bedCount == 2 ? _bedB : null,
            ),
          );
      ref.invalidate(roomsListProvider);
      widget.onDone();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (e is InvalidRoom) _errors = e.errors;
        _error = panelError(e);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    final categories = ref.watch(bedCategoriesProvider).value ?? const [];
    final options = categoryOptions(categories);

    Widget bedRow(BedLabel label, String? value, ValueChanged<String> set) =>
        Padding(
          padding: const EdgeInsets.only(bottom: Space.x12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              BedLetter(label),
              const SizedBox(width: Space.x12),
              Expanded(
                child: LabeledDropdown<String>(
                  fieldKey: ValueKey('add.bed${label.code}'),
                  label: 'Bed ${label.code} category',
                  options: options,
                  value: value,
                  errorText:
                      _errors[label == BedLabel.a
                          ? RoomField.bedA
                          : RoomField.bedB],
                  onChanged: (v) => setState(() => set(v)),
                ),
              ),
            ],
          ),
        );

    return SidePanel(
      title: 'Add a room',
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LabeledField(
                label: 'Room number',
                controller: _number,
                fieldKey: const ValueKey('add.number'),
                autofocus: true,
                errorText: _errors[RoomField.number],
              ),
            ),
            const SizedBox(width: Space.x12),
            Expanded(
              child: LabeledField(
                label: 'Floor (optional)',
                controller: _floor,
                fieldKey: const ValueKey('add.floor'),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.x20),
        Text('Beds in this room', style: t.fieldLabel),
        const SizedBox(height: Space.x6),
        SegmentedChoice<int>(
          options: const [ChoiceOption(1, '1 bed'), ChoiceOption(2, '2 beds')],
          selected: _bedCount,
          onChanged: (n) => setState(() => _bedCount = n),
        ),
        const SizedBox(height: Space.x16),
        bedRow(BedLabel.a, _bedA, (v) => _bedA = v),
        if (_bedCount == 2) bedRow(BedLabel.b, _bedB, (v) => _bedB = v),
        Text('New beds start as ready to let (clean).', style: t.small),
        const SizedBox(height: Space.x16),
        if (_error != null) ...[
          Note.error(_error!),
          const SizedBox(height: Space.x16),
        ],
        Row(
          children: [
            Expanded(
              child: AppButton.primary(
                key: const ValueKey('add.save'),
                label: 'Add room',
                busy: _busy,
                onPressed: _save,
              ),
            ),
            const SizedBox(width: Space.x12),
            AppButton.secondary(
              key: const ValueKey('add.cancel'),
              label: 'Cancel',
              onPressed: widget.onDone,
            ),
          ],
        ),
      ],
    );
  }
}
