import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/theme.dart';
import '../../../../app/widgets/buttons.dart';
import '../../../../app/widgets/labeled_dropdown.dart';
import '../../../../app/widgets/labeled_field.dart';
import '../../../../app/widgets/notes.dart';
import '../../../../core/auth/permissions.dart';
import '../../../../core/auth/session.dart';
import '../../../../core/clock/clock_time.dart';
import '../../../../core/settings/settings_repository.dart';
import '../../../receipts/domain/receipt_number.dart';
import '../../data/prices_repository.dart';
import '../../domain/prices_settings.dart';
import '../prices_providers.dart';

/// "Rules and receipts" (AD-3): lodging name, checkout time, grace, lock
/// timeout and receipt prefix, each with its range under it. Read-only
/// without [Permission.editSettings].
class SettingsCard extends ConsumerStatefulWidget {
  const SettingsCard({super.key});

  @override
  ConsumerState<SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends ConsumerState<SettingsCard> {
  final _lodgingName = TextEditingController();
  final _grace = TextEditingController();
  final _idleLock = TextEditingController();
  final _prefix = TextEditingController();
  ClockTime? _checkout;

  /// The stored form the inputs were last filled from.
  SettingsInput? _loaded;
  var _errors = <SettingsField, String>{};
  String? _error;
  String? _saved;
  var _busy = false;

  @override
  void dispose() {
    _lodgingName.dispose();
    _grace.dispose();
    _idleLock.dispose();
    _prefix.dispose();
    super.dispose();
  }

  void _fill(SettingsInput stored) {
    if (identical(stored, _loaded)) return;
    _loaded = stored;
    _lodgingName.text = stored.lodgingName;
    _grace.text = stored.graceMinutes;
    _idleLock.text = stored.idleLockMinutes;
    _prefix.text = stored.receiptPrefix;
    _checkout = stored.checkoutTime;
  }

  SettingsInput _input() => SettingsInput(
    lodgingName: _lodgingName.text,
    checkoutTime: _checkout!,
    graceMinutes: _grace.text,
    idleLockMinutes: _idleLock.text,
    receiptPrefix: _prefix.text,
  );

  Future<void> _save() async {
    final input = _input();
    final errors = validateSettings(input);
    setState(() {
      _errors = errors;
      _error = null;
      _saved = null;
    });
    if (errors.isNotEmpty) return;
    setState(() => _busy = true);
    try {
      final changed = await ref
          .read(pricesRepositoryProvider)
          .saveSettings(ref.read(sessionProvider)!, input);
      ref
        ..invalidate(settingsFormProvider)
        ..invalidate(lodgingNameProvider);
      if (mounted) {
        setState(
          () => _saved = changed == 0 ? 'Nothing to save.' : 'Settings saved.',
        );
      }
    } on InvalidSettings catch (e) {
      if (mounted) setState(() => _errors = e.errors);
    } on NotPermitted {
      if (mounted) {
        setState(() => _error = 'Only the owner can change settings.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final user = ref.watch(sessionProvider);
    final canEdit = user != null && can(user, Permission.editSettings);
    final stored = ref.watch(settingsFormProvider);
    final next = ref.watch(nextReceiptNumberProvider).value ?? 1;
    if (stored.value case final value?) _fill(value);

    final Widget body;
    if (stored case AsyncError(:final error)) {
      body = Note.error('$error', title: 'Settings could not be loaded.');
    } else if (_checkout == null) {
      body = const Padding(
        padding: EdgeInsets.all(Space.x24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else {
      final prefix = _prefix.text.trim().toUpperCase();
      final preview = formatReceiptNumber(prefix.isEmpty ? 'R' : prefix, next);
      Widget pair(Widget a, Widget b) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: a),
          const SizedBox(width: Space.x16),
          Expanded(child: b),
        ],
      );

      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LabeledField(
            label: 'Lodging name on receipts',
            controller: _lodgingName,
            fieldKey: const ValueKey('settings.lodgingName'),
            errorText: _errors[SettingsField.lodgingName],
            enabled: canEdit,
          ),
          const SizedBox(height: Space.x16),
          pair(
            LabeledDropdown<ClockTime>(
              fieldKey: ValueKey('settings.checkoutTime.$_checkout'),
              label: 'Checkout time',
              options: [
                for (final time in checkoutTimeOptions)
                  DropdownOption(time, time.format()),
              ],
              value: _checkout,
              errorText: _errors[SettingsField.checkoutTime],
              helperText:
                  'Every guest leaves by this time the day after arrival',
              onChanged: canEdit
                  ? (time) => setState(() {
                      _checkout = time;
                      _saved = null;
                    })
                  : null,
            ),
            LabeledField(
              label: 'Grace before overstay',
              controller: _grace,
              fieldKey: const ValueKey('settings.grace'),
              suffixText: 'minutes',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              errorText: _errors[SettingsField.graceMinutes],
              helperText:
                  '${graceMinutesRange.min} to ${graceMinutesRange.max}\n'
                  'Changes apply immediately to every guest.',
              enabled: canEdit,
            ),
          ),
          const SizedBox(height: Space.x16),
          pair(
            LabeledField(
              label: 'Lock screen after',
              controller: _idleLock,
              fieldKey: const ValueKey('settings.idleLock'),
              suffixText: 'min idle',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              errorText: _errors[SettingsField.idleLockMinutes],
              helperText: '1 to 60',
              enabled: canEdit,
            ),
            LabeledField(
              label: 'Receipt prefix',
              controller: _prefix,
              fieldKey: const ValueKey('settings.receiptPrefix'),
              suffixText: preview.substring(preview.indexOf('-')),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[A-Za-z]')),
                LengthLimitingTextInputFormatter(4),
                const _UpperCase(),
              ],
              errorText: _errors[SettingsField.receiptPrefix],
              helperText: '1 to 4 letters · next receipt $preview',
              enabled: canEdit,
              onChanged: (_) => setState(() => _saved = null),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: Space.x12),
            Note.error(_error!),
          ],
          const SizedBox(height: Space.x20),
          if (canEdit)
            Wrap(
              spacing: Space.x16,
              runSpacing: Space.x8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                AppButton.primary(
                  key: const ValueKey('settings.save'),
                  label: 'Save settings',
                  busy: _busy,
                  onPressed: _save,
                ),
                if (_saved != null)
                  Text(
                    _saved!,
                    key: const ValueKey('settings.saved'),
                    style: t.small,
                  ),
              ],
            ),
          const SizedBox(height: Space.x16),
          Text(
            canEdit
                ? 'Every change is recorded in the audit trail with the old '
                      'and new value.'
                : 'Only users who can edit settings can change these.',
            style: t.small.copyWith(color: c.muted),
          ),
        ],
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.x24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text('Rules and receipts', style: t.sectionTitle),
            ),
            const SizedBox(height: Space.x20),
            body,
          ],
        ),
      ),
    );
  }
}

/// Receipt prefixes are stored in capitals; show them that way as typed.
class _UpperCase extends TextInputFormatter {
  const _UpperCase();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}
