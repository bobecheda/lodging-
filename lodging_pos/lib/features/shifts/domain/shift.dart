/// An open shift on this device.
class OpenShift {
  const OpenShift({
    required this.id,
    required this.userId,
    required this.userName,
    required this.openedAt,
    required this.openingFloat,
  });

  final String id;
  final String userId;

  /// Full name of the receptionist who opened it.
  final String userName;

  /// UTC.
  final DateTime openedAt;

  /// Whole KES.
  final int openingFloat;
}
