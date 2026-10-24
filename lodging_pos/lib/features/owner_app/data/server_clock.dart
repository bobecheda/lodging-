import '../../../core/clock/clock.dart';
import 'owner_cloud.dart';

/// The phone's clock corrected to the server's: every "now" on the owner's
/// phone (day, week and month boundaries, overstays, "Updated 4 min ago")
/// comes from here, so a phone set to the wrong time never moves a payment
/// to another day. Corrected on every load ([sync]).
class ServerClock implements Clock {
  ServerClock(this._phone);

  final Clock _phone;

  /// Server minus phone; zero until the first [sync].
  Duration offset = Duration.zero;

  /// Answers slower than this are ignored (as the desk's clock check).
  static const slowest = Duration(seconds: 10);

  @override
  DateTime now() => _phone.now().add(offset);

  /// Asks the cloud its time (`server_time()`) and keeps the offset,
  /// measured halfway through the request. Returns the server's now.
  Future<DateTime> sync(OwnerCloud cloud) async {
    final asked = _phone.now();
    final answer = await cloud.rpc('server_time', const {});
    final answered = _phone.now();
    final server = DateTime.parse(answer! as String).toUtc();
    final roundTrip = answered.difference(asked);
    if (roundTrip <= slowest) {
      offset = server.difference(asked.add(roundTrip ~/ 2));
    }
    return now();
  }
}
