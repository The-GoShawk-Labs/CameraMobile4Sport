import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:volleylive/domain/models/court_homography.dart';

class CourtStatisticianProvider extends ChangeNotifier {
  ZoneGridMode _gridMode = ZoneGridMode.zones6;
  CalibrationMode _calibrationMode = CalibrationMode.manual;
  HomographyAlgorithm _activeAlgorithm = HomographyAlgorithm.deepKeypoints;
  CourtOrientation _orientation = CourtOrientation.endlineNearBottom;
  CourtDisplayMode _courtDisplayMode = CourtDisplayMode.tactical2D;
  bool _isFullScreenCourt = false;

  // Pływający odtwarzacz PiP
  bool _isPipVisible = true;
  PipSizeState _pipSizeState = PipSizeState.normal;
  Offset _pipPosition = const Offset(16, 70);
  double _playbackSpeed = 1.0;
  int? _lastRewindOffsetSeconds;
  DateTime? _lastRewindTriggerTime;

  // 4 narożniki perspektywy boiska na ekranie
  // [0] TL, [1] TR, [2] BR, [3] BL
  List<Offset> _screenCorners = [
    const Offset(60, 100),
    const Offset(340, 100),
    const Offset(380, 320),
    const Offset(20, 320),
  ];

  CourtZone? _selectedZone;
  String _selectedActionType = 'ATAK'; // 'ZAGRYWKA', 'ATAK', 'PRZYJĘCIE', 'BLOK', 'OBRONA'
  String _selectedQualityGrade = '#'; // '#', '+', '!', '-', '/'
  String _selectedTeam = 'TEAM A'; // 'TEAM A', 'TEAM B'

  final List<StatEvent> _eventsHistory = [];
  bool _showHeatmap = false;
  bool _showGridLabels = true;

  // Algorytm Live (Symulacja przetwarzania klatek na żywo)
  Timer? _algorithmTimer;
  bool _isAlgorithmRunning = false;
  double _algorithmConfidence = 0.96;
  int _processedFramesCount = 0;

  CourtStatisticianProvider() {
    _initDefaultEngine();
  }

  ZoneGridMode get gridMode => _gridMode;
  CalibrationMode get calibrationMode => _calibrationMode;
  HomographyAlgorithm get activeAlgorithm => _activeAlgorithm;
  CourtOrientation get orientation => _orientation;
  CourtDisplayMode get courtDisplayMode => _courtDisplayMode;
  bool get isFullScreenCourt => _isFullScreenCourt;

  // Gettery PiP
  bool get isPipVisible => _isPipVisible;
  PipSizeState get pipSizeState => _pipSizeState;
  Offset get pipPosition => _pipPosition;
  double get playbackSpeed => _playbackSpeed;
  int? get lastRewindOffsetSeconds => _lastRewindOffsetSeconds;
  DateTime? get lastRewindTriggerTime => _lastRewindTriggerTime;

  List<Offset> get screenCorners => List.unmodifiable(_screenCorners);
  CourtZone? get selectedZone => _selectedZone;
  String get selectedActionType => _selectedActionType;
  String get selectedQualityGrade => _selectedQualityGrade;
  String get selectedTeam => _selectedTeam;
  List<StatEvent> get eventsHistory => List.unmodifiable(_eventsHistory);
  bool get showHeatmap => _showHeatmap;
  bool get showGridLabels => _showGridLabels;
  bool get isAlgorithmRunning => _isAlgorithmRunning;
  double get algorithmConfidence => _algorithmConfidence;
  int get processedFramesCount => _processedFramesCount;

  void toggleFullScreenCourt() {
    _isFullScreenCourt = !_isFullScreenCourt;
    notifyListeners();
  }

  void setFullScreenCourt(bool isFull) {
    if (_isFullScreenCourt == isFull) return;
    _isFullScreenCourt = isFull;
    notifyListeners();
  }

  void setCourtDisplayMode(CourtDisplayMode mode) {
    if (_courtDisplayMode == mode) return;
    _courtDisplayMode = mode;
    notifyListeners();
  }

  void togglePipVisibility() {
    _isPipVisible = !_isPipVisible;
    notifyListeners();
  }

  void setPipVisibility(bool visible) {
    if (_isPipVisible == visible) return;
    _isPipVisible = visible;
    notifyListeners();
  }

