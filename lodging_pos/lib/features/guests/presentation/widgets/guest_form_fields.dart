import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/theme.dart';
import '../../../../app/widgets/labeled_dropdown.dart';
import '../../../../app/widgets/labeled_field.dart';
import '../../../../app/widgets/notes.dart';
import '../../../../core/contacts/phone.dart';
import '../../domain/guest.dart';
import '../guests_providers.dart';

/// The guest form's inputs, shared by register and correct-details.
class GuestFormControllers {
  GuestFormControllers([Guest? guest])
    : fullName = TextEditingController(text: guest?.fullName),
      phone = TextEditingController(text: guest?.phone),
      idNumber = TextEditingController(text: guest?.idNumber),
      idType = guest?.idType;

  final TextEditingController fullName;
  final TextEditingController phone;
  final TextEditingController idNumber;
  IdType? idType;

  GuestForm get form => GuestForm(
    fullName: fullName.text,
    phone: phone.text,
    idType: idType,
    idNumber: idNumber.text,
  );

  void clear() {
    fullName.clear();
    phone.clear();
    idNumber.clear();
    idType = null;
  }

  void dispose() {
    fullName.dispose();
    phone.dispose();
    idNumber.dispose();
  }
}

/// Full name, phone, ID type and number, with field errors and a notice
/// when the phone already belongs to another guest (allowed: families share
/// phones). [keyPrefix] keeps keys apart when two forms are on screen.
class GuestFormFields extends ConsumerStatefulWidget {
  const GuestFormFields({
    super.key,
    required this.controllers,
    required this.errors,
    required this.keyPrefix,
    this.exceptGuestId,
  });

  final GuestFormControllers controllers;
  final Map<GuestField, String> errors;
  final String keyPrefix;

  /// The guest being corrected, left out of the shared-phone notice.
  final String? exceptGuestId;

  @override
  ConsumerState<GuestFormFields> createState() => _GuestFormFieldsState();
}

class _GuestFormFieldsState extends ConsumerState<GuestFormFields> {
  GuestFormControllers get c => widget.controllers;

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    final phone = normalizeGuestPhone(c.phone.text);
    final shared = phone == null
        ? const []
        : ref
                  .watch(guestsWithPhoneProvider(phone, widget.exceptGuestId))
                  .value ??
              const [];
    Key key(String name) => ValueKey('${widget.keyPrefix}.$name');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LabeledField(
          label: 'Full name',
          controller: c.fullName,
          fieldKey: key('fullName'),
          errorText: widget.errors[GuestField.fullName],
        ),
        const SizedBox(height: Space.x12),
        LabeledField(
          label: 'Phone',
          controller: c.phone,
          fieldKey: key('phone'),
          keyboardType: TextInputType.phone,
          errorText: widget.errors[GuestField.phone],
          onChanged: (_) => setState(() {}),
        ),
        if (shared.isNotEmpty) ...[
          const SizedBox(height: Space.x8),
          Note.info(
            'Already registered with this phone: '
            '${shared.map((g) => g.fullName).join(', ')}. Check it isn’t the '
            'same person.',
            key: key('sharedPhone'),
          ),
        ],
        const SizedBox(height: Space.x12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LabeledDropdown<IdType?>(
                fieldKey: key('idType.${c.idType?.code}'),
                label: 'ID type (optional)',
                options: [
                  const DropdownOption(null, 'No ID'),
                  for (final type in IdType.values)
                    DropdownOption(type, type.label),
                ],
                value: c.idType,
                errorText: widget.errors[GuestField.idType],
                onChanged: (type) => setState(() => c.idType = type),
              ),
            ),
            const SizedBox(width: Space.x12),
            Expanded(
              child: LabeledField(
                label: 'ID number (optional)',
                controller: c.idNumber,
                fieldKey: key('idNumber'),
                errorText: widget.errors[GuestField.idNumber],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.x8),
        Text(
          'Full name and phone are required. ID is optional.',
          style: t.small,
        ),
      ],
    );
  }
}
