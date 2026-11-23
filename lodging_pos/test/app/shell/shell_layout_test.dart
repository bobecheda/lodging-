import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/app/shell/shell_layout.dart';

void main() {
  test('breakpoints: narrow < 768, medium 768–1279, wide ≥ 1280', () {
    expect(deskWidthOf(767), DeskWidth.narrow);
    expect(deskWidthOf(768), DeskWidth.medium);
    expect(deskWidthOf(1279), DeskWidth.medium);
    expect(deskWidthOf(1280), DeskWidth.wide);
  });

  test('a tab’s width: padding, icon, gaps, label, badge, chevron', () {
    // Figma "Beds": 12 + 18 + 8 + 33 + 12 = 83.
    expect(topTabWidth(labelWidth: 33), 83);
    // "Refunds" with its badge: + 8 + 18.
    expect(topTabWidth(labelWidth: 57, badgeWidth: 18), 133);
    // "Setup ▾": + 8 + 16 for the chevron.
    expect(topTabWidth(labelWidth: 40, menu: true), 114);
  });

  group('the tabs fit, or collapse into the menu', () {
    // Figma 1366: tabs from 109 to 544; the status starts at 1049.
    const receptionist = [83.0, 109.0, 98.0, 133.0];

    test('the receptionist’s four tabs fit at 1366', () {
      expect(
        tabsFit(
          barWidth: 1366,
          leading: 109,
          trailing: 341,
          tabWidths: receptionist,
        ),
        isTrue,
      );
    });

    test('at 768 they don’t', () {
      expect(
        tabsFit(
          barWidth: 768,
          leading: 109,
          trailing: 341,
          tabWidths: receptionist,
        ),
        isFalse,
      );
    });

    test('exactly fitting fits; one pixel short doesn’t', () {
      const tabs = [100.0, 100.0];
      final needed = 10 + 100 + tabSpacing + 100 + 20;
      expect(
        tabsFit(barWidth: needed, leading: 10, trailing: 20, tabWidths: tabs),
        isTrue,
      );
      expect(
        tabsFit(
          barWidth: needed - 1,
          leading: 10,
          trailing: 20,
          tabWidths: tabs,
        ),
        isFalse,
      );
    });

    test('no tabs always fit', () {
      expect(
        tabsFit(barWidth: 0, leading: 10, trailing: 10, tabWidths: const []),
        isTrue,
      );
    });
  });

  group('the active tab for a location', () {
    const routes = ['/home', '/owner', '/cash', '/receipts'];
    const flows = {'/check-in': '/home'};

    test('the route itself, ignoring the query', () {
      expect(activeRouteFor('/cash', routes), '/cash');
      expect(activeRouteFor('/home?stay=s-1', routes), '/home');
    });

    test('a page under a route belongs to it', () {
      expect(activeRouteFor('/cash/count?kind=check', routes), '/cash');
      expect(activeRouteFor('/owner/refund?id=r', routes), '/owner');
    });

    test('a flow belongs to its home', () {
      expect(activeRouteFor('/check-in?bed=b', routes, flows: flows), '/home');
    });

    test('nothing matches', () {
      expect(activeRouteFor('/guests', routes), isNull);
      expect(activeRouteFor('/cashier', routes), isNull);
    });
  });

  test('initials: two words, or the first two letters of one', () {
    expect(initialsOf('Akinyi'), 'AK');
    expect(initialsOf('Grace Supervisor'), 'GS');
    expect(initialsOf('  amina  wanjiru owner '), 'AW');
    expect(initialsOf('O'), 'O');
    expect(initialsOf(''), '?');
  });
}