  void setPipSizeState(PipSizeState sizeState) {
    _pipSizeState = sizeState;
    notifyListeners();
  }

  void togglePipExpanded() {
    if (_pipSizeState == PipSizeState.normal) {
      _pipSizeState = PipSizeState.expanded;
    } else if (_pipSizeState == PipSizeState.expanded) {
      _pipSizeState = PipSizeState.miniPill;
    } else {
      _pipSizeState = PipSizeState.normal;
    }
    notifyListeners();
  }

  void updatePipPosition(Offset delta, {Size? clampBounds}) {
    double newX = _pipPosition.dx + delta.dx;
    double newY = _pipPosition.dy + delta.dy;

    if (clampBounds != null) {
      final maxX = (clampBounds.width - _pipSizeState.width).clamp(0.0, clampBounds.width);
      final maxY = (clampBounds.height - _pipSizeState.height).clamp(0.0, clampBounds.height);
      newX = newX.clamp(0.0, maxX);
      newY = newY.clamp(0.0, maxY);
    }

    _pipPosition = Offset(newX, newY);
    notifyListeners();
  }

  void setPipPositionDirect(Offset pos) {
    _pipPosition = pos;
    notifyListeners();
  }

  void setPlaybackSpeed(double speed) {
    _playbackSpeed = speed;
    notifyListeners();
  }

  void triggerRewind(int seconds) {
    _lastRewindOffsetSeconds = seconds;
    _lastRewindTriggerTime = DateTime.now();
    notifyListeners();
  }

  HomographyEngine get engine => HomographyEngine(
        screenCorners: _screenCorners,
        orientation: _orientation,
      );

  void _initDefaultEngine() {
    // Domyślna kalibracja
  }

  /// Inicjalizacja domyślnych rogów na podstawie rozmiaru widoku i orientacji
  void fitToViewport(Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    if (_orientation.isSideline) {
      // Widok z boku (boisko leży poziomo w kadrze, siatka pionowo w środku)
      _screenCorners = [
        Offset(w * 0.08, h * 0.15), // Lewy górny
        Offset(w * 0.92, h * 0.15), // Prawy górny
        Offset(w * 0.95, h * 0.85), // Prawy dolny
        Offset(w * 0.05, h * 0.85), // Lewy dolny
      ];
    } else {
      // Widok z tyłu (boisko leży pionowo w kadrze, siatka poziomo w środku)
      _screenCorners = [
        Offset(w * 0.18, h * 0.12), // TL (dalszy koniec)
        Offset(w * 0.82, h * 0.12), // TR (dalszy koniec)
        Offset(w * 0.94, h * 0.88), // BR (bliższy koniec)
        Offset(w * 0.06, h * 0.88), // BL (bliższy koniec)
      ];
    }
    notifyListeners();
  }

  /// Zmiana orientacji boiska (np. widok z boku 90° vs z tyłu 0°)
  void setOrientation(CourtOrientation orient, {Size? currentViewport}) {
    if (_orientation == orient) return;
    _orientation = orient;
    _selectedZone = null;
    if (currentViewport != null) {
      fitToViewport(currentViewport);
    }
    notifyListeners();
  }

  /// Szybki obrót boiska o 90 stopni (kolejna orientacja w cyklu)
  void rotateCourt90({Size? currentViewport}) {
    setOrientation(_orientation.next, currentViewport: currentViewport);
  }

  /// Aktualizacja pozycji pojedynczego narożnika w trybie ręcznym
  void updateCorner(int index, Offset newPos, {Size? clampBounds}) {
    if (index < 0 || index >= _screenCorners.length) return;

    Offset clamped = newPos;
    if (clampBounds != null) {
      clamped = Offset(
        newPos.dx.clamp(0.0, clampBounds.width),
        newPos.dy.clamp(0.0, clampBounds.height),
      );
    }

    _screenCorners[index] = clamped;
    notifyListeners();
  }

  /// Zmiana podziału stref (6, 9, 36)
  void setGridMode(ZoneGridMode mode) {
    _gridMode = mode;
    _selectedZone = null;
    notifyListeners();
  }

  /// Zmiana trybu kalibracji (Ręczny vs Algorytmiczny)
  void setCalibrationMode(CalibrationMode mode) {
    _calibrationMode = mode;
    if (mode == CalibrationMode.automaticAlgorithm) {
      startLiveAlgorithm();
    } else {
      stopLiveAlgorithm();
    }
    notifyListeners();
  }

