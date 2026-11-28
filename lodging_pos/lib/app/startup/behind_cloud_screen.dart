import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audit/audit_writer.dart';
import '../../core/auth/password_hasher.dart';
import '../../core/database/database_provider.dart';
import '../../core/support_contact.dart';
import '../../core/sync/sync_providers.dart';
import '../../features/auth/presentation/auth_providers.dart';
import '../theme/theme.dart';
import '../widgets/buttons.dart';
import '../widgets/labeled_field.dart';
import '../widgets/notes.dart';
import '../widgets/split_gate_layout.dart';
import 'behind_cloud.dart';

/// This PC's data is older than the cloud (story/desk-db-guards-2): shown
/// instead of sign-in, at start and at every sign-in or lock, until the
/// data folder is replaced. Plain words, no raw errors; the owner may see
/// what proved it and copy it for Bobe. Nothing here unlocks the data.
class BehindCloudScreen extends ConsumerStatefulWidget {
  const BehindCloudScreen({super.key});

  @override
  ConsumerState<BehindCloudScreen> createState() => _BehindCloudScreenState();
}

class _BehindCloudScreenState extends ConsumerState<BehindCloudScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  var _busy = false;
  String? _error;
  String? _copyText;
  var _copied = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _reveal() async {
    final evidence = ref.read(deskBehindProvider);
    if (evidence == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final text = await BehindDetailsService(
        ref.read(appDatabaseProvider),
        ref.read(auditWriterProvider),
        ref.read(userRepositoryProvider),
        ref.read(passwordHasherProvider),
      ).reveal(evidence, username: _username.text, password: _password.text);
      if (mounted) setState(() => _copyText = text);
    } on BehindDetailsRefused catch (e) {
      _password.clear();
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    final text = _copyText;
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final t = LodgingType.of(context);
    final c = LodgingColors.of(context);
    final evidence = ref.watch(deskBehindProvider);
    if (evidence == null) return const SizedBox.shrink();
    return SplitGateLayout(
      title: 'This PC’s data is older than the cloud',
      subtitle:
          'Nobody can sign in on this PC until $supportName has sorted it. '
          'Use the paper receipt book meanwhile; the entries are typed in '
          'afterwards.',
      showVersion: true,
      children: [
        Note.error(behindRefusalText, key: const ValueKey('behind.text')),
        formGap,
        if (_copyText == null) ...[
          Text(
            'For the owner: what the cloud has that this PC doesn’t.',
            style: t.secondary.copyWith(color: c.inkSoft),
          ),
          formGap,
          LabeledField(
            label: 'Owner username',
            controller: _username,
            fieldKey: const ValueKey('behind.username'),
            textInputAction: TextInputAction.next,
          ),
          formGap,
          LabeledField(
            label: 'Password',
            controller: _password,
            fieldKey: const ValueKey('behind.password'),
            obscureText: true,
            onSubmitted: (_) => _reveal(),
          ),
          formGap,
          if (_error != null) ...[
            Note.error(_error!, key: const ValueKey('behind.error')),
            formGap,
          ],
          AppButton.secondary(
            key: const ValueKey('behind.details'),
            label: 'Show the details',
            busy: _busy,
            onPressed: _reveal,
          ),
        ] else ...[
          Column(
            key: const ValueKey('behind.lines'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in evidence.lines())
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.x8),
                  child: Text(line, style: t.body),
                ),
            ],
          ),
          formGap,
          AppButton.primary(
            key: const ValueKey('behind.copy'),
            label: _copied ? 'Copied' : 'Copy for $supportName',
            onPressed: _copy,
          ),
        ],
      ],
    );
  }
}
