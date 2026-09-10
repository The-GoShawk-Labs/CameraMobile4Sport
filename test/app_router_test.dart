import 'package:flutter_test/flutter_test.dart';
import 'package:volleylive/core/router/app_router.dart';
import 'package:volleylive/main.dart';

void main() {
  group('AppRouter Navigation & Routes Tests', () {
    testWidgets('App initializes at ModeSelectScreen route', (WidgetTester tester) async {
      await tester.pumpWidget(const VolleyLiveApp());
      await tester.pump(const Duration(milliseconds: 100));

      expect(AppRouter.router.routeInformationProvider.value.uri.path, equals('/'));
      expect(find.text('VolleyLive Pro'), findsOneWidget);
    });

    testWidgets('Can navigate to Camera Pair screen via router', (WidgetTester tester) async {
      await tester.pumpWidget(const VolleyLiveApp());
      await tester.pump(const Duration(milliseconds: 100));

      AppRouter.router.go(AppRouter.cameraPairRoute);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('POŁĄCZ JAKO KAMERA (PHONE A)'), findsOneWidget);
      expect(find.text('SKANUJ KOD QR Z EKRANU B'), findsOneWidget);
    });

    testWidgets('Can navigate to Scorer Setup screen via router', (WidgetTester tester) async {
      await tester.pumpWidget(const VolleyLiveApp());
      await tester.pump(const Duration(milliseconds: 100));

      AppRouter.router.go(AppRouter.scorerSetupRoute);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('KONFIGURACJA PRZEDMECZOWA'), findsOneWidget);
      expect(find.text('GOSPODARZE (DRUŻYNA A)'), findsOneWidget);
    });

    testWidgets('Can navigate to Scorer Cockpit screen via router', (WidgetTester tester) async {
      await tester.pumpWidget(const VolleyLiveApp());
      await tester.pump(const Duration(milliseconds: 100));

      AppRouter.router.go(AppRouter.scorerRoute);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('AZS KRAKÓW'), findsWidgets);
      expect(find.text('LEGIA WARSZAWA'), findsWidgets);
    });

    testWidgets('Can navigate to Camera Cockpit screen via router', (WidgetTester tester) async {
      await tester.pumpWidget(const VolleyLiveApp());
      await tester.pump(const Duration(milliseconds: 100));

      AppRouter.router.go(AppRouter.cameraRoute);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('MASTER REC: GOTOWY'), findsOneWidget);
      expect(find.textContaining('PODGLĄD TRANSMISJI'), findsOneWidget);
    });

    testWidgets('Can navigate to Statistician screen via router', (WidgetTester tester) async {
      await tester.pumpWidget(const VolleyLiveApp());
      await tester.pump(const Duration(milliseconds: 100));

      AppRouter.router.go(AppRouter.statisticianRoute);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('PANEL STATYSTYKA MVP'), findsOneWidget);
    });
  });
}
