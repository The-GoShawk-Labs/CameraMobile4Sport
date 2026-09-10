import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:volleylive/domain/models/court_homography.dart';
import 'package:volleylive/presentation/providers/court_statistician_provider.dart';
import 'package:volleylive/presentation/providers/match_provider.dart';
import 'package:volleylive/presentation/screens/statistician/statistician_screen.dart';
import 'package:volleylive/presentation/widgets/pip_video_player_overlay.dart';
import 'package:volleylive/presentation/widgets/tactical_2d_court_view.dart';

void main() {
  group('CourtStatisticianProvider PiP & Pitch Zone State Tests', () {
    late CourtStatisticianProvider provider;

    setUp(() {
      provider = CourtStatisticianProvider();
    });

    test('Initializes with default tactical 2D court, PiP visible and normal size', () {
      expect(provider.courtDisplayMode, CourtDisplayMode.tactical2D);
      expect(provider.isFullScreenCourt, false);
      expect(provider.isPipVisible, true);
      expect(provider.pipSizeState, PipSizeState.normal);
      expect(provider.playbackSpeed, 1.0);
      expect(provider.gridMode, ZoneGridMode.zones6);
    });

    test('Can toggle full screen court mode', () {
      expect(provider.isFullScreenCourt, false);
      provider.toggleFullScreenCourt();
      expect(provider.isFullScreenCourt, true);
      provider.toggleFullScreenCourt();
      expect(provider.isFullScreenCourt, false);
    });

    test('Can switch court display mode between 2D and camera perspective', () {
      provider.setCourtDisplayMode(CourtDisplayMode.cameraPerspective);
      expect(provider.courtDisplayMode, CourtDisplayMode.cameraPerspective);
      provider.setCourtDisplayMode(CourtDisplayMode.tactical2D);
      expect(provider.courtDisplayMode, CourtDisplayMode.tactical2D);
    });

    test('Can toggle PiP visibility and cycle PiP sizes', () {
      provider.togglePipVisibility();
      expect(provider.isPipVisible, false);
      provider.togglePipVisibility();
      expect(provider.isPipVisible, true);

      expect(provider.pipSizeState, PipSizeState.normal);
      provider.togglePipExpanded();
      expect(provider.pipSizeState, PipSizeState.expanded);
      provider.togglePipExpanded();
      expect(provider.pipSizeState, PipSizeState.miniPill);
      provider.togglePipExpanded();
      expect(provider.pipSizeState, PipSizeState.normal);
    });

    test('Clamps PiP position within viewport bounds when dragged', () {
      const viewport = Size(400, 800);
      provider.setPipPositionDirect(const Offset(10, 10));

      // Drag to right
      provider.updatePipPosition(const Offset(100, 200), clampBounds: viewport);
      expect(provider.pipPosition.dx, 110.0);
      expect(provider.pipPosition.dy, 210.0);

      // Drag beyond bottom right
      provider.updatePipPosition(const Offset(500, 800), clampBounds: viewport);
      final maxX = viewport.width - provider.pipSizeState.width;
      final maxY = viewport.height - provider.pipSizeState.height;
      expect(provider.pipPosition.dx, maxX);
      expect(provider.pipPosition.dy, maxY);
    });

    test('Triggers rewind offset (-5s, -10s) and adjusts playback speed', () {
      provider.triggerRewind(5);
      expect(provider.lastRewindOffsetSeconds, 5);
      expect(provider.lastRewindTriggerTime, isNotNull);

      provider.triggerRewind(10);
      expect(provider.lastRewindOffsetSeconds, 10);

      provider.setPlaybackSpeed(0.5);
      expect(provider.playbackSpeed, 0.5);
      provider.setPlaybackSpeed(1.5);
      expect(provider.playbackSpeed, 1.5);
    });

    test('Records stat events on court zones, tracks history and computes heatmap', () {
      final zones = provider.engine.generateZones(ZoneGridMode.zones6);
      expect(zones, isNotEmpty);

      final zone1 = zones.first;
      provider.setActionType('ATAK');
      provider.setQualityGrade('#');
      provider.setSelectedTeam('TEAM A');

      provider.recordCurrentStatEvent(targetZone: zone1);
      expect(provider.eventsHistory.length, 1);
      expect(provider.eventsHistory.first.zone.id, zone1.id);
      expect(provider.eventsHistory.first.actionType, 'ATAK');
      expect(provider.eventsHistory.first.qualityGrade, '#');

      final heatmap = provider.getZoneHeatmapIntensities();
      expect(heatmap[zone1.id], 1.0);

      provider.undoLastEvent();
      expect(provider.eventsHistory.isEmpty, true);
    });
  });

  group('StatisticianScreen UI & PiP Overlay Widget Tests', () {
    Widget createWidgetUnderTest({
      CourtStatisticianProvider? statsProvider,
      MatchProvider? matchProvider,
    }) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<CourtStatisticianProvider>(
            create: (_) => statsProvider ?? CourtStatisticianProvider(),
          ),
          ChangeNotifierProvider<MatchProvider>(
            create: (_) => matchProvider ?? MatchProvider(),
          ),
        ],
        child: const MaterialApp(
          home: StatisticianScreen(),
        ),
      );
    }

    testWidgets('Renders top HUD, action deck, 2D tactical court and PiP overlay', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final provider = CourtStatisticianProvider();
      await tester.pumpWidget(createWidgetUnderTest(statsProvider: provider));
      await tester.pumpAndSettle();

      expect(find.text('PANEL STATYSTYKA MVP'), findsOneWidget);
      expect(find.byType(Tactical2DCourtView), findsOneWidget);
      expect(find.byType(PipVideoPlayerOverlay), findsOneWidget);

      // Verify Action Deck items
      expect(find.text('ZAGRYWKA'), findsOneWidget);
      expect(find.text('ATAK'), findsOneWidget);
      expect(find.text('BLOK'), findsOneWidget);
      expect(find.text('#'), findsOneWidget);
      expect(find.text('+'), findsOneWidget);

      // Verify PiP rewind buttons
      expect(find.text('-10s'), findsOneWidget);
      expect(find.text('-5s'), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);
    });

    testWidgets('Tapping -5s and -10s on PiP overlay triggers replay seek without error', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final provider = CourtStatisticianProvider();
      await tester.pumpWidget(createWidgetUnderTest(statsProvider: provider));
      await tester.pumpAndSettle();

      final rewind5Btn = find.text('-5s');
      expect(rewind5Btn, findsOneWidget);
      await tester.tap(rewind5Btn);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('-5 s REPLAY'), findsOneWidget);

      final rewind10Btn = find.text('-10s');
      expect(rewind10Btn, findsOneWidget);
      await tester.tap(rewind10Btn);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('-10 s REPLAY'), findsOneWidget);
    });

    testWidgets('Toggling full screen court switches layout', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final provider = CourtStatisticianProvider();
      await tester.pumpWidget(createWidgetUnderTest(statsProvider: provider));
      await tester.pumpAndSettle();

      final fullScreenBtn = find.byIcon(Icons.fullscreen);
      expect(fullScreenBtn, findsOneWidget);

      await tester.tap(fullScreenBtn);
      await tester.pumpAndSettle();

      expect(provider.isFullScreenCourt, true);
      expect(find.byIcon(Icons.fullscreen_exit), findsOneWidget);
    });

    testWidgets('Tapping pitch zone on Tactical2DCourtView logs event', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final provider = CourtStatisticianProvider();
      await tester.pumpWidget(createWidgetUnderTest(statsProvider: provider));
      await tester.pumpAndSettle();

      final tacticalCourt = find.byType(Tactical2DCourtView);
      expect(tacticalCourt, findsOneWidget);

      // Tap on tactical court center
      await tester.tap(tacticalCourt);
      await tester.pump(const Duration(milliseconds: 100));

      expect(provider.eventsHistory.length, 1);
    });
  });
}
