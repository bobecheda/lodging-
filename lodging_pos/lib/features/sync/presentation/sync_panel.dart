import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/theme.dart';
import '../../../app/widgets/buttons.dart';
import '../../../app/widgets/labeled_field.dart';
import '../../../app/widgets/notes.dart';
import '../../../app/widgets/side_panel.dart';
import '../../../core/auth/password_hasher.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/clock/clock.dart';
import '../../../core/clock/nairobi.dart';
import '../../../core/money/kes.dart';
import '../../../core/sync/cloud.dart';
import '../../../core/sync/cloud_writes.dart';
import '../../../core/sync/outbox_status.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_providers.dart';
import '../../../core/sync/sync_status_text.dart';
import '../../auth/presentation/auth_providers.dart';

Future<void> showSyncPanel(BuildContext context) => showSidePanel(
  context,
  child: const SyncPanel(),
  barrierLabel: 'Close cloud sync',
);

/// "Cloud sync", opened from the sidebar pill: where sync stands, the
/// refused change stopping the queue with Retry, the first upload's
/// progress, and for the owner Connect / Reconnect this desk and the
/// sign-in that finishes the first upload (docs/sync.md).
class SyncPanel extends ConsumerStatefulWidget {
  const SyncPanel({super.key});

  @override
  ConsumerState<SyncPanel> createState() => _SyncPanelState();
}

class _SyncPanelState extends ConsumerState<SyncPanel> {
  final _code = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _codeError;
  String? _emailError;
  String? _passwordError;
  String? _problem;
  var _busy = false;