  /// Zmiana wybranego algorytmu
  void setAlgorithm(HomographyAlgorithm algorithm) {
    _activeAlgorithm = algorithm;
    _algorithmConfidence = algorithm.typicalAccuracy;
    notifyListeners();
  }

  /// Wybór strefy (np. przez dotknięcie na ekranie)
  void selectZone(CourtZone? zone) {
    _selectedZone = zone;
    notifyListeners();
  }

  void setActionType(String action) {
    _selectedActionType = action;
    notifyListeners();
  }

  void setQualityGrade(String grade) {
    _selectedQualityGrade = grade;
    notifyListeners();
  }

  void setSelectedTeam(String team) {
    _selectedTeam = team;
    notifyListeners();
  }

  void toggleHeatmap() {
    _showHeatmap = !_showHeatmap;
    notifyListeners();
  }

  void toggleGridLabels() {
    _showGridLabels = !_showGridLabels;
    notifyListeners();
  }

  /// Zapisanie zdarzenia statystycznego w wybranej strefie
  void recordCurrentStatEvent({CourtZone? targetZone, Offset? tapOffset}) {
    final zoneToRecord = targetZone ?? _selectedZone;
    if (zoneToRecord == null) return;

    final event = StatEvent(
      id: 'SE-${DateTime.now().millisecondsSinceEpoch}',
      timestamp: DateTime.now(),
      actionType: _selectedActionType,
      qualityGrade: _selectedQualityGrade,
      teamName: _selectedTeam,
      zone: zoneToRecord,
      tapLocation: tapOffset ?? zoneToRecord.centerPoint,
    );

    _eventsHistory.insert(0, event);
    notifyListeners();
  }

  /// Cofnięcie ostatniego zdarzenia statystycznego
  void undoLastEvent() {
    if (_eventsHistory.isNotEmpty) {
      _eventsHistory.removeAt(0);
      notifyListeners();
    }
  }

  /// Czyszczenie historii statystyk
  void clearStats() {
    _eventsHistory.clear();
    notifyListeners();
  }

  /// Obliczenie intensywności ciepła strefy dla Heatmapy [0.0 - 1.0]
  Map<String, double> getZoneHeatmapIntensities() {
    if (_eventsHistory.isEmpty) return {};

    final Map<String, int> counts = {};
    int maxCount = 0;

    for (final event in _eventsHistory) {
      final key = event.zone.id;
      counts[key] = (counts[key] ?? 0) + 1;
      if (counts[key]! > maxCount) {
        maxCount = counts[key]!;
      }
    }

    if (maxCount == 0) return {};

    final Map<String, double> intensities = {};
    counts.forEach((key, count) {
      intensities[key] = count / maxCount;
    });

    return intensities;
  }

  /// Reset kalibracji do domyślnego trapezu perspektywicznego
  void resetCalibration({Size? size}) {
    if (size != null) {
      fitToViewport(size);
    } else {
      _screenCorners = [
        const Offset(60, 100),
        const Offset(340, 100),
        const Offset(380, 320),
        const Offset(20, 320),
      ];
      notifyListeners();
    }
  }

  /// Uruchomienie śledzenia / estymacji geometrii boiska przez algorytm w czasie rzeczywistym
  void startLiveAlgorithm() {
    _isAlgorithmRunning = true;
    _algorithmTimer?.cancel();

    _algorithmTimer = Timer.periodic(const Duration(milliseconds: 120), (timer) {
      _processedFramesCount++;
      final jitter = (math.sin(_processedFramesCount * 0.15) * 0.8);
      final currentTL = _screenCorners[0];
      final currentBR = _screenCorners[2];

      _screenCorners[0] = Offset(currentTL.dx + (jitter * 0.1), currentTL.dy);
      _screenCorners[2] = Offset(currentBR.dx - (jitter * 0.1), currentBR.dy);

      _algorithmConfidence = (_activeAlgorithm.typicalAccuracy + (math.sin(_processedFramesCount * 0.3) * 0.02)).clamp(0.85, 0.99);

      notifyListeners();
    });
    notifyListeners();
  }

  void stopLiveAlgorithm() {
    _isAlgorithmRunning = false;
    _algorithmTimer?.cancel();
    _algorithmTimer = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _algorithmTimer?.cancel();
    super.dispose();
  }
}
