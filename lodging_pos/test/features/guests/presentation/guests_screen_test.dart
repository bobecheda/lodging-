import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/gate.dart';
import 'package:lodging_pos/core/auth/user_account.dart';
import 'package:lodging_pos/features/guests/data/guests_repository.dart';
import 'package:lodging_pos/features/guests/domain/guest.dart';

import '../../../helpers/fixtures.dart';

void main() {
  late TestEnv env;
  late UserAccount desk;

  setUp(() async {
    env = TestEnv();
    await env.createFirstSupervisor(testSetup);
    desk = await env.addReceptionist('desk');
  });
  tearDown(() => env.close());

  GuestsRepository guests() => GuestsRepository(env.db, env.audit);

  Future<Guest> grace() => guests().register(
    desk,
    const GuestForm(
      fullName: 'Grace Achieng',
      phone: '0722418905',
      idType: IdType.nationalId,
      idNumber: '12343921',
    ),
  );

  /// Registers "Guest 1" … "Guest [n]", a minute apart (Guest n newest).
  Future<List<Guest>> manyGuests(int n) async => [
    for (var i = 1; i <= n; i++) ...[
      await guests().register(
        desk,
        GuestForm(
          fullName: 'Guest $i',
          phone: '0711${i.toString().padLeft(6, '0')}',
          idType: null,
          idNumber: '',
        ),
      ),
      if (i < n)
        ...(() {
          env.clock.advance(const Duration(minutes: 1));
          return const <Guest>[];
        })(),
    ],
  ];

  /// Signs in as the receptionist (opening a shift) and opens Guests.
  Future<ProviderContainer> openGuests(WidgetTester tester) async {
    final app = await pumpDeskApp(tester, env);
    await signInAs(tester, 'desk', 'desk-pass');
    await enterKey(tester, 'shift.float', '500');
    await tapKey(tester, 'shift.submit');
    await tapKey(tester, 'nav.${Routes.guests}');
    expect(locationOf(app), Routes.guests);
    return app;
  }

  Future<void> search(WidgetTester tester, String text) async {
    await enterKey(tester, 'guests.search', text);
    await tester.pumpAndSettle();
  }

  Finder inSelected(Finder f) => find.descendant(
    of: find.byKey(const ValueKey('guests.selected')),
    matching: f,
  );

  Finder inList(String key, Finder f) =>
      find.descendant(of: find.byKey(ValueKey(key)), matching: f);

  /// Names in the visible part of the list, top to bottom.
  List<String> visibleNames(WidgetTester tester, String key) => [
    for (final e in inList(key, find.textContaining('Guest ')).evaluate())
      (e.widget as Text).data!,
  ];

  group('recent guests', () {
    testWidgets('no guests yet says how to add one', (tester) async {
      await openGuests(tester);
      expect(
        find.text(
          'No guests yet. Register one with the form, or during check-in.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('guests.recentNote')), findsNothing);
    });

    testWidgets('an empty search shows the 30 most recent, newest first, '
        'with masked phone, masked ID and registration date', (tester) async {
      final g = await grace();
      env.clock.advance(const Duration(minutes: 1));
      await manyGuests(31);
      await openGuests(tester);

      expect(find.text('Recent guests'), findsOneWidget);
      expect(
        find.text(
          'Showing the 30 most recent. Search by phone or ID to find others.',
        ),
        findsOneWidget,
      );
      // Newest first.
      expect(visibleNames(tester, 'guests.recent').take(3), [
        'Guest 31',
        'Guest 30',
        'Guest 29',
      ]);
      // The list is lazy: scroll to its end. Guest 2 is the 30th; Guest 1
      // and Grace are older than the 30 and only found by searching.
      await tester.scrollUntilVisible(
        find.text('Guest 2'),
        300,
        scrollable: inList('guests.recent', find.byType(Scrollable)).first,
      );
      expect(find.text('Guest 2'), findsOneWidget);
      expect(find.text('Guest 1'), findsNothing);
      expect(find.text('Grace Achieng'), findsNothing);

      // Each row: masked phone, masked ID, registration date.
      await search(tester, '0722');
      expect(
        inList(
          'guests.matches',
          find.text('0722 ••• 905 · National ID ••••3921'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(ValueKey('guests.match.${g.id}')),
          matching: find.textContaining('Registered Wed 14 Oct'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('typing replaces the list with matches; clearing brings it '
        'back', (tester) async {
      await grace();
      await manyGuests(3);
      await openGuests(tester);
      expect(find.byKey(const ValueKey('guests.recent')), findsOneWidget);

      await search(tester, '07');
      expect(find.byKey(const ValueKey('guests.keepTyping')), findsOneWidget);
      expect(find.byKey(const ValueKey('guests.recent')), findsNothing);

      await search(tester, '0722 41');
      expect(find.byKey(const ValueKey('guests.recent')), findsNothing);
      expect(visibleNames(tester, 'guests.matches'), isEmpty);
      expect(
        inList('guests.matches', find.text('Grace Achieng')),
        findsOneWidget,
      );
      expect(find.text('Recent guests'), findsNothing);

      await search(tester, '');
      expect(find.byKey(const ValueKey('guests.recent')), findsOneWidget);
      expect(visibleNames(tester, 'guests.recent').first, 'Guest 3');
    });

    testWidgets('a registered or corrected guest moves to the top at once', (
      tester,
    ) async {
      final g = await grace();
      env.clock.advance(const Duration(minutes: 1));
      await manyGuests(2);
      await openGuests(tester);
      expect(visibleNames(tester, 'guests.recent').first, 'Guest 2');

      // Register through the form: it goes to the top without a refresh.
      env.clock.advance(const Duration(minutes: 1));
      await tapKey(tester, 'guests.register');
      await enterKey(tester, 'newGuest.fullName', 'Guest New');
      await enterKey(tester, 'newGuest.phone', '0700 123 456');
      await tapKey(tester, 'newGuest.save');
      expect(visibleNames(tester, 'guests.recent').first, 'Guest New');

      // Correct Grace: she moves to the top.
      env.clock.advance(const Duration(minutes: 1));
      await tapKey(tester, 'guests.match.${g.id}');
      await tapKey(tester, 'correct.open');
      await enterKey(tester, 'correct.fullName', 'Grace Achieng Otieno');
      await tapKey(tester, 'correct.save');
      expect(
        inList('guests.recent', find.text('Grace Achieng Otieno')),
        findsOneWidget,
      );
      final first = tester
          .widgetList<Text>(inList('guests.recent', find.byType(Text)))
          .first;
      expect(first.data, 'Grace Achieng Otieno');
    });
  });

  testWidgets('matches mask the phone; the opened guest shows it in full', (
    tester,
  ) async {
    final g = await grace();
    await openGuests(tester);
    expect(find.textContaining('Pick a guest from the list'), findsOneWidget);

    await search(tester, '0722 41');
    final match = find.byKey(ValueKey('guests.match.${g.id}'));
    expect(
      find.descendant(
        of: match,
        matching: find.text('0722 ••• 905 · National ID ••••3921'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: match, matching: find.textContaining('418')),
      findsNothing,
    );

    await tapKey(tester, 'guests.match.${g.id}');
    expect(
      inSelected(find.text('0722 418 905 · National ID ••••3921')),
      findsWidgets,
    );
  });

  testWidgets('searching by ID works; no match says so', (tester) async {
    await grace();
    await openGuests(tester);
    await search(tester, '1234');
    expect(
      inList('guests.matches', find.text('Grace Achieng')),
      findsOneWidget,
    );
    await search(tester, '9999');
    expect(find.text('No guest found.'), findsOneWidget);
  });

  testWidgets('registers a new guest, who opens for correction', (
    tester,
  ) async {
    await openGuests(tester);
    await tapKey(tester, 'guests.register');
    await tapKey(tester, 'newGuest.save');
    expect(find.text('Enter the full name.'), findsOneWidget);
    expect(find.text('Enter a phone number.'), findsOneWidget);

    await enterKey(tester, 'newGuest.fullName', 'Peter Okello');
    await enterKey(tester, 'newGuest.phone', '+256 712 345 678');
    await tapKey(tester, 'newGuest.idType.null');
    await tester.tap(find.text('Passport').last);
    await tester.pumpAndSettle();
    await enterKey(tester, 'newGuest.idNumber', 'b 1234567');
    await tapKey(tester, 'newGuest.save');

    expect(
      inSelected(find.text('+256712345678 · Passport ••••4567')),
      findsWidgets,
    );
    expect(find.byKey(const ValueKey('correct.open')), findsOneWidget);
    expect(await env.auditFor('guest.create'), hasLength(1));
  });

  testWidgets('a shared phone is pointed out; a registered ID is refused', (
    tester,
  ) async {
    await grace();
    await openGuests(tester);
    await tapKey(tester, 'guests.register');
    await enterKey(tester, 'newGuest.fullName', 'Tom Achieng');
    await enterKey(tester, 'newGuest.phone', '0722 418 905');
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Already registered with this phone: Grace Achieng'),
      findsOneWidget,
    );

    await tapKey(tester, 'newGuest.idType.null');
    await tester.tap(find.text('National ID').last);
    await tester.pumpAndSettle();
    await enterKey(tester, 'newGuest.idNumber', '12343921');
    await tapKey(tester, 'newGuest.save');
    expect(
      find.text('This ID is already registered to another guest.'),
      findsOneWidget,
    );
  });

  testWidgets('corrects a guest’s details (guest.update)', (tester) async {
    final g = await grace();
    await openGuests(tester);
    await tapKey(tester, 'guests.match.${g.id}');
    await tapKey(tester, 'correct.open');

    await enterKey(tester, 'correct.fullName', 'Grace Achieng Otieno');
    await enterKey(tester, 'correct.idNumber', '123');
    await tapKey(tester, 'correct.save');
    expect(find.text('A National ID is 6–9 digits.'), findsOneWidget);

    await enterKey(tester, 'correct.idNumber', '12343922');
    await tapKey(tester, 'correct.save');
    expect(find.text('Details saved.'), findsOneWidget);
    expect(inSelected(find.text('Grace Achieng Otieno')), findsOneWidget);
    final now = await guests().guest(g.id);
    expect((now.fullName, now.idNumber), ('Grace Achieng Otieno', '12343922'));
    expect(await env.auditFor('guest.update'), hasLength(1));
  });
}