  @override
  void dispose() {
    _code.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// The signed-in owner's desk password, checked here first: the cloud
  /// account gets the same one.
  Future<bool> _passwordIsTheOwners() async {
    final user = ref.read(sessionProvider);
    if (user == null) return false;
    final stored = await ref
        .read(userRepositoryProvider)
        .findByUsername(user.username);
    return stored != null &&
        await ref
            .read(passwordHasherProvider)
            .verify(_password.text, stored.passwordHash);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await action();
      _password.clear();
    } on CloudOffline {
      if (mounted) {
        setState(() => _problem = 'No internet connection. Try again later.');
      }
    } on CloudRefused catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } on CloudSignInRefused {
      if (mounted) {
        setState(
          () => _problem = 'The cloud didn’t accept that email and password.',
        );
      }
    } on NeedsInternet {
      if (mounted) {
        setState(() => _problem = 'No internet connection. Try again later.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect({required bool reconnect}) async {
    final engine = ref.read(syncEngineProvider);
    final owner = ref.read(sessionProvider);
    if (engine == null || owner == null) return;
    final email = _email.text.trim();
    setState(() {
      _codeError = !reconnect && _code.text.trim().isEmpty
          ? 'Enter the install code.'
          : null;
      _emailError = email.contains('@') ? null : 'Enter your email.';
      _passwordError = _password.text.isEmpty
          ? 'Enter your desk password.'
          : null;
    });
    if (_codeError != null || _emailError != null || _passwordError != null) {
      return;
    }
    if (!await _passwordIsTheOwners()) {
      setState(() => _passwordError = 'That isn’t your desk password.');
      return;
    }
    await _run(
      () => reconnect
          ? engine.reconnect(
              owner: owner,
              ownerEmail: email,
              password: _password.text,
            )
          : engine.connect(
              owner: owner,
              installCode: _code.text,
              ownerEmail: email,
              password: _password.text,
            ),
    );
  }

  Future<void> _finishUpload() async {
    final engine = ref.read(syncEngineProvider);
    if (engine == null) return;
    setState(
      () => _passwordError = _password.text.isEmpty
          ? 'Enter your desk password.'
          : null,
    );
    if (_passwordError != null) return;
    await _run(() async {
      await engine.signInOwner(_password.text);
      await engine.continueFirstUpload();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = LodgingColors.of(context);
    final t = LodgingType.of(context);
    final status =
        ref.watch(syncStatusProvider).value ??
        const SyncStatus(phase: SyncPhase.notConfigured);
    final pending = ref.watch(pendingChangesProvider).value ?? 0;
    final now = ref.watch(clockProvider).now();
    final user = ref.watch(sessionProvider);
    final isOwner = user != null && can(user, Permission.connectDesk);
    final engine = ref.watch(syncEngineProvider);

    Widget row(String label, String value, {Key? key}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: t.small.copyWith(color: c.muted)),
          ),
          Text(value, key: key, style: t.monoStrong),
        ],
      ),
    );

    final retry = AppButton.secondary(
      key: const ValueKey('sync.retry'),
      label: 'Try again now',
      busy: _busy,
      onPressed: engine == null ? null : () => _run(engine.syncNow),
    );

    final List<Widget> body = switch (status.phase) {
      SyncPhase.notConfigured => [
        const Note.info(
          'This build has no cloud settings, so everything stays on this '
          'desk. See docs/sync.md.',
        ),
      ],
      SyncPhase.notConnected when isOwner => _connectForm(reconnect: false),
      SyncPhase.notConnected => [
        const Note.info(
          'This desk isn’t connected to the cloud yet. The owner connects '
          'it here.',
        ),
      ],
      SyncPhase.uploading => [
        LinearProgressIndicator(
          key: const ValueKey('sync.progress'),
          value: status.uploadTotal == 0
              ? null
              : status.uploadSent / status.uploadTotal,
          color: c.marine,
          backgroundColor: c.marineTint,
        ),
        const SizedBox(height: Space.x12),
        Text(
          'Keep this desk on. After a power cut or a lost connection it '
          'carries on where it stopped.',
          style: t.small.copyWith(color: c.inkSoft),
        ),
      ],
      SyncPhase.waitingForOwner when isOwner => [
        const Note.warning(
          'The first upload needs your cloud sign-in to send your decisions '
          'and prices and finish.',
        ),
        const SizedBox(height: Space.x16),
        ..._passwordField(),
        const SizedBox(height: Space.x16),
        AppButton.primary(
          key: const ValueKey('sync.finish'),
          label: 'Finish the first upload',
          busy: _busy,
          onPressed: _finishUpload,
        ),
      ],
      SyncPhase.waitingForOwner => [
        const Note.warning(
          'The first upload is waiting for the owner to sign in and finish '
          'it.',
        ),
      ],
      SyncPhase.online => [
        Note.info(
          pending == 0
              ? 'Everything written on this desk is in the cloud.'
              : 'The latest changes go up in a moment.',
        ),
      ],
      SyncPhase.offline => [
        const Note.warning(
          'The cloud can’t be reached. Changes wait safely on this desk and '
          'go up when the connection is back.',
        ),
        const SizedBox(height: Space.x16),
        retry,
      ],
      SyncPhase.problem when status.needsReconnect => [
        Note.error(
          status.problem ?? '',
          key: const ValueKey('sync.problem'),
          title: 'This desk needs reconnecting.',
        ),
        const SizedBox(height: Space.x16),
        if (isOwner)
          ..._connectForm(reconnect: true)
        else
          const Note.info('Ask the owner to reconnect this desk.'),
      ],
      SyncPhase.problem => [
        Note.error(
          status.problem ?? '',
          key: const ValueKey('sync.problem'),
          title: 'Sync stopped at a change the cloud refused.',
        ),
        const SizedBox(height: Space.x8),
        Text(
          'Nothing is skipped: later changes wait behind it. Tell the '
          'supervisor; once it’s fixed, sync carries on.',
          style: t.small.copyWith(color: c.inkSoft),
        ),
        const SizedBox(height: Space.x16),
        retry,
      ],
    };

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.x24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Cloud sync', style: t.pageTitle)),
                IconButton(
                  key: const ValueKey('sync.close'),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: Space.x8),
            Text(
              syncPillText(status, pending: pending, now: now),
              key: const ValueKey('sync.state'),
              style: t.bodyStrong,
            ),
            const SizedBox(height: Space.x12),
            row(
              'Last synced',
              status.lastSyncAt == null
                  ? 'Not yet'
                  : formatDayDateComma(status.lastSyncAt!),
            ),
            row(
              'Changes waiting',
              formatKesPlain(pending),
              key: const ValueKey('sync.pending'),
            ),
            if (status.clockWarning && status.clockOffset != null) ...[
              const SizedBox(height: Space.x16),
              Note.warning(
                clockWarningText(status.clockOffset!),
                key: const ValueKey('sync.clock'),
                title: 'Check the PC’s clock',
              ),
              const SizedBox(height: Space.x4),
              Text(
                'Checkout times and late charges use this PC’s clock. Nothing '
                'is blocked meanwhile.',
                style: t.small.copyWith(color: c.inkSoft),
              ),
            ],
            const SizedBox(height: Space.x20),
            ...body,
            if (_problem != null) ...[
              const SizedBox(height: Space.x12),
              Note.error(_problem!, key: const ValueKey('sync.error')),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _passwordField() => [
    LabeledField(
      label: 'Your desk password',
      controller: _password,
      fieldKey: const ValueKey('sync.password'),
      errorText: _passwordError,
      obscureText: true,
    ),
  ];

  List<Widget> _connectForm({required bool reconnect}) {
    final t = LodgingType.of(context);
    final c = LodgingColors.of(context);
    return [
      Text(
        reconnect
            ? 'Your cloud email and desk password give this desk a new key.'
            : 'Connecting sends everything on this desk to the cloud, then '
                  'keeps it up to date. Your phone will sign in with this '
                  'email and your desk password.',
        style: t.small.copyWith(color: c.inkSoft),
      ),
      const SizedBox(height: Space.x16),
      if (!reconnect) ...[
        LabeledField(
          label: 'Install code',
          controller: _code,
          fieldKey: const ValueKey('sync.code'),
          errorText: _codeError,
          helperText: 'A one-time code, e.g. 7KQ2-M9XD-4HPA',
        ),
        const SizedBox(height: Space.x12),
      ],
      LabeledField(
        label: 'Your email',
        controller: _email,
        fieldKey: const ValueKey('sync.email'),
        errorText: _emailError,
        keyboardType: TextInputType.emailAddress,
      ),
      const SizedBox(height: Space.x12),
      ..._passwordField(),
      const SizedBox(height: Space.x16),
      AppButton.primary(
        key: const ValueKey('sync.connect'),
        label: reconnect ? 'Reconnect this desk' : 'Connect this desk',
        busy: _busy,
        onPressed: () => _connect(reconnect: reconnect),
      ),
    ];
  }
}
