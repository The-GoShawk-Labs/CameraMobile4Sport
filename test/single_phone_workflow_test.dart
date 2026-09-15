import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:volleylive/core/router/app_router.dart';
import 'package:volleylive/main.dart';
import 'package:volleylive/presentation/providers/camera_provider.dart';
import 'package:volleylive/presentation/screens/mode_select_screen.dart';
import 'package:volleylive/presentation/screens/phone_a_camera/phone_a_camera_screen.dart';
import 'package:volleylive/presentation/screens/phone_b_scorer/phone_b_scorer_screen.dart';
import 'package:volleylive/presentation/screens/pairing/phone_a_join_screen.dart';
import 'package:volleylive/presentation/screens/pairing/phone_b_match_setup_screen.dart';

void main() {
  group('Single Phone (All-In-One) Workflow & Safe Exit Tests', () {
    setUp(() {
      AppRouter.router.go(AppRouter.initialRoute);
    });

    testWidgets('ModeSelectScreen renders Single Phone section and quick start buttons', (WidgetTester tester) async {
      await tester.pumpWidget(const VolleyLiveApp());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('TRYB JEDNEGO SMARTFONA'), findsOneWidget);
      expect(find.text('1. KAMERA'), findsOneWidget);
      expect(find.text('2. SĘDZIA'), findsOneWidget);
      expect(find.textContaining('STAT'), findsWidgets);
    });

    testWidgets('Tapping 1. KAMERA opens PhoneACameraScreen and presents safe exit and quick pills', (WidgetTester tester) async {
      await tester.pumpWidget(const VolleyLiveApp());
      await tester.pump(const Duration(milliseconds: 100));

      // Klikamy 1. KAMERA
      await tester.tap(find.text('1. KAMERA'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(PhoneACameraScreen), findsOneWidget);
      expect(find.textContaining('MENU'), findsWidgets);
      expect(find.textContaining('SĘDZIA'), findsWidgets);
      expect(find.textContaining('STATYSTYKI'), findsWidgets);
    });

    testWidgets('Can quick-switch from Camera directly to Scorer screen without stopping camera', (WidgetTester tester) async {
      await tester.pumpWidget(const VolleyLiveApp());
      await tester.pump(const Duration(milliseconds: 100));

      AppRouter.router.go(AppRouter.cameraRoute);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Szybkie przełączenie na Sędzia
      final sedziaFinder = find.widgetWithText(InkWell, 'SĘDZIA');
      expect(sedziaFinder, findsWidgets);
      await tester.tap(sedziaFinder.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(PhoneBScorerScreen), findsOneWidget);
      expect(find.text('MENU'), findsWidgets);
    });

    testWidgets('Scorer screen displays [MENU] and bottom navigation allows 1-tap jump to Camera and Stats', (WidgetTester tester) async {
      await tester.pumpWidget(const VolleyLiveApp());
      await tester.pump(const Duration(milliseconds: 100));

      AppRouter.router.go(AppRouter.scorerRoute);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Weryfikacja przycisków w dolnym pasku nawigacyjnym: SĘDZIA, KAMERA, STATS
      expect(find.text('KAMERA'), findsWidgets);
      expect(find.text('STATS'), findsWidgets);

      // Tapping [MENU] returns safely to initialRoute
      await tester.tap(find.text('MENU').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(ModeSelectScreen), findsWidgets);
      expect(AppRouter.router.routeInformationProvider.value.uri.path, equals(AppRouter.initialRoute));
    });

    testWidgets('Statistician screen has top HUD exit button and quick jump to Camera and Scorer', (WidgetTester tester) async {
      await tester.pumpWidget(const VolleyLiveApp());
      await tester.pump(const Duration(milliseconds: 100));

      AppRouter.router.go(AppRouter.statisticianRoute);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('PANEL STATYSTYKA MVP'), findsOneWidget);
      expect(find.byTooltip('Przejdź do Kamery'), findsOneWidget);
      expect(find.byTooltip('Przejdź do Kokpitu Sędziego'), findsOneWidget);

      // Back icon button in top bar navigates back safely
      final backButtonFinder = find.byTooltip('Wróć');
      expect(backButtonFinder, findsOneWidget);
      await tester.tap(backButtonFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(ModeSelectScreen), findsWidgets);
      expect(AppRouter.router.routeInformationProvider.value.uri.path, equals(AppRouter.initialRoute));
    });

    testWidgets('Phone A Join Screen exits safely to initialRoute', (WidgetTester tester) async {
      await tester.pumpWidget(const VolleyLiveApp());
      await tester.pump(const Duration(milliseconds: 100));

      AppRouter.router.go(AppRouter.cameraPairRoute);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(PhoneAJoinScreen), findsOneWidget);

      final backBtn = find.byTooltip('Wróć do menu');
      expect(backBtn, findsOneWidget);
      await tester.tap(backBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(ModeSelectScreen), findsWidgets);
      expect(AppRouter.router.routeInformationProvider.value.uri.path, equals(AppRouter.initialRoute));
    });

    testWidgets('Phone B Setup Screen exits safely to initialRoute', (WidgetTester tester) async {
      await tester.pumpWidget(const VolleyLiveApp());
      await tester.pump(const Duration(milliseconds: 100));

      AppRouter.router.go(AppRouter.scorerSetupRoute);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(PhoneBMatchSetupScreen), findsOneWidget);

      final backBtn = find.byTooltip('Wróć do menu');
      expect(backBtn, findsOneWidget);
      await tester.tap(backBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(ModeSelectScreen), findsWidgets);
      expect(AppRouter.router.routeInformationProvider.value.uri.path, equals(AppRouter.initialRoute));
    });

    testWidgets('When camera recording is active, ModeSelectScreen displays persistent recording banner', (WidgetTester tester) async {
      await tester.pumpWidget(const VolleyLiveApp());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(ModeSelectScreen), findsWidgets);
      final BuildContext context = tester.element(find.byType(ModeSelectScreen).first);
      final cameraProvider = Provider.of<CameraProvider>(context, listen: false);

      // Uruchomienie nagrywania (start)
      await cameraProvider.toggleMasterRecording();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Sprawdzamy czy na ekranie głównym jest baner aktywnego nagrywania w tle
      expect(find.textContaining('KAMERA NAGRYWA W TLE'), findsOneWidget);
      expect(find.text('PODGLĄD KAMERY'), findsOneWidget);

      // Zatrzymujemy nagrywanie
      await cameraProvider.toggleMasterRecording();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Bezpieczne odmontowanie drzewa widgetów (zatrzymuje animacje PulseDot i zwalnia zasoby)
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}
