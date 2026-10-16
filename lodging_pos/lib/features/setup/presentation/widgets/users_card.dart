import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/theme.dart';
import '../../../../app/widgets/buttons.dart';
import '../../../../app/widgets/labeled_field.dart';
import '../../../../app/widgets/notes.dart';
import '../../../../core/auth/permissions.dart';
import '../../../../core/auth/session.dart';
import '../../../../core/auth/user_account.dart';
import '../../../../core/clock/nairobi.dart';
import '../../data/staff_repository.dart';
import '../../domain/staff.dart';
import '../staff_providers.dart';
import 'staff_dialogs.dart';

/// "People who sign in" (AD-4): status, reset password, disable or enable,
/// and the add-a-receptionist form. Read-only without
/// [Permission.manageUsers].
class UsersCard extends ConsumerStatefulWidget {
  const UsersCard({super.key});

  @override
  ConsumerState<UsersCard> createState() => _UsersCardState();
}

class _UsersCardState extends ConsumerState<UsersCard> {
  final _fullName = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  var _errors = <ReceptionistField, String>{};
  String? _error;
  String? _done;
  var _busy = false;

  @override
  void dispose() {
    _fullName.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  StaffRepository get _repo => ref.read(staffRepositoryProvider);
  UserAccount get _me => ref.read(sessionProvider)!;

  Future<void> _run(Future<void> Function() write, {String? done}) async {
    setState(() {
      _busy = true;
      _error = null;
      _done = null;
    });
    try {
      await write();
      ref.invalidate(staffUsersProvider);
      if (mounted) setState(() => _done = done);
    } on InvalidReceptionist catch (e) {
      if (mounted) setState(() => _errors = e.errors);
    } on StaffRuleViolation catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on NotPermitted {
      if (mounted) setState(() => _error = 'Only the owner can manage users.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final input = NewReceptionist(
      fullName: _fullName.text,
      username: _username.text,
      temporaryPassword: _password.text,
    );
    setState(() => _errors = validateNewReceptionist(input));
    if (_errors.isNotEmpty) return;
    await _run(() async {
      await _repo.addReceptionist(_me, input);
      _fullName.clear();
      _username.clear();
      _password.clear();
    }, done: '${input.fullName.trim()} added.');
  }

  Future<void> _reset(UserSummary user) async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => ResetPasswordDialog(user: user.account),
    );
    if (password == null || !mounted) return;
    await _run(
      () => _repo.resetPassword(_me, user.account.id, password),
      done: 'Password reset for ${user.account.fullName}.',
    );
  }

  Future<void> _disable(UserSummary user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => DisableUserDialog(
        user: user.account,
        warning: disableWarning(
          user.account,
          shiftOpenSince: user.shiftOpenSince,
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await _run(
      () => _repo.disableUser(_me, user.account.id),
      done: '${user.account.fullName} is disabled.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final me = ref.watch(sessionProvider);
    final canManage = me != null && can(me, Permission.manageUsers);
    final users = ref.watch(staffUsersProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.x24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text('People who sign in', style: t.sectionTitle),
            ),
            const SizedBox(height: Space.x12),
            if (users case AsyncError(:final error))
              Note.error('$error', title: 'Users could not be loaded.')
            else
              for (final (i, u) in (users.value ?? const []).indexed) ...[
                if (i > 0) Divider(height: 1, color: c.lineSoft),
                _UserRow(
                  user: u,
                  me: me,
                  canManage: canManage,
                  busy: _busy,
                  onReset: () => _reset(u),
                  onDisable: () => _disable(u),
                  onEnable: () => _run(
                    () => _repo.enableUser(_me, u.account.id),
                    done: '${u.account.fullName} can sign in again.',
                  ),
                ),
              ],
            if (_error != null) ...[
              const SizedBox(height: Space.x12),
              Note.error(_error!, key: const ValueKey('users.error')),
            ],
            if (_done != null) ...[
              const SizedBox(height: Space.x12),
              Text(_done!, key: const ValueKey('users.done'), style: t.small),
            ],
            const SizedBox(height: Space.x20),
            if (canManage)
              _AddReceptionist(
                fullName: _fullName,
                username: _username,
                password: _password,
                errors: _errors,
                busy: _busy,
                onAdd: _add,
              )
            else
              Text(
                'Only users who can manage users can change these.',
                style: t.small.copyWith(color: c.muted),
              ),
          ],
        ),
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    required this.me,
    required this.canManage,
    required this.busy,
    required this.onReset,
    required this.onDisable,
    required this.onEnable,
  });

