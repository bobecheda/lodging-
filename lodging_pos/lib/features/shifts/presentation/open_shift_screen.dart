import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/gate_card.dart';
import '../../../core/auth/session.dart';
import '../../../core/clock/nairobi.dart';
import '../../../core/money/kes.dart';
import '../data/shift_repository.dart';
import '../domain/shift_rules.dart';
import 'shift_providers.dart';

/// A receptionist opens a shift (recording the cash float) before working,
/// or is told whose shift is blocking the device.
class OpenShiftScreen extends ConsumerStatefulWidget {
  const OpenShiftScreen({super.key});

  @override
  ConsumerState<OpenShiftScreen> createState() => _OpenShiftScreenState();
}

class _OpenShiftScreenState extends ConsumerState<OpenShiftScreen> {
  final _float = TextEditingController();
  String? _error;
  var _busy = false;

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final user = ref.read(sessionProvider);
    if (user == null) return;
    final amount = parseKes(_float.text);
    final problem = _float.text.trim().isEmpty
        ? openingFloatError(null)
        : amount == null
        ? 'Enter a whole amount in KES, e.g. 1,000'
        : openingFloatError(amount);
    setState(() => _error = problem);
    if (problem != null) return;

    setState(() => _busy = true);
    try {
      await ref.read(currentShiftProvider.notifier).open(user, amount!);
    } on ShiftAlreadyOpen {
      // Someone opened one meanwhile; reload so the router re-decides.
      ref.invalidate(currentShiftProvider);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open the shift: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _signOut() => ref.read(sessionProvider.notifier).signOut();

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider);
    final open = ref.watch(currentShiftProvider).value;
    final start = user == null
        ? null
        : shiftStartFor(openShift: open, userId: user.id, role: user.role);

    if (start case ShiftBlocked(:final openShift)) {
      return GateCard(
        title: 'Another shift is open',
        subtitle:
            "${openShift.userName}'s shift has been open since "
            '${formatNairobi(openShift.openedAt)}. It must be closed before '
            'a new shift can start on this computer.',
        children: [
          OutlinedButton(onPressed: _signOut, child: const Text('Sign out')),
        ],
      );
    }

    return GateCard(
      title: 'Open your shift',
      subtitle: 'Count the cash in the drawer and enter it as your float.',
      children: [
        TextField(
          key: const ValueKey('shift.float'),
          controller: _float,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Opening cash float',
            prefixText: 'KES ',
            errorText: _error,
          ),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 16),
        BusyButton(
          key: const ValueKey('shift.submit'),
          label: 'Open shift',
          busy: _busy,
          onPressed: _submit,
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: _signOut, child: const Text('Sign out')),
      ],
    );
  }
}
