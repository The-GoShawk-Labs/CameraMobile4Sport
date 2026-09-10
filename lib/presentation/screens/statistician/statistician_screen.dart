import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:volleylive/core/theme/app_theme.dart';
import 'package:volleylive/domain/models/court_homography.dart';
import 'package:volleylive/presentation/providers/court_statistician_provider.dart';
import 'package:volleylive/presentation/providers/match_provider.dart';
import 'package:volleylive/presentation/widgets/court_homography_overlay.dart';
import 'package:volleylive/presentation/widgets/pip_video_player_overlay.dart';
import 'package:volleylive/presentation/widgets/tactical_2d_court_view.dart';

class StatisticianScreen extends StatefulWidget {
  const StatisticianScreen({super.key});

  @override
  State<StatisticianScreen> createState() => _StatisticianScreenState();
}

class _StatisticianScreenState extends State<StatisticianScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isInitialFitted = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showZoneRecordedFeedback(BuildContext context, CourtZone zone, CourtStatisticianProvider statsProvider) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF16253B),
        duration: const Duration(milliseconds: 700),
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: AppTheme.greenLive, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${statsProvider.selectedTeam}: ${statsProvider.selectedActionType} [${statsProvider.selectedQualityGrade}] ➔ ${zone.fullDisplayLabel}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statsProvider = context.watch<CourtStatisticianProvider>();
    final matchProvider = context.watch<MatchProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF070A10),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, screenConstraints) {
            final screenSize = Size(screenConstraints.maxWidth, screenConstraints.maxHeight);

            return Stack(
              fit: StackFit.expand,
              children: [
                // GŁÓWNA STRUKTURA EKRANU (PEŁNY EKRAN LUB UKŁAD Z ZAKŁADKAMI)
                if (statsProvider.isFullScreenCourt)
                  _buildFullScreenLayout(context, statsProvider, matchProvider)
                else
                  _buildStandardLayout(context, statsProvider, matchProvider),

                // PŁYWAJĄCY ODTWARZACZ WIDEO PiP (POWTÓRKI -5s, -10s, DRAG & DROP)
                if (statsProvider.isPipVisible)
                  PipVideoPlayerOverlay(
                    provider: statsProvider,
                    viewportSize: screenSize,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Układ pełnoekranowy (Full-Screen Pitch Mode) dla maksymalnego obszaru makiety
  Widget _buildFullScreenLayout(
    BuildContext context,
    CourtStatisticianProvider statsProvider,
    MatchProvider matchProvider,
  ) {
    return Column(
      children: [
        // Kompaktowy pasek HUD na samej górze
        _buildTopHUD(context, statsProvider, isFullScreen: true),

        // Pełnoekranowa makieta boiska
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildMainCourtSurface(context, statsProvider),

              // Pływający przycisk Undo w prawym górnym rogu
              Positioned(
                top: 10,
                right: 12,
                child: ElevatedButton.icon(
                  onPressed: statsProvider.eventsHistory.isEmpty ? null : () => statsProvider.undoLastEvent(),
                  icon: const Icon(Icons.undo, size: 15),
                  label: Text('UNDO (${statsProvider.eventsHistory.length})'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B).withValues(alpha: 0.9),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    textStyle: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Pasek kodowania akcji na dole
        _buildActionDeck(context, statsProvider, matchProvider),
      ],
    );
  }

  /// Standardowy układ z zakładkami konfiguracyjnymi i analitycznymi
  Widget _buildStandardLayout(
    BuildContext context,
    CourtStatisticianProvider statsProvider,
    MatchProvider matchProvider,
  ) {
    return Column(
      children: [
        // 1. GÓRNY PASEK HUD STATYSTYKA
        _buildTopHUD(context, statsProvider, isFullScreen: false),

        // 2. GŁÓWNY WIDOK BOISKA (2D LUB PERSPEKTYWA)
        Expanded(
          flex: 11,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildMainCourtSurface(context, statsProvider),

              // Status kalibracji / trybu
              Positioned(
                top: 8,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: statsProvider.courtDisplayMode == CourtDisplayMode.tactical2D
                              ? AppTheme.cyanAccent
                              : (statsProvider.calibrationMode == CalibrationMode.automaticAlgorithm
                                  ? AppTheme.greenLive
                                  : AppTheme.amberAccent),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        statsProvider.courtDisplayMode == CourtDisplayMode.tactical2D
                            ? 'MAKIETA 2D (${statsProvider.gridMode.title})'
                            : (statsProvider.calibrationMode == CalibrationMode.automaticAlgorithm
                                ? 'AUTO AI: ${(statsProvider.algorithmConfidence * 100).toStringAsFixed(1)}%'
                                : 'PERSPEKTYWA (P1-P4)'),
                        style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),

              // Przycisk szybkiego cofania (Undo)
              Positioned(
                bottom: 10,
                right: 12,
                child: ElevatedButton.icon(
                  onPressed: statsProvider.eventsHistory.isEmpty ? null : () => statsProvider.undoLastEvent(),
                  icon: const Icon(Icons.undo, size: 15),
                  label: Text('UNDO (${statsProvider.eventsHistory.length})'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B).withValues(alpha: 0.9),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    textStyle: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 3. SZYBKI PANEL KODOWANIA AKCJI STATYSTYCZNYCH (ACTION DECK)
        _buildActionDeck(context, statsProvider, matchProvider),

        // 4. DOLNE ZAKŁADKI KONTROLNE
        Container(
          color: const Color(0xFF0F1726),
          child: TabBar(
            controller: _tabController,
            indicatorColor: AppTheme.cyanAccent,
            labelColor: AppTheme.cyanAccent,
            unselectedLabelColor: AppTheme.textMuted,
            labelStyle: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900),
            tabs: const [
              Tab(icon: Icon(Icons.grid_4x4, size: 16), text: 'STREFY & KAMERA'),
              Tab(icon: Icon(Icons.list_alt, size: 16), text: 'REJESTR AKCJI'),
              Tab(icon: Icon(Icons.analytics_outlined, size: 16), text: 'HEATMAPA'),
            ],
          ),
        ),

        Expanded(
          flex: 8,
          child: Container(
            color: const Color(0xFF0A0F1A),
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildConfigurationTab(context, statsProvider),
                _buildEventsLogTab(context, statsProvider),
                _buildHeatmapSummaryTab(context, statsProvider),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Główna powierzchnia boiska z przełączaniem między 2D a Perspektywą Kamery
  Widget _buildMainCourtSurface(BuildContext context, CourtStatisticianProvider statsProvider) {
    if (statsProvider.courtDisplayMode == CourtDisplayMode.tactical2D) {
      return Container(
        padding: const EdgeInsets.all(8),
        color: const Color(0xFF070A10),
        child: Tactical2DCourtView(
          provider: statsProvider,
          onZoneTapped: (zone) => _showZoneRecordedFeedback(context, zone, statsProvider),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!_isInitialFitted && constraints.maxWidth > 0 && constraints.maxHeight > 0) {
          _isInitialFitted = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            statsProvider.fitToViewport(Size(constraints.maxWidth, constraints.maxHeight));
          });
        }

        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0D1424), Color(0xFF070A10)],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _StaticCameraCourtBackgroundPainter(
                  orientation: statsProvider.orientation,
                ),
              ),
              CourtHomographyOverlay(
                provider: statsProvider,
                onZoneTapped: (zone) => _showZoneRecordedFeedback(context, zone, statsProvider),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopHUD(
    BuildContext context,
    CourtStatisticianProvider statsProvider, {
    required bool isFullScreen,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: const Color(0xFF0A0F1A),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'PANEL STATYSTYKA MVP',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Smartfon Sterujący • ${statsProvider.courtDisplayMode.shortLabel}',
                  style: const TextStyle(fontSize: 9, color: AppTheme.cyanAccent),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Przełącznik Pełny Ekran Boiska (Full Screen Pitch Toggle)
              IconButton(
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                icon: Icon(
                  isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  color: isFullScreen ? AppTheme.amberAccent : Colors.white,
                  size: 20,
                ),
                tooltip: isFullScreen ? 'Wyjdź z pełnego ekranu' : 'Pełny ekran makiety boiska',
                onPressed: () => statsProvider.toggleFullScreenCourt(),
              ),
              const SizedBox(width: 4),

              // Przełącznik Trybu Widoku: 2D vs Perspektywa Kamery
              IconButton(
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                icon: Icon(
                  statsProvider.courtDisplayMode == CourtDisplayMode.tactical2D ? Icons.crop_square : Icons.videocam,
                  color: AppTheme.cyanAccent,
                  size: 18,
                ),
                tooltip: 'Zmień tryb widoku (${statsProvider.courtDisplayMode.shortLabel})',
                onPressed: () {
                  final nextMode = statsProvider.courtDisplayMode == CourtDisplayMode.tactical2D
                      ? CourtDisplayMode.cameraPerspective
                      : CourtDisplayMode.tactical2D;
                  statsProvider.setCourtDisplayMode(nextMode);
                },
              ),
              const SizedBox(width: 4),

              // Pokaż / Ukryj Pływające Okno PiP Wideo
              IconButton(
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                icon: Icon(
                  statsProvider.isPipVisible ? Icons.picture_in_picture_alt : Icons.picture_in_picture_outlined,
                  color: statsProvider.isPipVisible ? AppTheme.amberAccent : Colors.white54,
                  size: 18,
                ),
                tooltip: statsProvider.isPipVisible ? 'Ukryj wideo PiP' : 'Pokaż wideo PiP',
                onPressed: () => statsProvider.togglePipVisibility(),
              ),
              const SizedBox(width: 4),

              // Przycisk obrotu boiska o 90° (Z tyłu <-> Z boku)
              IconButton(
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.rotate_90_degrees_cw, color: AppTheme.cyanAccent, size: 18),
                tooltip: 'Obróć boisko o 90° (${statsProvider.orientation.shortLabel})',
                onPressed: () {
                  final size = MediaQuery.of(context).size;
                  statsProvider.rotateCourt90(currentViewport: Size(size.width, size.height * 0.5));
                },
              ),
              const SizedBox(width: 4),

              // Heatmap Toggle
              IconButton(
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                icon: Icon(
                  statsProvider.showHeatmap ? Icons.local_fire_department : Icons.local_fire_department_outlined,
                  color: statsProvider.showHeatmap ? AppTheme.amberAccent : Colors.white60,
                  size: 18,
                ),
                tooltip: 'Pokaż Heatmapę',
                onPressed: () => statsProvider.toggleHeatmap(),
              ),
              const SizedBox(width: 4),

              // Etykiety Stref Toggle
              IconButton(
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                icon: Icon(
                  statsProvider.showGridLabels ? Icons.visibility : Icons.visibility_off,
                  color: statsProvider.showGridLabels ? AppTheme.cyanAccent : Colors.white60,
                  size: 18,
                ),
                tooltip: 'Pokaż/Ukryj etykiety stref',
                onPressed: () => statsProvider.toggleGridLabels(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionDeck(BuildContext context, CourtStatisticianProvider statsProvider, MatchProvider matchProvider) {
    final actions = ['ZAGRYWKA', 'PRZYJĘCIE', 'ROZEGRANIE', 'ATAK', 'BLOK', 'OBRONA'];
    final grades = [
      {'code': '#', 'name': 'Perfekt'},
      {'code': '+', 'name': 'Dobra'},
      {'code': '!', 'name': 'Neutral'},
      {'code': '-', 'name': 'Słaba'},
      {'code': '/', 'name': 'Błąd'},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: const Color(0xFF0F1726),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Wybór Drużyny + Typu Akcji
          Row(
            children: [
              // Przełącznik Drużyny
              InkWell(
                onTap: () {
                  statsProvider.setSelectedTeam(
                    statsProvider.selectedTeam == 'TEAM A' ? 'TEAM B' : 'TEAM A',
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: statsProvider.selectedTeam == 'TEAM A'
                        ? AppTheme.cyanAccent.withValues(alpha: 0.2)
                        : AppTheme.amberAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: statsProvider.selectedTeam == 'TEAM A' ? AppTheme.cyanAccent : AppTheme.amberAccent,
                    ),
                  ),
                  child: Text(
                    statsProvider.selectedTeam == 'TEAM A'
                        ? matchProvider.session.teamA
                        : matchProvider.session.teamB,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: statsProvider.selectedTeam == 'TEAM A' ? AppTheme.cyanAccent : AppTheme.amberAccent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Lista akcji sportowych
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: actions.map((act) {
                      final isSelected = statsProvider.selectedActionType == act;
                      return Padding(
                        padding: const EdgeInsets.only(right: 5),
                        child: ChoiceChip(
                          label: Text(act),
                          selected: isSelected,
                          selectedColor: AppTheme.cyanAccent,
                          labelStyle: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.black : Colors.white70,
                          ),
                          backgroundColor: const Color(0xFF1E293B),
                          onSelected: (_) => statsProvider.setActionType(act),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),

          // Wybór Oceny Jakości (#, +, !, -, /)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: grades.map((g) {
              final isSelected = statsProvider.selectedQualityGrade == g['code'];
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: InkWell(
                    onTap: () => statsProvider.setQualityGrade(g['code']!),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.amberAccent : const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: isSelected ? Colors.white : Colors.white10),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            g['code']!,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: isSelected ? Colors.black : Colors.white,
                            ),
                          ),
                          Text(
                            g['name']!,
                            style: TextStyle(
                              fontSize: 7.5,
                              color: isSelected ? Colors.black87 : AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigurationTab(BuildContext context, CourtStatisticianProvider statsProvider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Tryb Wyświetlania Makiety
          const Text(
            'TRYB WIDOKU MAKIETY BOISKA',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppTheme.cyanAccent),
          ),
          const SizedBox(height: 8),
          SegmentedButton<CourtDisplayMode>(
            segments: const [
              ButtonSegment(
                value: CourtDisplayMode.tactical2D,
                label: Text('Makieta Taktyczna 2D'),
                icon: Icon(Icons.grid_view, size: 14),
              ),
              ButtonSegment(
                value: CourtDisplayMode.cameraPerspective,
                label: Text('Perspektywa Kamery'),
                icon: Icon(Icons.videocam, size: 14),
              ),
            ],
            selected: {statsProvider.courtDisplayMode},
            onSelectionChanged: (val) => statsProvider.setCourtDisplayMode(val.first),
          ),
          const SizedBox(height: 16),

          // 2. Podział Stref Boiska
          const Text(
            'PODZIAŁ STREF BOISKA',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppTheme.cyanAccent),
          ),
          const SizedBox(height: 8),
          SegmentedButton<ZoneGridMode>(
            segments: const [
              ButtonSegment(
                value: ZoneGridMode.zones6,
                label: Text('6 / stronę (12 całkiem)'),
                icon: Icon(Icons.grid_3x3, size: 14),
              ),
              ButtonSegment(
                value: ZoneGridMode.zones9,
                label: Text('9 / stronę (18 całkiem)'),
                icon: Icon(Icons.grid_view, size: 14),
              ),
              ButtonSegment(
                value: ZoneGridMode.zones36Subdivided,
                label: Text('36 / stronę (72 całkiem)'),
                icon: Icon(Icons.apps, size: 14),
              ),
            ],
            selected: {statsProvider.gridMode},
            onSelectionChanged: (val) => statsProvider.setGridMode(val.first),
          ),
          const SizedBox(height: 16),

          // 3. Kąt Widzenia Kamery / Orientacja Boiska
          const Text(
            'KĄT WIDZENIA KAMERY / POZYCJA STATYWU',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppTheme.cyanAccent),
          ),
          const SizedBox(height: 8),
          SegmentedButton<CourtOrientation>(
            segments: const [
              ButtonSegment(
                value: CourtOrientation.endlineNearBottom,
                label: Text('Z tyłu (0°)'),
                icon: Icon(Icons.vertical_align_bottom, size: 14),
              ),
              ButtonSegment(
                value: CourtOrientation.sidelineLeftToRight,
                label: Text('Z boku (90° L➔P)'),
                icon: Icon(Icons.view_column, size: 14),
              ),
              ButtonSegment(
                value: CourtOrientation.endlineNearTop,
                label: Text('Z tyłu (180°)'),
                icon: Icon(Icons.vertical_align_top, size: 14),
              ),
              ButtonSegment(
                value: CourtOrientation.sidelineRightToLeft,
                label: Text('Z boku (270° P➔L)'),
                icon: Icon(Icons.view_column_outlined, size: 14),
              ),
            ],
            selected: {statsProvider.orientation},
            onSelectionChanged: (val) {
              final size = MediaQuery.of(context).size;
              statsProvider.setOrientation(val.first, currentViewport: Size(size.width, size.height * 0.45));
            },
          ),
          const SizedBox(height: 16),

          // 4. Tryb Kalibracji Perspektywy (gdy wybrany tryb perspektywiczny)
          if (statsProvider.courtDisplayMode == CourtDisplayMode.cameraPerspective) ...[
            const Text(
              'TRYB KALIBRACJI PERSPEKTYWY',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppTheme.cyanAccent),
            ),
            const SizedBox(height: 8),
            SegmentedButton<CalibrationMode>(
              segments: const [
                ButtonSegment(
                  value: CalibrationMode.manual,
                  label: Text('Ręczny (Piny P1-P4)'),
                  icon: Icon(Icons.touch_app, size: 14),
                ),
                ButtonSegment(
                  value: CalibrationMode.automaticAlgorithm,
                  label: Text('Algorytm Live AI'),
                  icon: Icon(Icons.auto_awesome, size: 14),
                ),
              ],
              selected: {statsProvider.calibrationMode},
              onSelectionChanged: (val) => statsProvider.setCalibrationMode(val.first),
            ),
            if (statsProvider.calibrationMode == CalibrationMode.automaticAlgorithm) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF16253B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.greenLive.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('WYBÓR SILNIKA DETEKCJI GEOMETRII:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.greenLive)),
                    const SizedBox(height: 6),
                    DropdownButton<HomographyAlgorithm>(
                      value: statsProvider.activeAlgorithm,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF1A2638),
                      underline: const SizedBox(),
                      items: HomographyAlgorithm.values.map((algo) {
                        return DropdownMenuItem(
                          value: algo,
                          child: Text('${algo.name} (~${(algo.typicalAccuracy * 100).toInt()}%)', style: const TextStyle(fontSize: 12, color: Colors.white)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) statsProvider.setAlgorithm(val);
                      },
                    ),
                    const SizedBox(height: 6),
                    Text(
                      statsProvider.activeAlgorithm.description,
                      style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildEventsLogTab(BuildContext context, CourtStatisticianProvider statsProvider) {
    if (statsProvider.eventsHistory.isEmpty) {
      return const Center(
        child: Text(
          'Brak zarejestrowanych zagrań.\nDotknij strefy na makiecie boiska, aby zapisać akcję.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ŁĄCZNIE ZDARZEŃ: ${statsProvider.eventsHistory.length}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70),
              ),
              TextButton.icon(
                onPressed: () => statsProvider.clearStats(),
                icon: const Icon(Icons.delete_outline, size: 14, color: Colors.redAccent),
                label: const Text('Wyczyść rejestr', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: statsProvider.eventsHistory.length,
            separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1),
            itemBuilder: (context, index) {
              final ev = statsProvider.eventsHistory[index];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: ev.teamName == 'TEAM A'
                        ? AppTheme.cyanAccent.withValues(alpha: 0.2)
                        : AppTheme.amberAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    ev.zone.label,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Colors.white),
                  ),
                ),
                title: Text(
                  '${ev.teamName}: ${ev.actionType} [${ev.qualityGrade}]',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                ),
                subtitle: Text(
                  'Godz. ${ev.timestamp.hour.toString().padLeft(2, '0')}:${ev.timestamp.minute.toString().padLeft(2, '0')}:${ev.timestamp.second.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeatmapSummaryTab(BuildContext context, CourtStatisticianProvider statsProvider) {
    final heatmap = statsProvider.getZoneHeatmapIntensities();

    if (heatmap.isEmpty) {
      return const Center(
        child: Text(
          'Brak danych do wygenerowania analizy ciepła stref.\nZarejestruj kilka akcji dotykając strefy boiska.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
        ),
      );
    }

    final sortedEntries = heatmap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: sortedEntries.length,
      itemBuilder: (context, index) {
        final entry = sortedEntries[index];
        final percent = (entry.value * 100).toStringAsFixed(0);

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              SizedBox(
                width: 60,
                child: Text(
                  entry.key,
                  style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 12),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: entry.value,
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      entry.value > 0.6 ? Colors.redAccent : (entry.value > 0.3 ? AppTheme.amberAccent : AppTheme.greenLive),
                    ),
                    minHeight: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 45,
                child: Text(
                  '$percent%',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70, fontSize: 11),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StaticCameraCourtBackgroundPainter extends CustomPainter {
  final CourtOrientation orientation;

  _StaticCameraCourtBackgroundPainter({this.orientation = CourtOrientation.endlineNearBottom});

  @override
  void paint(Canvas canvas, Size size) {
    final courtPaint = Paint()
      ..color = const Color(0xFF16253B)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);

    if (orientation.isSideline) {
      final rect = Rect.fromCenter(center: center, width: size.width * 0.92, height: size.height * 0.70);
      canvas.drawRect(rect, courtPaint);
      canvas.drawLine(Offset(center.dx, rect.top), Offset(center.dx, rect.bottom), courtPaint..strokeWidth = 2.0);
    } else {
      final rect = Rect.fromCenter(center: center, width: size.width * 0.84, height: size.height * 0.76);
      canvas.drawRect(rect, courtPaint);
      canvas.drawLine(Offset(rect.left, center.dy), Offset(rect.right, center.dy), courtPaint..strokeWidth = 2.0);
    }
  }

  @override
  bool shouldRepaint(covariant _StaticCameraCourtBackgroundPainter oldDelegate) =>
      oldDelegate.orientation != orientation;
}