  final UserSummary user;
  final UserAccount? me;
  final bool canManage;
  final bool busy;
  final VoidCallback onReset;
  final VoidCallback onDisable;
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final a = user.account;
    final status = userStatus(a);
    final disabled = status == UserStatus.disabled;
    final isMe = me?.id == a.id;
    final manageable =
        canManage &&
        me != null &&
        accountActionBlocker(actor: me!, target: a) == null;
    final role = switch (a.role) {
      Role.admin => 'Admin',
      Role.receptionist => 'Receptionist',
    };
    final since = user.shiftOpenSince;
    final details = [
      a.username,
      role,
      if (since != null) 'shift open since ${formatTime(since)}',
    ].join(' · ');
    final name = a.username;

    return Padding(
      key: ValueKey('users.row.$name'),
      padding: const EdgeInsets.symmetric(vertical: Space.x12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    text: a.fullName,
                    children: [
                      if (isMe)
                        TextSpan(
                          text: ' (you)',
                          style: t.body.copyWith(color: c.muted),
                        ),
                    ],
                  ),
                  style: t.bodyStrong.copyWith(
                    color: disabled ? c.muted : null,
                  ),
                ),
                const SizedBox(height: Space.x4),
                Text(details, style: t.small.copyWith(color: c.muted)),
              ],
            ),
          ),
          const SizedBox(width: Space.x12),
          Wrap(
            spacing: Space.x8,
            runSpacing: Space.x8,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusBadge(
                key: ValueKey('users.status.$name'),
                switch (status) {
                  UserStatus.active => 'ACTIVE',
                  UserStatus.mustSetPassword => 'MUST SET PASSWORD',
                  UserStatus.disabled => 'DISABLED',
                },
                tone: switch (status) {
                  UserStatus.active => BadgeTone.active,
                  UserStatus.mustSetPassword => BadgeTone.warning,
                  UserStatus.disabled => BadgeTone.disabled,
                },
              ),
              if (manageable && !disabled) ...[
                AppButton.secondary(
                  key: ValueKey('users.reset.$name'),
                  label: 'Reset password',
                  compact: true,
                  onPressed: busy ? null : onReset,
                ),
                AppButton.destructive(
                  key: ValueKey('users.disable.$name'),
                  label: 'Disable',
                  compact: true,
                  onPressed: busy ? null : onDisable,
                ),
              ],
              if (manageable && disabled)
                AppButton.secondary(
                  key: ValueKey('users.enable.$name'),
                  label: 'Enable',
                  compact: true,
                  onPressed: busy ? null : onEnable,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddReceptionist extends StatelessWidget {
  const _AddReceptionist({
    required this.fullName,
    required this.username,
    required this.password,
    required this.errors,
    required this.busy,
    required this.onAdd,
  });

  final TextEditingController fullName;
  final TextEditingController username;
  final TextEditingController password;
  final Map<ReceptionistField, String> errors;
  final bool busy;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    return Container(
      padding: const EdgeInsets.all(Space.x20),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add a receptionist', style: t.bodyStrong),
          const SizedBox(height: Space.x12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LabeledField(
                  label: 'Full name',
                  controller: fullName,
                  fieldKey: const ValueKey('addUser.fullName'),
                  errorText: errors[ReceptionistField.fullName],
                ),
              ),
              const SizedBox(width: Space.x12),
              Expanded(
                child: LabeledField(
                  label: 'Username',
                  controller: username,
                  fieldKey: const ValueKey('addUser.username'),
                  errorText: errors[ReceptionistField.username],
                ),
              ),
              const SizedBox(width: Space.x12),
              Expanded(
                child: LabeledField(
                  label: 'Temporary password',
                  controller: password,
                  fieldKey: const ValueKey('addUser.password'),
                  errorText: errors[ReceptionistField.temporaryPassword],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.x16),
          Wrap(
            spacing: Space.x16,
            runSpacing: Space.x8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppButton.primary(
                key: const ValueKey('addUser.save'),
                label: 'Add receptionist',
                busy: busy,
                onPressed: onAdd,
              ),
              Text(
                'They choose their own password the first time they sign in.',
                style: t.small,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
