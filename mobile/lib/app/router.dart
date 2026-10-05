import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/models/models.dart';
import '../features/agronomist/agronomist_screen.dart';
import '../features/dealers/dealers_screen.dart';
import '../features/diagnose/diagnose_screen.dart';
import '../features/diagnose/result_screen.dart';
import '../features/home/home_screen.dart';
import '../features/ledger/ledger_screen.dart';
import '../features/outbreaks/outbreak_map_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shell/app_shell.dart';

abstract final class Routes {
  static const home = '/home';
  static const diagnose = '/diagnose';
  static const outbreaks = '/outbreaks';
  static const ledger = '/ledger';
  static const settings = '/settings';
  static const result = '/result';
  static const dealers = '/dealers';
  static const agronomist = '/agronomist';
}

GoRouter buildRouter() => GoRouter(
      initialLocation: Routes.home,
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => AppShell(shell: shell),
          branches: [
            StatefulShellBranch(routes: [GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: Routes.diagnose, builder: (_, _) => const DiagnoseScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: Routes.outbreaks, builder: (_, _) => const OutbreakMapScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: Routes.ledger, builder: (_, _) => const LedgerScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: Routes.settings, builder: (_, _) => const SettingsScreen())]),
          ],
        ),
        GoRoute(
          path: '${Routes.result}/:id',
          builder: (_, state) => ResultScreen(
            diagnosisId: state.pathParameters['id']!,
            initial: state.extra is Diagnosis ? state.extra as Diagnosis : null,
          ),
        ),
        GoRoute(
          path: Routes.dealers,
          builder: (_, state) {
            final extra = state.extra is DealersArgs ? state.extra as DealersArgs : const DealersArgs();
            return DealersScreen(args: extra);
          },
        ),
        GoRoute(path: Routes.agronomist, builder: (_, _) => const AgronomistScreen()),
      ],
      errorBuilder: (context, state) => Scaffold(body: Center(child: Text(state.error.toString()))),
    );
