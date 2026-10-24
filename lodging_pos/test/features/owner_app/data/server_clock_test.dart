import 'package:flutter_test/flutter_test.dart';
import 'package:lodging_pos/core/clock/clock.dart';
import 'package:lodging_pos/core/clock/nairobi.dart';
import 'package:lodging_pos/features/owner_app/data/server_clock.dart';

import '../../../helpers/fake_owner_cloud.dart';

void main() {
  final server = nairobiInstant(2026, 10, 21, 0, 1);

  test('the phone’s clock 2 hours slow: now is the server’s', () async {
    final phone = FixedClock(server.subtract(const Duration(hours: 2)));
    final cloud = FakeOwnerCloud(serverNow: () => server)
      ..stored = FakeOwnerCloud.owner;
    await cloud.restore();
    final clock = ServerClock(phone);
    expect(clock.now(), phone.now()); // before the first answer
    expect(await clock.sync(cloud), server);
    expect(clock.now(), server);
    phone.advance(const Duration(minutes: 5));
    expect(clock.now(), server.add(const Duration(minutes: 5)));
  });

  test('a slow answer (over 10 s) is ignored', () async {
    final phone = FixedClock(server.subtract(const Duration(hours: 2)));
    final cloud = FakeOwnerCloud(
      serverNow: () {
        phone.advance(const Duration(seconds: 11));
        return server;
      },
    )..stored = FakeOwnerCloud.owner;
    await cloud.restore();
    final clock = ServerClock(phone);
    await clock.sync(cloud);
    expect(clock.offset, Duration.zero);
  });
}
