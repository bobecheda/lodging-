import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/app/startup/desk_root.dart';
import 'package:lodging_pos/app/startup/startup_providers.dart';
import 'package:lodging_pos/app/startup/startup_refusal_screen.dart';
import 'package:lodging_pos/app/theme/theme.dart';
import 'package:lodging_pos/core/app_version.dart';
import 'package:lodging_pos/core/database/desk_meta.dart';
import 'package:lodging_pos/core/database/desk_startup.dart';
import 'package:lodging_pos/core/database/desk_startup_provider.dart';
import 'package:lodging_pos/features/backup/data/restore_acceptance.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/recording_marks.dart';

/// The startup refusals, the unusual-start warning and the version line on
/// screen (story/desk-db-guards).
void main() {
  late TestEnv env;
  setUp(() => env = TestEnv());
  tearDown(() => env.close());

  final t0 = DateTime.utc(2026, 11, 24, 4, 20);
  DatabaseFigures figures({int stays = 42, String receipt = 'R-000061'}) =>
      DatabaseFigures(
        schemaVersion: 11,
        stays: stays,
        payments: stays,
        auditEntries: 900,
        lastReceipt: receipt,
        lastAuditAt: t0,
      );
  final mark = HighWaterMark(
    backupName: 'lodging_pos-2026-11-24-0720.sqlite',
    takenAt: t0,
    figures: figures(),
    build: AppBuild.current.stamp,
  );
  final older = OlderThanBackup(
    LiveFile(figures: figures(stays: 30, receipt: 'R-000050')),
    mark,
  );

  final verdicts = <(String, StartupVerdict)>[
    (
      'The desk is already open on this PC',
      const AlreadyOpen(
        LockHolder(
          exePath: r'D:\Release\lodging_pos.exe',
          version: 'desk 1.0.0 (build 2)',
          since: '',
        ),
      ),
    ),
    ('Database missing — restore from backup', DatabaseMissing(mark)),
    (
      'This app is older than the database',
      const NewerDatabase(12, DeskStamp(version: '1.2.0', build: 4)),
    ),
    (
      'This app is older than the database',
      const NewerBuild(DeskStamp(version: '1.2.0', build: 4)),
    ),
    ('This database looks older than the last backup', older),
  ];

  /// The desk's root with [verdict]; [check] answers a retry.
  Future<void> pumpRoot(
    WidgetTester tester,
    StartupVerdict verdict, {
    Size size = deskSize,
    Future<DeskStartup> Function()? check,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      DeskRoot(
        startup: DeskStartup(folder: 'C:/data', verdict: verdict),
        check: check ?? () async => DeskStartup(verdict: verdict),
        app: const Directionality(
          textDirection: TextDirection.ltr,
          child: Text('app started'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final (title, verdict) in verdicts) {
    testWidgets('${verdict.runtimeType}: "$title", both versions named, at '
        'every desk size', (tester) async {
      for (final size in deskSizes) {
        await pumpRoot(tester, verdict, size: size);
        expect(find.text(title), findsOneWidget);
        final details = tester
            .widget<Text>(find.byKey(const ValueKey('refusal.details')))
            .data!;
        expect(details, contains(AppBuild.current.label));
        expect(
          find.text(
            versionLine(AppBuild.current, schemaVersion: latestSchemaVersion),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull, reason: '$size');
      }
    });
  }

  testWidgets('"Check again" runs the checks again; once they pass, the app '
      'starts', (tester) async {
    var checks = 0;
    await pumpRoot(
      tester,
      verdicts.first.$2,
      check: () async {
        checks++;
        return DeskStartup.none;
      },
    );
    await tapKey(tester, 'refusal.retry');
    expect(checks, 1);
    expect(find.byKey(const ValueKey('refusal.title')), findsNothing);
    expect(find.text('app started'), findsOneWidget);
  });

  testWidgets('older than the last backup: the owner’s form', (tester) async {
    final calls = <(String, String)>[];
    var retried = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deskStartupProvider.overrideWithValue(
            DeskStartup(folder: 'C:/data', verdict: older),
          ),
          restoreAcceptanceProvider.overrideWithValue(
            _FakeAcceptance((password, receipt) async {
              calls.add((password, receipt));
              if (password != 'owner-pass') {
                throw const RestoreRefused('That isn’t the owner’s password.');
              }
            }),
          ),
        ],
        child: MaterialApp(
          theme: buildLodgingTheme(),
          home: StartupRefusalScreen(
            startup: DeskStartup(folder: 'C:/data', verdict: older),
            onRetry: () async => retried++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('30 stays'), findsOneWidget);
    expect(find.textContaining('42 stays'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('refusal.password')),
      'wrong',
    );
    await tester.enterText(
      find.byKey(const ValueKey('refusal.lastReceipt')),
      'R-000064',
    );
    await tapKey(tester, 'refusal.acceptRestore');
    expect(find.text('That isn’t the owner’s password.'), findsOneWidget);
    expect(retried, 0);

    await tester.enterText(
      find.byKey(const ValueKey('refusal.password')),
      'owner-pass',
    );
    await tapKey(tester, 'refusal.acceptRestore');
    expect(calls.last, ('owner-pass', 'R-000064'));
    expect(retried, 1);
  });

  testWidgets('a synced desk whose file doesn’t know the owner’s email: the '
      'form asks for it, then passes it on (story/restore-cloud-check)', (
    tester,
  ) async {
    final acceptance = _FakeAcceptance((_, _) async {});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [restoreAcceptanceProvider.overrideWithValue(acceptance)],
        child: MaterialApp(
          theme: buildLodgingTheme(),
          home: StartupRefusalScreen(
            startup: DeskStartup(folder: 'C:/data', verdict: older),
            onRetry: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('refusal.email')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('refusal.password')),
      'needs-email',
    );
    await tester.enterText(
      find.byKey(const ValueKey('refusal.lastReceipt')),
      '64',
    );
    await tapKey(tester, 'refusal.acceptRestore');
    expect(find.byKey(const ValueKey('refusal.email')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('refusal.email')),
      'owner@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('refusal.password')),
      'needs-email',
    );
    await tapKey(tester, 'refusal.acceptRestore');
    expect(acceptance.emails, [null, 'owner@example.com']);
  });

  group('the unusual start', () {
    const usb = UnusualLocation(
      path: r'D:\Release',
      removable: true,
      recorded: r'C:\UB40\Desk',
    );

    testWidgets('comes before sign-in; the supervisor carries on, then the '
        'desk signs in as usual', (tester) async {
      await env.createFirstSupervisor(testSetup);
      final app = await pumpDeskApp(
        tester,
        env,
        extraOverrides: [
          deskStartupProvider.overrideWithValue(
            const DeskStartup(location: usb),
          ),
        ],
      );
      expect(locationOf(app), Routes.unusualStart);
      expect(find.textContaining(r'D:\Release'), findsOneWidget);
      // A removable drive never becomes the install folder.
      expect(
        find.byKey(const ValueKey('unusualStart.makeInstallFolder')),
        findsNothing,
      );

      await tester.enterText(
        find.byKey(const ValueKey('unusualStart.username')),
        'supervisor',
      );
      await tester.enterText(
        find.byKey(const ValueKey('unusualStart.password')),
        'super-pass',
      );
      await tapKey(tester, 'unusualStart.accept');
      expect(locationOf(app), Routes.login);
      expect(await env.auditFor('desk.unusual_start'), hasLength(1));
    });

    testWidgets('a receptionist can’t carry on', (tester) async {
      await env.createFirstSupervisor(testSetup);
      await env.addReceptionist('desk');
      final app = await pumpDeskApp(
        tester,
        env,
        extraOverrides: [
          deskStartupProvider.overrideWithValue(
            const DeskStartup(location: usb),
          ),
        ],
      );
      await tester.enterText(
        find.byKey(const ValueKey('unusualStart.username')),
        'desk',
      );
      await tester.enterText(
        find.byKey(const ValueKey('unusualStart.password')),
        'desk-pass',
      );
      await tapKey(tester, 'unusualStart.accept');
      expect(locationOf(app), Routes.unusualStart);
      expect(
        find.text(
          'Only the supervisor or the owner can start the desk from here.',
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('on the real desk, before sign-in: an accepted restore is '
      'finished, the build stamped, the first install folder recorded', (
    tester,
  ) async {
    await env.createFirstSupervisor(testSetup);
    final pending = HighWaterMark(
      backupName: 'restore accepted',
      takenAt: t0,
      figures: figures(stays: 30, receipt: 'R-000050'),
      build: AppBuild.current.stamp,
      pendingRestore: PendingRestore(
        acceptedBy: env.owner!.id,
        acceptedAt: t0,
        counterFloor: 65,
        previous: figures(),
      ),
    );
    final marks = RecordingMarks();
    final app = await pumpDeskApp(
      tester,
      env,
      extraOverrides: [
        deskStartupProvider.overrideWithValue(
          DeskStartup(
            folder: 'C:/data',
            inspection: DeskInspection(mark: pending),
            location: const LocationRecord(r'C:\UB40\Desk'),
          ),
        ),
        markStoreProvider.overrideWithValue(marks),
      ],
    );
    expect(locationOf(app), Routes.login);
    expect(await raiseReceiptCounter(env.db, 1), (65, 65));
    expect(await env.auditFor('database.restore_accepted'), hasLength(1));
    expect(marks.replaced.single.pendingRestore, isNull);
    expect(await installPath(env.db), r'C:\UB40\Desk');
    final stamp = await (env.db.select(
      env.db.syncState,
    )..where((s) => s.key.equals(DeskMetaKeys.build))).getSingle();
    expect(stamp.value, '$appBuildNumber');
  });

  testWidgets('the sign-in screen shows the version, commit and schema', (
    tester,
  ) async {
    await env.createFirstSupervisor(testSetup);
    await pumpDeskApp(tester, env);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('gate.version'))).data,
      versionLine(AppBuild.current, schemaVersion: env.db.schemaVersion),
    );
  });
}

class _FakeAcceptance implements RestoreAcceptance {
  _FakeAcceptance(this._accept);

  final Future<void> Function(String password, String receipt) _accept;

  /// The emails the screen passed.
  final emails = <String?>[];

  @override
  Future<void> accept(
    OlderThanBackup refused, {
    required String password,
    required String lastPaperReceipt,
    String? ownerEmail,
  }) {
    emails.add(ownerEmail);
    if (password == 'needs-email' && ownerEmail == null) {
      throw const RestoreNeedsEmail();
    }
    return _accept(password, lastPaperReceipt);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
