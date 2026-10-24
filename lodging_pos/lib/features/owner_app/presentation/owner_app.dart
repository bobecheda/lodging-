import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/theme/theme.dart';
import 'owner_more_screen.dart';
import 'owner_providers.dart';
import 'owner_refund_screen.dart';
import 'owner_shell.dart';
import 'owner_sign_in_screen.dart';
import 'owner_today_screen.dart';

part 'owner_app.g.dart';

/// The owner's phone app (Android and web; `lib/main_owner.dart`): online
/// only, reading the cloud. Nothing it loads is stored on the phone.
class OwnerApp extends ConsumerWidget {
  const OwnerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'Lodging · Owner',
    theme: buildLodgingTheme(),
    debugShowCheckedModeBanner: false,
    routerConfig: ref.watch(ownerRouterProvider),
  );
}

abstract final class OwnerRoutes {
  static const starting = '/starting';
  static const signIn = '/sign-in';
  static const today = '/today';
  static const money = '/money';
  static const beds = '/beds';
  static const prices = '/prices';
  static const more = '/more';
  static const refund = '/refund';

  static String refundFor(String id) =>
      Uri(path: refund, queryParameters: {'id': id}).toString();

  /// The bottom bar's tabs, in order.
  static const tabs = [today, money, beds, prices, more];
}

@Riverpod(keepAlive: true)
GoRouter ownerRouter(Ref ref) {
  final session = ValueNotifier(ref.read(ownerSessionProvider));
  ref
    ..listen(ownerSessionProvider, (_, next) => session.value = next)
    ..onDispose(session.dispose);
  return GoRouter(
    initialLocation: OwnerRoutes.today,
    refreshListenable: session,
    redirect: (context, state) {
      final s = session.value;
      final at = state.matchedLocation;
      if (!s.hasValue && !s.hasError) {
        return at == OwnerRoutes.starting ? null : OwnerRoutes.starting;
      }
      if (s.value == null) {
        return at == OwnerRoutes.signIn ? null : OwnerRoutes.signIn;
      }
      if (at == OwnerRoutes.signIn || at == OwnerRoutes.starting) {
        return OwnerRoutes.today;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: OwnerRoutes.starting,
        builder: (_, _) =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(
        path: OwnerRoutes.signIn,
        builder: (_, _) => const OwnerSignInScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            OwnerShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: OwnerRoutes.today,
            builder: (_, _) => const OwnerTodayScreen(),
          ),
          GoRoute(
            path: OwnerRoutes.refund,
            builder: (_, state) => OwnerRefundScreen(
              refundId: state.uri.queryParameters['id'] ?? '',
            ),
          ),
          for (final (path, title) in [
            (OwnerRoutes.money, 'Money'),
            (OwnerRoutes.beds, 'Beds'),
            (OwnerRoutes.prices, 'Prices'),
          ])
            GoRoute(
              path: path,
              builder: (_, _) => ComingSoonScreen(title: title),
            ),
          GoRoute(
            path: OwnerRoutes.more,
            builder: (_, _) => const OwnerMoreScreen(),
          ),
        ],
      ),
    ],
  );
}
