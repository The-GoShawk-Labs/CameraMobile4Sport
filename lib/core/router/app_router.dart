import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:volleylive/presentation/screens/mode_select_screen.dart';
import 'package:volleylive/presentation/screens/pairing/phone_a_join_screen.dart';
import 'package:volleylive/presentation/screens/pairing/phone_b_match_setup_screen.dart';
import 'package:volleylive/presentation/screens/phone_a_camera/phone_a_camera_screen.dart';
import 'package:volleylive/presentation/screens/phone_b_scorer/phone_b_scorer_screen.dart';
import 'package:volleylive/presentation/screens/statistician/statistician_screen.dart';

/// Centralna konfiguracja deklaratywnego routingu aplikacji (go_router)
class AppRouter {
  AppRouter._();

  static const String initialRoute = '/';
  static const String cameraRoute = '/camera';
  static const String cameraPairRoute = '/camera/pair';
  static const String scorerRoute = '/scorer';
  static const String scorerSetupRoute = '/scorer/setup';
  static const String statisticianRoute = '/statistician';

  static final GoRouter router = GoRouter(
    initialLocation: initialRoute,
    debugLogDiagnostics: true,
    routes: [
      GoRoute(
        path: initialRoute,
        name: 'mode_select',
        builder: (context, state) => const ModeSelectScreen(),
      ),
      GoRoute(
        path: cameraPairRoute,
        name: 'camera_pair',
        builder: (context, state) => const PhoneAJoinScreen(),
      ),
      GoRoute(
        path: cameraRoute,
        name: 'camera',
        builder: (context, state) => const PhoneACameraScreen(),
      ),
      GoRoute(
        path: scorerSetupRoute,
        name: 'scorer_setup',
        builder: (context, state) => const PhoneBMatchSetupScreen(),
      ),
      GoRoute(
        path: scorerRoute,
        name: 'scorer',
        builder: (context, state) => const PhoneBScorerScreen(),
      ),
      GoRoute(
        path: statisticianRoute,
        name: 'statistician',
        builder: (context, state) => const StatisticianScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Nie znaleziono ścieżki: ${state.uri.toString()}'),
      ),
    ),
  );
}
